--[[
	BinaryCacheService.luau
	-----------------------
	Module 5 of 6 - binary serialisation + dirty-detection cache.

	Why binary at all
	-----------------
	A rig can carry hundreds of KeyframeSequences. Storing one Lua table per
	animation in Plugin settings, or one Attribute per animation, costs a lot of
	memory and a lot of JSON/XML text. Instead we pack the *metadata* of every
	animation into one compact binary blob (~60 bytes per animation) and keep a
	single copy of that blob in exactly one place.

	What gets packed, per animation
		name, two independent 32-bit hashes of the name, two independent 32-bit
		hashes of the animation's structural digest, clip length (double, so it
		round-trips exactly), keyframe count, pose count, marker count, priority,
		a flag bitfield, the last uploaded asset id and the upload timestamp.

	Where the blob lives
		Backend "Settings"    -> Plugin:SetSetting (base64url encoded)
		Backend "StringValue" -> one StringValue inside a folder in the rig

	Both backends are TEXT channels:
		* Plugin settings are persisted as JSON.
		* Instance string properties are persisted as XML.
	Neither can carry raw bytes, so the blob is base64url-encoded before it is
	written and decoded immediately after it is read (see Util.base64Encode).

	Roblox limits that are explicitly respected
		* Luau numbers are doubles: only exact up to 2^53. We therefore never
		  rely on a raw 64-bit integer; 64-bit values either use the explicitly
		  sized `I8` option (values far below 2^53) or are split into two exact
		  `I4` halves.
		* `string.pack` integral options check overflow, so all counts are stored
		  as unsigned 32-bit and clamped before packing.
		* Entry count and blob size are hard-capped, so the cache can never grow
		  without bound on a pathological rig.
		* Every read is wrapped in pcall and validated against a magic + version
		  + checksum header; a corrupt blob is discarded, never fatal.
]]

local Util = require(script.Parent.Util)

local BinaryCacheService = {}
BinaryCacheService.__index = BinaryCacheService

local TWO_POW_32 = 4294967296 -- 2^32

-- Header magic. Bumping CACHE_VERSION invalidates every previously written blob.
local MAGIC = "ASUC" -- AnimSaves Uploader Cache
local CACHE_VERSION = 1

-- Per-entry flag bits.
local FLAG_UPLOADED = 1 -- entry has a known asset id
local FLAG_LOOP = 2 -- sequence.Loop == true
local FLAG_VERIFIED = 4 -- asset id cross-checked against UploadedAnimations
local FLAG_AUTO = 8 -- eligible for auto-reupload

BinaryCacheService.FLAG_UPLOADED = FLAG_UPLOADED
BinaryCacheService.FLAG_LOOP = FLAG_LOOP
BinaryCacheService.FLAG_VERIFIED = FLAG_VERIFIED
BinaryCacheService.FLAG_AUTO = FLAG_AUTO
BinaryCacheService.MAGIC = MAGIC
BinaryCacheService.VERSION = CACHE_VERSION

-- Animation states reported by :Analyze().
BinaryCacheService.STATE_NEW = "New" -- no cache entry -> must upload
BinaryCacheService.STATE_CHANGED = "Changed" -- digest mismatch -> must re-upload
BinaryCacheService.STATE_CLEAN = "Clean" -- digest match + asset id known -> skip
BinaryCacheService.STATE_INCOMPLETE = "Incomplete" -- digest match, no asset id -> must upload

--[[
	Probe whether this Luau build supports the explicitly sized `I8` integral
	option of string.pack. It does on every current Roblox client, but the probe
	costs nothing and keeps the module working if that ever changes.
]]
local function supportsInt64(): boolean
	local ok, result = pcall(function()
		local packed = string.pack("<I8", 1)
		if #packed ~= 8 then
			return false
		end
		return string.unpack("<I8", packed) == 1
	end)
	return ok and result == true
end

local INT64_SUPPORTED = supportsInt64()
local INT_FMT = if INT64_SUPPORTED then "I8" else "I4I4"

-- Fields that hold a 64-bit value. `savedAt` is a *header* field, but it must be
-- listed here too: the split-64 read path keys off this table, and omitting it
-- made string.unpack return (hi, lo, nextPos) into a single `value` binding, so
-- `nextPos` silently became the low 32 bits of the timestamp and every
-- following header field was read from a garbage offset.
local WIDE_FIELDS = {
	assetId = true,
	uploadedAt = true,
	savedAt = true,
}

--------------------------------------------------------------------------------
-- Pack formats: one tiny format per field.
--------------------------------------------------------------------------------

local ENTRY_FIELDS = {
	name = "<s2",
	nameHashA = "<I4",
	nameHashB = "<I4",
	digestA = "<I4",
	digestB = "<I4",
	length = "<d", -- double: exact round-trip for clip lengths
	keyframes = "<I4",
	poses = "<I4",
	markers = "<I4",
	priority = "<I1",
	flags = "<I1",
	assetId = "<" .. INT_FMT,
	uploadedAt = "<" .. INT_FMT,
}

-- Fixed serialisation order for one entry.
local ENTRY_ORDER = {
	"name",
	"nameHashA",
	"nameHashB",
	"digestA",
	"digestB",
	"length",
	"keyframes",
	"poses",
	"markers",
	"priority",
	"flags",
	"assetId",
	"uploadedAt",
}

local HEADER_FIELDS = {
	magic = "<c4",
	version = "<I1",
	globalFlags = "<I1",
	entryCount = "<I4",
	rigName = "<s2",
	savedAt = "<" .. INT_FMT,
	checksum = "<I4",
}

local HEADER_ORDER = { "magic", "version", "globalFlags", "entryCount", "rigName", "savedAt", "checksum" }

local function clampU32(value: number): number
	if value ~= value or value < 0 then -- NaN / negative guard
		return 0
	end
	return math.min(math.floor(value), TWO_POW_32 - 1)
end

local function clampU8(value: number): number
	return math.min(math.max(math.floor(value), 0), 255)
end

--[[
	Packs a 64-bit value in the layout :Deserialize() reads back.

	With I8 support this is one option. Without it the value is split into two
	exact unsigned 32-bit halves. The split is only lossless while the value
	stays below 2^53, which is the exact-integer range of a Luau double and is
	the module-wide hard limit on every 64-bit value it stores (see the header
	comment). Both halves are < 2^32 by construction, so they always fit I4.

	The reader's counterpart is `hi * TWO_POW_32 + lo`.
]]
local function packWide(value: number): string
	if INT64_SUPPORTED then
		return string.pack("<I8", value)
	end
	local hi = math.floor(value / TWO_POW_32)
	local lo = value - hi * TWO_POW_32
	return string.pack("<I4I4", clampU32(hi), clampU32(lo))
end

--------------------------------------------------------------------------------
-- Digest accumulator
-- Streams bytes into two independent hashes, so a multi-megabyte animation never
-- needs a large temporary buffer.
--------------------------------------------------------------------------------

local Digest = {}
Digest.__index = Digest

function Digest.new()
	return setmetatable({ a = 0x811C9DC5, b = 5381 }, Digest)
end

function Digest:bytes(chunk: string)
	if #chunk == 0 then
		return
	end
	self.a = Util.fnv1a32(chunk, self.a)
	self.b = Util.djb2(chunk, self.b)
end

function Digest:number(value: number)
	self:bytes(string.pack("<d", value))
end

function Digest:text(value: string)
	self:number(#value)
	self:bytes(value)
end

--------------------------------------------------------------------------------
-- Types
--------------------------------------------------------------------------------

export type CacheEntry = {
	name: string,
	nameHashA: number,
	nameHashB: number,
	digestA: number,
	digestB: number,
	length: number,
	keyframes: number,
	poses: number,
	markers: number,
	priority: number,
	flags: number,
	assetId: number,
	uploadedAt: number,
}

export type AnalysisRecord = {
	sequence: KeyframeSequence,
	name: string,
	subPath: string,
	depth: number,
	state: string,
	dirty: boolean,
	cached: boolean,
	digestA: number,
	digestB: number,
	nameHashA: number,
	nameHashB: number,
	length: number,
	keyframes: number,
	poses: number,
	markers: number,
	priority: number,
	flags: number,
	cachedAssetId: number,
	cachedUploadedAt: number,
	selected: boolean,
}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function BinaryCacheService.new(options: { [string]: any }?): BinaryCacheService
	local self = setmetatable({}, BinaryCacheService)

	self._options = {
		-- "Settings" or "StringValue"
		Backend = "Settings",
		-- "Deep" walks every keyframe/pose; "Fast" only hashes cheap metadata.
		HashMode = "Deep",
		-- StringValue backend layout.
		CacheFolderName = "_AnimUploaderCache",
		CacheValueName = "BinaryCache",
		-- Hard caps. 10k animations * ~60 B ~= 600 KB.
		MaxEntries = 10000,
		MaxBlobBytes = 1048576,
		-- Yield every N poses while hashing so Studio never stalls.
		YieldEvery = 4000,
	}
	if options then
		for key, value in pairs(options) do
			self._options[key] = value
		end
	end

	self._plugin = nil -- Plugin?
	self._rigInstance = nil -- Instance?
	self._entries = {} -- { [string]: CacheEntry }
	self._order = {} -- { string }
	self._blob = ""
	self._rigName = nil -- string?
	self._savedAt = 0
	self._globalFlags = 0
	self._dirty = false
	self._loaded = false
	self._lastError = nil -- string?
	self._stats = { entries = 0, blobBytes = 0, encodedBytes = 0 }

	return self
end

function BinaryCacheService:SetPlugin(pluginInstance: Plugin?)
	self._plugin = pluginInstance
	return self
end

function BinaryCacheService:SetRigInstance(rig: Instance?)
	self._rigInstance = rig
	if rig then
		self._rigName = rig.Name
	end
	return self
end

function BinaryCacheService:GetLastError(): string?
	return self._lastError
end

function BinaryCacheService:IsDirty(): boolean
	return self._dirty
end

function BinaryCacheService:Count(): number
	local n = 0
	for _ in pairs(self._entries) do
		n += 1
	end
	return n
end

function BinaryCacheService:GetStats()
	self._stats.entries = self:Count()
	self._stats.blobBytes = #self._blob
	return self._stats
end

--------------------------------------------------------------------------------
-- Digest computation
--------------------------------------------------------------------------------

--[[
	Computes the structural digest of a KeyframeSequence.

	Deep mode feeds, in a deterministic order:
		sequence name, Loop, Priority, keyframe count
		for each keyframe (sorted by Time then Name):
			Time, Name, marker count, each marker's name and value
			for each pose in pre-order:
				Name, Weight, EasingStyle, EasingDirection, all 12 CFrame components

	Fast mode only hashes cheap metadata (name, Loop, Priority, keyframe count,
	length). It is roughly an order of magnitude faster and is the right choice
	for 1000+ animation libraries where a full re-hash would be noticeable.

	Returns digestA, digestB, meta.
]]
function BinaryCacheService:ComputeDigest(sequence: KeyframeSequence, yieldHook: (() -> ())?)
	local digest = Digest.new()
	local meta = { length = 0, keyframes = 0, poses = 0, markers = 0, priority = 0 }

	digest:text(sequence.Name)

	local loopOk, loop = pcall(function()
		return sequence.Loop
	end)
	digest:number(if loopOk then (if loop then 1 else 0) else 0)

	local prioOk, priority = pcall(function()
		return sequence.Priority
	end)
	local priorityValue = 0
	if prioOk and typeof(priority) == "EnumItem" then
		priorityValue = priority.Value
	end
	meta.priority = priorityValue
	digest:number(priorityValue)

	local keyframes: { Keyframe } = {}
	local kfOk = pcall(function()
		return sequence:GetKeyframes()
	end)
	if kfOk then
		keyframes = sequence:GetKeyframes()
	end
	meta.keyframes = #keyframes
	digest:number(#keyframes)

	-- Deterministic keyframe order.
	local sortedKeyframes = table.clone(keyframes)
	table.sort(sortedKeyframes, function(a, b)
		if a.Time == b.Time then
			return a.Name < b.Name
		end
		return a.Time < b.Time
	end)

	if self._options.HashMode == "Fast" then
		for _, keyframe in ipairs(sortedKeyframes) do
			if keyframe.Time > meta.length then
				meta.length = keyframe.Time
			end
		end
		digest:number(meta.length)
		return digest.a, digest.b, meta
	end

	local yieldCounter = 0
	local yieldEvery = math.max(1, math.floor(self._options.YieldEvery))

	local function hashPose(pose: Pose)
		meta.poses += 1
		digest:text(pose.Name)
		digest:number(pose.Weight)

		local styleOk, style = pcall(function()
			return pose.EasingStyle
		end)
		digest:number(if styleOk and typeof(style) == "EnumItem" then style.Value else -1)

		local dirOk, direction = pcall(function()
			return pose.EasingDirection
		end)
		digest:number(if dirOk and typeof(direction) == "EnumItem" then direction.Value else -1)

		-- All 12 CFrame components packed in one call instead of twelve.
		local cfOk, components = pcall(function()
			return { pose.CFrame:GetComponents() }
		end)
		if cfOk and #components == 12 then
			digest:bytes(string.pack("<dddddddddddd", table.unpack(components, 1, 12)))
		else
			digest:number(0)
		end

		yieldCounter += 1
		if yieldHook and yieldCounter % yieldEvery == 0 then
			yieldHook()
		end

		local subOk, subPoses = pcall(function()
			return pose:GetSubPoses()
		end)
		if subOk then
			local sorted = table.clone(subPoses)
			table.sort(sorted, function(a, b)
				return a.Name < b.Name
			end)
			for _, sub in ipairs(sorted) do
				if sub:IsA("Pose") then
					hashPose(sub)
				end
			end
		end
	end

	for _, keyframe in ipairs(sortedKeyframes) do
		if keyframe.Time > meta.length then
			meta.length = keyframe.Time
		end
		digest:number(keyframe.Time)
		digest:text(keyframe.Name)

		local markers: { KeyframeMarker } = {}
		local mkOk = pcall(function()
			return keyframe:GetMarkers()
		end)
		if mkOk then
			markers = keyframe:GetMarkers()
		end
		meta.markers += #markers
		digest:number(#markers)
		table.sort(markers, function(a, b)
			return a.Name < b.Name
		end)
		for _, marker in ipairs(markers) do
			digest:text(marker.Name)
			digest:number(marker.Value)
		end

		local poses: { Pose } = {}
		local pOk = pcall(function()
			return keyframe:GetPoses()
		end)
		if pOk then
			poses = keyframe:GetPoses()
		end
		digest:number(#poses)

		local sortedPoses = table.clone(poses)
		table.sort(sortedPoses, function(a, b)
			return a.Name < b.Name
		end)
		for _, pose in ipairs(sortedPoses) do
			if pose:IsA("Pose") then
				hashPose(pose)
			end
		end

		if yieldHook then
			yieldHook()
		end
	end

	return digest.a, digest.b, meta
end

--------------------------------------------------------------------------------
-- Serialisation
--------------------------------------------------------------------------------

local function serializeEntry(entry: CacheEntry): string
	local parts = table.create(#ENTRY_ORDER)
	for _, field in ipairs(ENTRY_ORDER) do
		-- Wide fields go through packWide so the I8 and I4I4 layouts stay in
		-- sync with what deserializeEntry expects.
		if WIDE_FIELDS[field] then
			parts[#parts + 1] = packWide(entry[field])
		else
			parts[#parts + 1] = string.pack(ENTRY_FIELDS[field], entry[field])
		end
	end
	return table.concat(parts)
end

--[[
	Reads one entry out of `blob` starting at `pos`.
	Returns entry, nextPosition. Returns nil, nil when the blob is truncated.
]]
local function deserializeEntry(blob: string, pos: number): (CacheEntry?, number?)
	local cursor = pos
	local values: { [string]: any } = {}

	for _, field in ipairs(ENTRY_ORDER) do
		local fmt = ENTRY_FIELDS[field]

		if WIDE_FIELDS[field] and not INT64_SUPPORTED then
			-- Split-64 layout: (hi, lo, nextPos)
			local ok, hi, lo, nextPos = pcall(string.unpack, fmt, blob, cursor)
			if not ok or type(nextPos) ~= "number" then
				return nil, nil
			end
			values[field] = hi * TWO_POW_32 + lo
			cursor = nextPos
		else
			local ok, value, nextPos = pcall(string.unpack, fmt, blob, cursor)
			if not ok or type(nextPos) ~= "number" then
				return nil, nil
			end
			values[field] = value
			cursor = nextPos
		end
	end

	local entry: CacheEntry = {
		name = values.name,
		nameHashA = values.nameHashA,
		nameHashB = values.nameHashB,
		digestA = values.digestA,
		digestB = values.digestB,
		length = values.length,
		keyframes = values.keyframes,
		poses = values.poses,
		markers = values.markers,
		priority = values.priority,
		flags = values.flags,
		assetId = values.assetId,
		uploadedAt = values.uploadedAt,
	}
	return entry, cursor
end

--[[
	Serialises the whole cache into a single binary string.
]]
function BinaryCacheService:Serialize(): string
	-- Rebuild a stable, de-duplicated order list.
	local seen: { [string]: boolean } = {}
	local names: { string } = {}
	for _, name in ipairs(self._order) do
		if self._entries[name] and not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end
	for name in pairs(self._entries) do
		if not seen[name] then
			seen[name] = true
			table.insert(names, name)
		end
	end

	local body = table.create(#names)
	for _, name in ipairs(names) do
		body[#body + 1] = serializeEntry(self._entries[name])
	end
	local bodyBlob = table.concat(body)

	local headerParts = table.create(#HEADER_ORDER)
	for _, field in ipairs(HEADER_ORDER) do
		local value
		if field == "magic" then
			value = MAGIC
		elseif field == "version" then
			value = CACHE_VERSION
		elseif field == "globalFlags" then
			value = clampU8(self._globalFlags)
		elseif field == "entryCount" then
			value = clampU32(#names)
		elseif field == "rigName" then
			value = self._rigName or ""
		elseif field == "checksum" then
			value = clampU32(Util.fnv1a32(bodyBlob))
		end
		if field == "savedAt" then
			-- Same wide-field treatment as the entry body.
			headerParts[#headerParts + 1] = packWide(math.floor(self._savedAt))
		else
			headerParts[#headerParts + 1] = string.pack(HEADER_FIELDS[field], value)
		end
	end

	self._order = names
	return table.concat(headerParts) .. bodyBlob
end

--[[
	Parses a blob produced by :Serialize(). Returns true on success.
	A malformed blob is reported through GetLastError() and leaves the cache empty.
]]
function BinaryCacheService:Deserialize(blob: string): boolean
	self._lastError = nil
	self._entries = {}
	self._order = {}

	if type(blob) ~= "string" or #blob < 16 then
		self._lastError = "Cache blob is empty or too small."
		return false
	end

	local ok, err = pcall(function()
		local cursor = 1
		local values: { [string]: any } = {}

		for _, field in ipairs(HEADER_ORDER) do
			local fmt = HEADER_FIELDS[field]
			if WIDE_FIELDS[field] and not INT64_SUPPORTED then
				local unpackOk, hi, lo, nextPos = pcall(string.unpack, fmt, blob, cursor)
				if not unpackOk or type(nextPos) ~= "number" then
					error("truncated header field " .. field, 0)
				end
				values[field] = hi * TWO_POW_32 + lo
				cursor = nextPos
			else
				local unpackOk, value, nextPos = pcall(string.unpack, fmt, blob, cursor)
				if not unpackOk or type(nextPos) ~= "number" then
					error("truncated header field " .. field, 0)
				end
				values[field] = value
				cursor = nextPos
			end
		end

		if values.magic ~= MAGIC then
			error("bad magic", 0)
		end
		if values.version ~= CACHE_VERSION then
			error("unsupported cache version " .. tostring(values.version), 0)
		end

		local body = blob:sub(cursor)
		if Util.fnv1a32(body) ~= values.checksum then
			error("checksum mismatch", 0)
		end

		self._rigName = values.rigName
		self._savedAt = values.savedAt
		self._globalFlags = values.globalFlags

		local readPos = 1
		local limit = math.min(values.entryCount, self._options.MaxEntries)
		for _ = 1, limit do
			local entry, nextPos = deserializeEntry(body, readPos)
			if not entry then
				break
			end
			if not self._entries[entry.name] then
				table.insert(self._order, entry.name)
			end
			self._entries[entry.name] = entry
			readPos = nextPos
		end
	end)

	if not ok then
		self._lastError = tostring(err)
		self._entries = {}
		self._order = {}
		return false
	end

	self._loaded = true
	return true
end

--------------------------------------------------------------------------------
-- Persistence
--------------------------------------------------------------------------------

--[[
	Builds a Plugin-settings key that is guaranteed JSON-safe.

	Plugin settings are stored as a JSON object and the docs explicitly warn that
	periods, quotes, backslashes and newlines in KEYS can corrupt the settings
	file. A rig's full name contains periods and dots, so it never goes into the
	key verbatim: it is sanitised and then fingerprinted with two hashes.
]]
local function buildSettingsKey(rigName: string): string
	local sanitized = (rigName:gsub("[^%w_]", "_")):sub(1, 48)
	local hashA, hashB = Util.hash64(rigName)
	return string.format("AnimSavesCache_v%d_%s_%d_%d", CACHE_VERSION, sanitized, hashA, hashB)
end

BinaryCacheService.BuildSettingsKey = buildSettingsKey

--[[
	Finds (never creates) the StringValue used by the "StringValue" backend.
]]
function BinaryCacheService:FindCacheValue(rig: Instance?): StringValue?
	if not rig then
		return nil
	end
	local folder = rig:FindFirstChild(self._options.CacheFolderName)
	if not folder or not folder:IsA("Folder") then
		return nil
	end
	local value = folder:FindFirstChild(self._options.CacheValueName)
	if not value or not value:IsA("StringValue") then
		return nil
	end
	return value :: StringValue
end

--[[
	Finds or creates the StringValue used by the "StringValue" backend.
]]
function BinaryCacheService:GetCacheValue(rig: Instance?): StringValue?
	if not rig then
		return nil
	end
	local existing = self:FindCacheValue(rig)
	if existing then
		return existing
	end

	local folder = rig:FindFirstChild(self._options.CacheFolderName)
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = self._options.CacheFolderName
		folder.Parent = rig
	end

	local value = Instance.new("StringValue")
	value.Name = self._options.CacheValueName
	value.Parent = folder
	return value
end

--[[
	Loads the cache for `rig` using the configured backend.
	Returns true when a valid blob was found and parsed. A missing blob is not an
	error - it just means this rig has never been uploaded from here.
]]
function BinaryCacheService:Load(rig: Instance?): boolean
	self._entries = {}
	self._order = {}
	self._loaded = false
	self._lastError = nil

	if not rig then
		self._lastError = "No rig to load a cache for."
		return false
	end

	self._rigName = rig.Name
	self._rigInstance = rig

	local encoded: any = nil

	if self._options.Backend == "StringValue" then
		local value = self:FindCacheValue(rig)
		encoded = if value then value.Value else nil
	else
		if not self._plugin then
			self._lastError = "Settings backend requires a Plugin reference."
			return false
		end
		local ok, stored = pcall(function()
			return (self._plugin :: Plugin):GetSetting(buildSettingsKey(rig.Name))
		end)
		encoded = if ok then stored else nil
	end

	if type(encoded) ~= "string" or #encoded == 0 then
		self._savedAt = 0
		return false
	end

	local decoded: string? = nil
	local ok, err = pcall(function()
		decoded = Util.base64Decode(encoded)
	end)
	if not ok or not decoded then
		-- Fall back to hex in case an older build wrote that format.
		ok, err = pcall(function()
			decoded = Util.hexDecode(encoded)
		end)
		if not ok or not decoded then
			self._lastError = "Cache blob could not be decoded: " .. tostring(err)
			return false
		end
	end

	return self:Deserialize(decoded)
end

--[[
	Persists the cache. Returns true on success.
]]
function BinaryCacheService:Save(): boolean
	self._savedAt = os.time()
	local blob = self:Serialize()

	if #blob > self._options.MaxBlobBytes then
		self._lastError = string.format(
			"Cache blob is %d bytes, over the %d byte limit - dropping oldest entries.",
			#blob,
			self._options.MaxBlobBytes
		)
		self:PruneOldest(math.ceil(self:Count() * 0.25))
		blob = self:Serialize()
		if #blob > self._options.MaxBlobBytes then
			return false
		end
	end

	local encoded = Util.base64Encode(blob)
	self._blob = blob
	self._stats.blobBytes = #blob
	self._stats.encodedBytes = #encoded
	self._dirty = false

	if self._options.Backend == "StringValue" then
		if not self._rigInstance then
			self._lastError = "StringValue backend needs the rig instance."
			return false
		end
		local value = self:GetCacheValue(self._rigInstance)
		if not value then
			return false
		end
		value.Value = encoded
		return true
	end

	if not self._plugin then
		self._lastError = "Settings backend requires a Plugin reference."
		return false
	end

	local key = buildSettingsKey(self._rigName or "unknown")
	local ok, err = pcall(function()
		(self._plugin :: Plugin):SetSetting(key, encoded)
	end)
	if not ok then
		self._lastError = "SetSetting failed: " .. tostring(err)
		return false
	end

	-- The docs warn SetSetting can silently fail when several Studio windows
	-- share the settings file, so verify the write.
	local verifyOk, stored = pcall(function()
		return (self._plugin :: Plugin):GetSetting(key)
	end)
	if not verifyOk or stored ~= encoded then
		self._lastError = "SetSetting did not persist (another Studio window may be writing)."
		return false
	end

	return true
end

--------------------------------------------------------------------------------
-- Dirty detection
--------------------------------------------------------------------------------

--[[
	Analyses a RigScanner result against the loaded cache.

	For every sequence we compute the structural digest, look for a cache entry
	with the same name, and classify:

		New        - no cache entry                         -> dirty
		Changed    - digest mismatch                        -> dirty
		Clean      - digest match and FLAG_UPLOADED set     -> not dirty
		Incomplete - digest match but no asset id recorded  -> dirty

	Returns an array of AnalysisRecord in the same order as the scanner's entries
	so UI rows stay aligned.
]]
function BinaryCacheService:Analyze(scanResult: any, yieldHook: (() -> ())?): { AnalysisRecord }
	local records: { AnalysisRecord } = {}

	for _, entry in ipairs(scanResult.entries or {}) do
		local sequence = entry.sequence
		local nameA, nameB = Util.hash64(sequence.Name)
		local digestA, digestB, meta = self:ComputeDigest(sequence, yieldHook)

		local cached: CacheEntry? = self._entries[sequence.Name]
		local state: string
		local dirty: boolean

		if not cached then
			state = BinaryCacheService.STATE_NEW
			dirty = true
		elseif cached.digestA ~= digestA or cached.digestB ~= digestB or cached.nameHashA ~= nameA or cached.nameHashB ~= nameB then
			state = BinaryCacheService.STATE_CHANGED
			dirty = true
		elseif bit32.band(cached.flags, FLAG_UPLOADED) ~= 0 and cached.assetId > 0 then
			state = BinaryCacheService.STATE_CLEAN
			dirty = false
		else
			state = BinaryCacheService.STATE_INCOMPLETE
			dirty = true
		end

		table.insert(records, {
			sequence = sequence,
			name = sequence.Name,
			subPath = entry.subPath or "",
			depth = entry.depth or 1,
			state = state,
			dirty = dirty,
			cached = cached ~= nil,
			digestA = digestA,
			digestB = digestB,
			nameHashA = nameA,
			nameHashB = nameB,
			length = meta.length,
			keyframes = meta.keyframes,
			poses = meta.poses,
			markers = meta.markers,
			priority = meta.priority,
			flags = if cached then cached.flags else 0,
			cachedAssetId = if cached then cached.assetId else 0,
			cachedUploadedAt = if cached then cached.uploadedAt else 0,
			selected = dirty,
		})
	end

	return records
end

--[[
	Records a successful upload and marks the entry clean.
]]
function BinaryCacheService:MarkUploaded(record: AnalysisRecord, assetId: number)
	local flags = bit32.bor(record.flags, FLAG_UPLOADED)

	local loopOk, loop = pcall(function()
		return record.sequence.Loop
	end)
	if loopOk and loop then
		flags = bit32.bor(flags, FLAG_LOOP)
	end

	local entry: CacheEntry = {
		name = record.name,
		nameHashA = record.nameHashA,
		nameHashB = record.nameHashB,
		digestA = record.digestA,
		digestB = record.digestB,
		length = record.length,
		keyframes = record.keyframes,
		poses = record.poses,
		markers = record.markers,
		priority = record.priority,
		flags = flags,
		assetId = math.floor(assetId),
		uploadedAt = os.time(),
	}

	if not self._entries[record.name] then
		table.insert(self._order, record.name)
	end
	self._entries[record.name] = entry

	self:EnforceLimits()
	self._dirty = true
end

--[[
	Forces an entry back to the dirty state without deleting it, so the UI shows
	"Changed" and the uploader will not skip it.
]]
function BinaryCacheService:MarkDirty(name: string)
	local entry = self._entries[name]
	if not entry then
		return
	end
	entry.flags = bit32.band(entry.flags, bit32.bnot(FLAG_UPLOADED))
	entry.assetId = 0
	self._dirty = true
end

--[[
	Drops cache entries that no longer exist in the rig, so the blob does not grow
	forever as animations are renamed or deleted. Returns the number removed.
]]
function BinaryCacheService:PruneOrphans(scanResult: any): number
	local live: { [string]: boolean } = {}
	for _, entry in ipairs(scanResult.entries or {}) do
		live[entry.name] = true
	end

	local removed = 0
	for name in pairs(self._entries) do
		if not live[name] then
			self._entries[name] = nil
			removed += 1
		end
	end

	if removed > 0 then
		local cleaned: { string } = {}
		for _, name in ipairs(self._order) do
			if self._entries[name] then
				table.insert(cleaned, name)
			end
		end
		self._order = cleaned
		self._dirty = true
	end

	return removed
end

--[[
	Drops the oldest N entries (by upload timestamp). Returns the number removed.
]]
function BinaryCacheService:PruneOldest(count: number): number
	if count <= 0 or self:Count() == 0 then
		return 0
	end

	local list = table.clone(self._order)
	table.sort(list, function(a, b)
		return (self._entries[a].uploadedAt or 0) < (self._entries[b].uploadedAt or 0)
	end)

	local removed = 0
	for i = 1, math.min(count, #list) do
		if self._entries[list[i]] then
			self._entries[list[i]] = nil
			removed += 1
		end
	end

	if removed > 0 then
		local cleaned: { string } = {}
		for _, name in ipairs(self._order) do
			if self._entries[name] then
				table.insert(cleaned, name)
			end
		end
		self._order = cleaned
		self._dirty = true
	end

	return removed
end

function BinaryCacheService:EnforceLimits()
	local guard = 0
	while self:Count() > self._options.MaxEntries and guard < 100 do
		if self:PruneOldest(math.ceil(self._options.MaxEntries * 0.1)) == 0 then
			break
		end
		guard += 1
	end
end

function BinaryCacheService:GetEntry(name: string): CacheEntry?
	return self._entries[name]
end

function BinaryCacheService:GetEntries(): { CacheEntry }
	local out = {}
	for _, name in ipairs(self._order) do
		if self._entries[name] then
			table.insert(out, self._entries[name])
		end
	end
	return out
end

--[[
	Wipes the in-memory cache and the persisted blob.
]]
function BinaryCacheService:Reset(rig: Instance?)
	if rig then
		self._rigName = rig.Name
		self._rigInstance = rig
	end

	self._entries = {}
	self._order = {}
	self._blob = ""
	self._savedAt = 0
	self._dirty = false
	self._lastError = nil

	if self._options.Backend == "StringValue" then
		local value = self:GetCacheValue(self._rigInstance)
		if value then
			value.Value = ""
		end
	elseif self._plugin then
		pcall(function()
			(self._plugin :: Plugin):SetSetting(buildSettingsKey(self._rigName or "unknown"), "")
		end)
	end
end

--[[
	Human-readable summary used by the UI and the log.
]]
function BinaryCacheService:Describe(): string
	return string.format(
		"%s backend | %s hash | %d entries | %s blob (%s encoded) | v%d%s",
		self._options.Backend,
		self._options.HashMode,
		self:Count(),
		Util.formatBytes(#self._blob),
		Util.formatBytes(#Util.base64Encode(self._blob)),
		CACHE_VERSION,
		if self._dirty then " | UNSAVED" else ""
	)
end

return BinaryCacheService
