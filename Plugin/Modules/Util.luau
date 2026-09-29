--[[
	Util.luau
	---------
	Shared, dependency-free helpers used by every module of the AnimSaves
	Bulk Uploader plugin.

	Nothing in this module touches Roblox instances, so it can be unit-tested
	in isolation and reused by the command-bar version of the tool.

	Contents
	1. mulMod32          - exact (a * b) mod 2^32 for doubles (16-bit limbs)
	2. fnv1a32 / djb2    - two independent, streamable 32-bit hashes
	3. base64url         - JSON/XML-safe text encoding for binary blobs
	4. hex               - fallback text encoding (used only if base64 fails)
	5. formatting helpers
	6. table helpers
]]

local Util = {}

local TWO_POW_32 = 4294967296 -- 2^32

--------------------------------------------------------------------------------
-- 1. Exact 32-bit modular multiplication
--------------------------------------------------------------------------------

--[[
	Luau numbers are IEEE-754 doubles, so they are only exact up to 2^53.
	A naive `(a * b) % 2^32` silently loses precision once a * b > 2^53,
	which corrupts hashes. We therefore split `a` into two 16-bit limbs and
	multiply each limb separately; every intermediate product stays below
	2^48 and is therefore exact.
]]
local function mulMod32(a: number, b: number): number
	local aHi = math.floor(a / 65536)
	local aLo = a % 65536
	local hi = (aHi * b) % TWO_POW_32
	local lo = (aLo * b) % TWO_POW_32
	return (hi * 65536 + lo) % TWO_POW_32
end

Util.mulMod32 = mulMod32

--------------------------------------------------------------------------------
-- 2. Streaming hashes
--------------------------------------------------------------------------------

--[[
	FNV-1a (32-bit). Streamable: it can be fed one byte at a time, which lets
	BinaryCacheService hash multi-megabyte animations without ever building a
	giant intermediate string.

	Returns an integer in [0, 2^32).
]]
function Util.fnv1a32(bytes: string, seed: number?): number
	local h = seed or 0x811C9DC5
	local prime = 0x01000193
	for i = 1, #bytes do
		h = mulMod32(bit32.bxor(h, string.byte(bytes, i)), prime)
	end
	return h
end

--[[
	djb2-x. Also streamable, completely independent of FNV-1a.
	Packing *two* unrelated hashes gives a 64-bit effective digest, which makes
	an accidental collision between two different animations negligible.
]]
function Util.djb2(bytes: string, seed: number?): number
	local h = seed or 5381
	for i = 1, #bytes do
		h = (h * 33 + string.byte(bytes, i)) % TWO_POW_32
	end
	return h
end

--[[
	Convenience wrapper: returns both hashes for a byte string.
]]
function Util.hash64(bytes: string): (number, number)
	return Util.fnv1a32(bytes), Util.djb2(bytes)
end

--------------------------------------------------------------------------------
-- 3. base64url - JSON / XML safe text encoding
--------------------------------------------------------------------------------

--[[
	Why this exists
	---------------
	`Plugin:SetSetting` stores values as JSON and Roblox instance string
	properties are serialized as XML text. Neither can carry raw binary bytes
	(0x00-0x1F, backslashes, quotes, ...). Every binary blob produced by
	BinaryCacheService is therefore encoded with base64url before it is stored.

	We use a URL-safe alphabet and drop '=' padding so the output contains only
	[A-Za-z0-9-_], which is safe in JSON strings, XML text and plugin setting keys.
]]
local B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local B64_REVERSE: { [string]: number } = {}
for i = 1, 64 do
	B64_REVERSE[B64_ALPHABET:sub(i, i)] = i - 1
end

--[[
	Encodes arbitrary bytes (including embedded NULs) as base64url text with
	standard '=' padding.

	The alphabet is URL-safe ([A-Za-z0-9-_]) so the result survives JSON and XML
	verbatim; '=' padding is safe in both.
]]
function Util.base64Encode(input: string): string
	local out = {}
	local n = #input
	local i = 1
	while i <= n do
		local b1 = string.byte(input, i)
		local b2 = string.byte(input, i + 1)
		local b3 = string.byte(input, i + 2)

		-- 6 bits of b1.
		out[#out + 1] = B64_ALPHABET:sub(bit32.rshift(b1, 2) + 1, bit32.rshift(b1, 2) + 1)

		-- Low 2 bits of b1 + high 4 bits of b2.
		local c2 = bit32.band(bit32.lshift(b1, 4), 0x30)
		if b2 then
			c2 = bit32.bor(c2, bit32.rshift(b2, 4))
		end
		out[#out + 1] = B64_ALPHABET:sub(c2 + 1, c2 + 1)

		if not b2 then
			-- 1 input byte left -> two padding chars.
			out[#out + 1] = "="
			out[#out + 1] = "="
			break
		end

		-- Low 4 bits of b2 + high 2 bits of b3.
		local c3 = bit32.band(bit32.lshift(b2, 2), 0x3C)
		if b3 then
			c3 = bit32.bor(c3, bit32.rshift(b3, 6))
		end
		out[#out + 1] = B64_ALPHABET:sub(c3 + 1, c3 + 1)

		if not b3 then
			-- 2 input bytes left -> one padding char.
			out[#out + 1] = "="
			break
		end

		-- Low 6 bits of b3.
		out[#out + 1] = B64_ALPHABET:sub(bit32.band(b3, 0x3F) + 1, bit32.band(b3, 0x3F) + 1)
		i += 3
	end
	return table.concat(out)
end

--[[
	Decodes base64url text back into raw bytes.

	Padding is honoured: a group ending in '=' yields fewer than three bytes.
	Errors on malformed input (bad length, invalid character, or '=' in a
	non-final group) rather than silently returning corrupted data.
]]
function Util.base64Decode(input: string): string
	if #input % 4 ~= 0 then
		error("Util.base64Decode: invalid base64 length " .. tostring(#input), 2)
	end

	local out = {}
	local n = #input
	local groups = n // 4

	for group = 0, groups - 1 do
		local base = group * 4
		local c1ch = input:sub(base + 1, base + 1)
		local c2ch = input:sub(base + 2, base + 2)
		local c3ch = input:sub(base + 3, base + 3)
		local c4ch = input:sub(base + 4, base + 4)

		local c1 = B64_REVERSE[c1ch]
		local c2 = B64_REVERSE[c2ch]
		if not (c1 and c2) then
			error("Util.base64Decode: invalid base64 character", 2)
		end

		-- '=' may only appear in the final group, and only as trailing chars.
		local lastGroup = group == groups - 1
		local pad3, pad4 = c3ch == "=", c4ch == "="
		if (pad3 or pad4) and not lastGroup then
			error("Util.base64Decode: padding character in a non-final group", 2)
		end
		if pad3 and not pad4 then
			error("Util.base64Decode: invalid padding", 2)
		end

		local c3 = if pad3 then 0 else B64_REVERSE[c3ch]
		local c4 = if pad4 then 0 else B64_REVERSE[c4ch]
		if c3 == nil or c4 == nil then
			error("Util.base64Decode: invalid base64 character", 2)
		end

		local v = bit32.bor(bit32.lshift(c1, 18), bit32.lshift(c2, 12), bit32.lshift(c3, 6), c4)

		out[#out + 1] = string.char(bit32.band(bit32.rshift(v, 16), 0xFF))
		if not pad3 then
			out[#out + 1] = string.char(bit32.band(bit32.rshift(v, 8), 0xFF))
		end
		if not pad4 then
			out[#out + 1] = string.char(bit32.band(v, 0xFF))
		end
	end

	return table.concat(out)
end

--------------------------------------------------------------------------------
-- 4. hex encoding (fallback)
--------------------------------------------------------------------------------

local HEX = "0123456789abcdef"

function Util.hexEncode(input: string): string
	local out = table.create(#input * 2)
	for i = 1, #input do
		local b = string.byte(input, i)
		out[i * 2 - 1] = HEX:sub(bit32.rshift(b, 4) + 1, bit32.rshift(b, 4) + 1)
		out[i * 2] = HEX:sub(bit32.band(b, 0x0F) + 1, bit32.band(b, 0x0F) + 1)
	end
	return table.concat(out)
end

function Util.hexDecode(input: string): string
	if #input % 2 ~= 0 then
		error("Util.hexDecode: odd length", 2)
	end
	local out = table.create(#input // 2)
	for i = 1, #input // 2 do
		local hi = HEX:find(input:sub(i * 2 - 1, i * 2 - 1), 1, true) - 1
		local lo = HEX:find(input:sub(i * 2, i * 2), 1, true) - 1
		out[i] = string.char(hi * 16 + lo)
	end
	return table.concat(out)
end

--[[
	Round-trip self test. Returns true when both encoders survive encode->decode.
	Called once by MainPlugin at startup; a failure downgrades the cache to the
	hex backend rather than crashing the plugin.
]]
function Util.selftestEncodings(): (boolean, boolean)
	-- Cover every padding path: lengths 0, 1, 2 mod 3 plus all 256 byte values.
	local samples = {
		"",
		"M",
		"Ma",
		"Man",
		string.char(0, 1, 2, 253, 254, 255, 65, 66, 67, 0, 10, 13, 34, 92),
	}
	for i = 0, 255 do
		samples[#samples + 1] = string.char(i)
		samples[#samples + 1] = string.char(i, i)
		samples[#samples + 1] = string.char(i, i, i)
	end

	local ok64, okHex = true, true
	for _, sample in ipairs(samples) do
		if Util.base64Decode(Util.base64Encode(sample)) ~= sample then
			ok64 = false
			break
		end
	end
	for _, sample in ipairs(samples) do
		if Util.hexDecode(Util.hexEncode(sample)) ~= sample then
			okHex = false
			break
		end
	end

	-- The alphabet must stay JSON/XML safe.
	local encoded = Util.base64Encode(table.concat(samples))
	for i = 1, #encoded do
		local b = string.byte(encoded, i)
		local safe = (b >= 65 and b <= 90) or (b >= 97 and b <= 122) or (b >= 48 and b <= 57) or b == 45 or b == 95 or b == 61
		if not safe then
			ok64 = false
			break
		end
	end

	return ok64, okHex
end

--------------------------------------------------------------------------------
-- 5. Formatting helpers
--------------------------------------------------------------------------------

--[[
	Formats seconds as `m:ss.s` (e.g. 74.25 -> "1:14.2").
]]
function Util.formatDuration(seconds: number): string
	if not seconds or seconds ~= seconds or seconds < 0 then
		return "0:00.0"
	end
	local minutes = math.floor(seconds / 60)
	local secs = seconds - minutes * 60
	return string.format("%d:%04.1f", minutes, secs)
end

--[[
	Formats a byte count using binary-ish units.
]]
function Util.formatBytes(bytes: number): string
	if bytes < 1024 then
		return string.format("%d B", bytes)
	elseif bytes < 1024 * 1024 then
		return string.format("%.1f KB", bytes / 1024)
	end
	return string.format("%.2f MB", bytes / (1024 * 1024))
end

--[[
	Adds thousands separators: 1234567 -> "1,234,567".
]]
function Util.formatInt(value: number): string
	local s = tostring(math.floor(value))
	local out = s:reverse():gsub("(%d%d%d)", "%1,")
	-- gsub returns (string, count); reverse the padded result back
	local padded = out:reverse()
	return (padded:gsub("^,", ""))
end

--[[
	Normalises an asset id to the canonical `rbxassetid://<number>` form so the
	plugin can accept either "12345", "rbxassetid://12345" or "http://www.roblox.com/asset/?id=12345".
]]
function Util.normalizeAssetId(value: any): number?
	if typeof(value) == "number" then
		return math.floor(value)
	end
	if type(value) ~= "string" then
		return nil
	end
	local digits = value:match("(%d+)%s*$")
	if not digits then
		return nil
	end
	local id = tonumber(digits)
	return id and math.floor(id) or nil
end

function Util.assetIdToContent(id: number): string
	return "rbxassetid://" .. tostring(math.floor(id))
end

--------------------------------------------------------------------------------
-- 6. Table helpers
--------------------------------------------------------------------------------

--[[
	Stable, case-insensitive sort key so the UI list order never jumps around
	between scans (Roblox's `GetChildren` order is not guaranteed).
]]
function Util.sortKey(name: string): string
	return name:lower()
end

--[[
	Shallow-copies an array.
]]
function Util.copyArray(source: { any }): { any }
	local out = table.create(#source)
	for i, v in ipairs(source) do
		out[i] = v
	end
	return out
end

--[[
	Returns true when `list` contains `value` (linear scan; lists are small).
]]
function Util.contains(list: { any }, value: any): boolean
	for _, v in ipairs(list) do
		if v == value then
			return true
		end
	end
	return false
end

--[[
	Escapes Lua pattern magic characters so a user-typed filter string can be
	used safely with string.find(..., _, true) alternatives.
]]
function Util.escapePattern(text: string): string
	return (text:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

return Util
