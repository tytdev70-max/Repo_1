--[[
	UploadService.luau
	------------------
	Module 2 of 6 - the AssetService upload module.

	Upload path (the ONLY one this plugin uses)
	-------------------------------------------
		game:GetService("AssetService")
		AssetService:CreateAssetAsync(keyframeSequence, Enum.AssetType.Animation, params)

	`CreateAssetAsync` is a yielding method that returns a tuple:

		(Enum.CreateAssetResult, number | string)

	* On success the first value is `Enum.CreateAssetResult.Success` and the second
	  is the new asset id (a number).
	* On failure the first value is one of PermissionDenied / UploadFailed /
	  Unknown and the second is a human-readable diagnostic string.
	* If the call itself cannot be made (for example the "CreateAssetAsync Luau
	  API" beta feature is not enabled in Studio) it raises a Lua error, which we
	  catch with pcall.

	ClipEditor is never touched. No rig selection dialog, no Animation Editor UI,
	no "three dots -> publish". The only thing the user ever sees is Roblox's own
	permission popup for the asset-creation capability.

	Documented constraints that are honoured here
		* The API is rate limited to roughly 30 requests per minute, so uploads are
		  throttled (default 20/min) and run in a coroutine so Studio stays live.
		* The API only works from a LOCAL plugin, not from Creator Store plugins.
		  `:IsAvailable()` surfaces this up front.
		* `Enum.AssetCreatorType` / `CreatorId` must be supplied for group uploads.
		* Deprecated/removed members such as AssetService:PromptCreateAssetAsync,
		  PromptPublishAssetAsync and CreatePlaceAsync are never called.

	See Plugin/API_RESEARCH.md for the source links.
]]

local AssetService = game:GetService("AssetService")

--[[
	"Clean" state string. Duplicated here (rather than required from
	BinaryCacheService) so the two modules stay independent and there is no
	circular dependency. Both modules must agree on this value.
]]
local STATE_CLEAN = "Clean"

local UploadService = {}
UploadService.__index = UploadService

--[[
	Defaults. Overridable per instance (the UI writes into these).
]]
UploadService.Defaults = {
	-- The API is documented as limited to 30 requests/minute. Stay under it.
	RequestsPerMinute = 20,

	-- Transient failures (UploadFailed / Unknown / raised errors) are retried.
	MaxRetries = 2,
	RetryDelaySeconds = 5,

	-- "Direct"  : pass the rig's own KeyframeSequence (what community bulk
	--             uploaders do, and the cheapest option).
	-- "Clone"   : upload an unparented clone, which guarantees the object passed
	--             to the API is a standalone root. Slightly slower/safer.
	UploadMode = "Direct",

	-- Asset metadata.
	DescriptionTemplate = "Uploaded with the AnimSaves Bulk Uploader Studio plugin.",
	CreatorType = Enum.AssetCreatorType.User,
	GroupId = nil :: number?,

	-- Optional name decoration. The uploaded asset name defaults to the
	-- KeyframeSequence's own name.
	NamePrefix = "",
	NameSuffix = "",

	-- Yield between uploads so the Studio UI keeps painting.
	InterItemDelay = 0.05,
}

export type UploadOutcome = {
	success: boolean,
	assetId: number,
	resultEnum: string,
	message: string,
	attempts: number,
	elapsed: number,
	sequence: KeyframeSequence?,
	name: string?,
}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UploadService.new(options: { [string]: any }?): UploadService
	local self = setmetatable({}, UploadService)

	self._options = {}
	for key, value in pairs(UploadService.Defaults) do
		self._options[key] = value
	end
	if options then
		for key, value in pairs(options) do
			self._options[key] = value
		end
	end

	self._requestTimes = {} -- { number }
	self._cancelled = false
	self._busy = false
	self._lastError = nil -- string?
	self._log = {}

	return self
end

function UploadService:SetOptions(options: { [string]: any })
	for key, value in pairs(options or {}) do
		self._options[key] = value
	end
	return self
end

function UploadService:GetOptions(): { [string]: any }
	return self._options
end

function UploadService:IsBusy(): boolean
	return self._busy
end

function UploadService:GetLastError(): string?
	return self._lastError
end

function UploadService:Cancel()
	self._cancelled = true
	return self
end

function UploadService:IsCancelled(): boolean
	return self._cancelled
end

function UploadService:Log(level: string, message: string)
	table.insert(self._log, { level = level, message = message, time = os.clock() })
	if #self._log > 500 then
		table.remove(self._log, 1)
	end
	if level == "error" then
		warn("[AnimSavesUploader] " .. message)
	elseif level == "warn" then
		warn("[AnimSavesUploader] " .. message)
	else
		print("[AnimSavesUploader] " .. message)
	end
end

function UploadService:GetLog(): { { level: string, message: string } }
	return self._log
end

--------------------------------------------------------------------------------
-- Availability check
--------------------------------------------------------------------------------

--[[
	Verifies the upload path is usable before we burn the user's time.

	Returns (available: boolean, reason: string?)

	Two things are checked:
	  1. AssetService exists and exposes CreateAssetAsync (always true on a
	     current client, but cheap to confirm).
	  2. Enum.AssetType.Animation and Enum.CreateAssetResult are present, because
	     those are what we branch on.
]]
function UploadService:IsAvailable(): (boolean, string?)
	if typeof(AssetService) ~= "Instance" or not AssetService:IsA("AssetService") then
		return false, "AssetService could not be acquired."
	end

	if type(AssetService.CreateAssetAsync) ~= "function" then
		return false, "AssetService:CreateAssetAsync is missing. Update Roblox Studio."
	end

	if not Enum.AssetType or not Enum.AssetType.Animation then
		return false, "Enum.AssetType.Animation is missing."
	end

	if not Enum.CreateAssetResult or not Enum.CreateAssetResult.Success then
		return false, "Enum.CreateAssetResult is missing."
	end

	return true, nil
end

--[[
	Translates a CreateAssetResult enum item into a stable string key so the UI
	and the log never depend on enum naming.
]]
local function resultKey(resultEnum: any): string
	if typeof(resultEnum) == "EnumItem" then
		return resultEnum.Name
	end
	return tostring(resultEnum)
end

--[[
	Detects the specific error raised when the "CreateAssetAsync Luau API" beta
	feature is not enabled in Studio, so we can give an actionable message.
]]
local function isBetaFeatureError(message: string): boolean
	if type(message) ~= "string" then
		return false
	end
	local lower = message:lower()
	return lower:find("not available yet", 1, true) ~= nil
		or lower:find("unable to create asset", 1, true) ~= nil
		or lower:find("createassetasync", 1, true) ~= nil and lower:find("beta", 1, true) ~= nil
end

--------------------------------------------------------------------------------
-- Request parameters
--------------------------------------------------------------------------------

--[[
	Builds the `requestParameters` dictionary for CreateAssetAsync.

	Only documented keys are used: Name, Description, CreatorId, CreatorType.
	`IsPackage` is intentionally omitted - it only applies to Enum.AssetType.Model.
]]
function UploadService:BuildParams(sequence: KeyframeSequence, overrides: { [string]: any }?): { [string]: any }
	local options = self._options
	local name = sequence.Name

	if overrides and overrides.name then
		name = overrides.name
	else
		name = options.NamePrefix .. sequence.Name .. options.NameSuffix
	end

	local description = options.DescriptionTemplate
	if overrides and overrides.description then
		description = overrides.description
	end

	local params: { [string]: any } = {
		Name = name,
		Description = description,
	}

	local creatorType = options.CreatorType
	if overrides and overrides.creatorType then
		creatorType = overrides.creatorType
	end
	params.CreatorType = creatorType

	local groupId = options.GroupId
	if overrides and overrides.groupId ~= nil then
		groupId = overrides.groupId
	end

	if creatorType == Enum.AssetCreatorType.Group then
		if type(groupId) ~= "number" then
			error("CreatorType is Group but no valid GroupId was provided.", 2)
		end
		params.CreatorId = math.floor(groupId)
	end

	return params
end

--------------------------------------------------------------------------------
-- Rate limiting
--------------------------------------------------------------------------------

--[[
	Blocks until a request slot is free, respecting `RequestsPerMinute`.

	Waits are chunked (max 1s at a time) so :Cancel() stays responsive.
]]
function UploadService:WaitForSlot()
	local rpm = math.clamp(math.floor(self._options.RequestsPerMinute), 1, 30)
	local now = time()

	-- Drop timestamps outside the rolling 60s window.
	local kept: { number } = {}
	for _, stamp in ipairs(self._requestTimes) do
		if now - stamp < 60 then
			table.insert(kept, stamp)
		end
	end
	self._requestTimes = kept

	while #self._requestTimes >= rpm do
		if self._cancelled then
			return
		end
		local oldest = self._requestTimes[1]
		local waitFor = 60 - (now - oldest)
		if waitFor <= 0 then
			table.remove(self._requestTimes, 1)
		else
			task.wait(math.min(waitFor, 1))
			now = time()
			kept = {}
			for _, stamp in ipairs(self._requestTimes) do
				if now - stamp < 60 then
					table.insert(kept, stamp)
				end
			end
			self._requestTimes = kept
		end
	end

	table.insert(self._requestTimes, time())
end

--------------------------------------------------------------------------------
-- Single upload
--------------------------------------------------------------------------------

--[[
	Uploads one KeyframeSequence with AssetService:CreateAssetAsync.

	Returns an UploadOutcome. Never throws.
]]
function UploadService:UploadOne(sequence: KeyframeSequence, overrides: { [string]: any }?): UploadOutcome
	local outcome: UploadOutcome = {
		success = false,
		assetId = 0,
		resultEnum = "Unknown",
		message = "",
		attempts = 0,
		elapsed = 0,
		sequence = sequence,
		name = if sequence then sequence.Name else nil,
	}

	if not sequence or not sequence:IsA("KeyframeSequence") then
		outcome.resultEnum = "InvalidInput"
		outcome.message = "Target is not a KeyframeSequence."
		return outcome
	end

	if self._cancelled then
		outcome.resultEnum = "Cancelled"
		outcome.message = "Upload cancelled before this item started."
		return outcome
	end

	local started = time()
	local maxRetries = math.max(0, math.floor(self._options.MaxRetries))

	for attempt = 1, maxRetries + 1 do
		outcome.attempts = attempt
		if self._cancelled then
			outcome.resultEnum = "Cancelled"
			outcome.message = "Upload cancelled."
			break
		end

		self:WaitForSlot()

		if self._cancelled then
			outcome.resultEnum = "Cancelled"
			outcome.message = "Upload cancelled."
			break
		end

		-- Build the object we hand to the API.
		local target: Instance = sequence
		local clone: Instance? = nil
		if self._options.UploadMode == "Clone" then
			local cloneOk, cloned = pcall(function()
				return sequence:Clone()
			end)
			if not cloneOk or not cloned then
				outcome.resultEnum = "CloneFailed"
				outcome.message = "Could not clone the KeyframeSequence: " .. tostring(cloned)
				break
			end
			clone = cloned
			clone.Parent = nil -- standalone root, not part of the rig
			target = clone
		end

		local params: { [string]: any }? = nil
		local paramsOk, paramsErr = pcall(function()
			params = self:BuildParams(sequence, overrides)
		end)
		if not paramsOk then
			outcome.resultEnum = "InvalidParameters"
			outcome.message = tostring(paramsErr)
			if clone then
				clone:Destroy()
			end
			break
		end

		-- The actual upload. pcall because a disabled beta feature or a network
		-- failure raises a Lua error instead of returning a result enum.
		local ok, first, second = pcall(function()
			return AssetService:CreateAssetAsync(target, Enum.AssetType.Animation, params)
		end)

		if clone then
			clone:Destroy()
		end

		if not ok then
			outcome.resultEnum = "LuaError"
			outcome.message = tostring(first)

			if isBetaFeatureError(outcome.message) then
				outcome.resultEnum = "BetaDisabled"
				outcome.message = "CreateAssetAsync is not available. Enable the "
					.. "'CreateAssetAsync Luau API' beta feature in Studio "
					.. "(File -> Beta Features) and make sure this plugin is installed "
					.. "as a LOCAL plugin, not from the Creator Store."
				break -- retrying will never help
			end

			if attempt <= maxRetries then
				self:Log("warn", string.format("Upload of '%s' raised an error (attempt %d): %s", sequence.Name, attempt, outcome.message))
				task.wait(self._options.RetryDelaySeconds)
				continue
			end
			break
		end

		outcome.resultEnum = resultKey(first)

		if typeof(first) == "EnumItem" and first == Enum.CreateAssetResult.Success then
			if type(second) == "number" then
				outcome.success = true
				outcome.assetId = math.floor(second)
				outcome.message = string.format("Uploaded '%s' as asset %d.", sequence.Name, outcome.assetId)
			else
				outcome.resultEnum = "MalformedResult"
				outcome.message = string.format(
					"CreateAssetAsync reported Success but returned %s instead of an asset id.",
					typeof(second)
				)
			end
			break
		end

		-- Failure path: second is a diagnostic string.
		outcome.message = if type(second) == "string" then second else "Upload failed with no diagnostic."

		if outcome.resultEnum == "PermissionDenied" then
			-- Retrying will not help; the user must fix permissions.
			break
		end

		if attempt <= maxRetries then
			self:Log(
				"warn",
				string.format("Upload of '%s' failed with %s (attempt %d): %s", sequence.Name, outcome.resultEnum, attempt, outcome.message)
			)
			task.wait(self._options.RetryDelaySeconds)
		end
	end

	outcome.elapsed = time() - started
	return outcome
end

--------------------------------------------------------------------------------
-- Batch upload
--------------------------------------------------------------------------------

export type BatchCallbacks = {
	onStart: ((total: number) -> ())?,
	onItemStart: ((index: number, total: number, record: any) -> ())?,
	onItemEnd: ((index: number, total: number, record: any, outcome: UploadOutcome) -> ())?,
	onProgress: ((index: number, total: number, record: any, outcome: UploadOutcome) -> ())?,
	onSkip: ((index: number, total: number, record: any, reason: string) -> ())?,
	onComplete: ((summary: BatchSummary) -> ())?,
	onLog: ((level: string, message: string) -> ())?,
}

export type BatchSummary = {
	total: number,
	succeeded: number,
	failed: number,
	skipped: number,
	cancelled: boolean,
	elapsed: number,
	results: { { record: any, outcome: UploadOutcome } },
}

--[[
	Uploads a list of AnalysisRecords produced by BinaryCacheService:Analyze().

	Behaviour
		* Records whose `.selected` is false are skipped.
		* Records that are Clean can be skipped entirely when `skipClean` is set;
		  this is the performance win the binary cache exists for.
		* Everything else is uploaded through AssetService:CreateAssetAsync.
		* Progress is reported after every item; the batch runs in whatever
		  coroutine calls it, so callers should `task.spawn` it.

	Returns a BatchSummary. Never throws.
]]
function UploadService:UploadBatch(records: { any }, callbacks: BatchCallbacks?, skipClean: boolean?): BatchSummary
	local summary: BatchSummary = {
		total = 0,
		succeeded = 0,
		failed = 0,
		skipped = 0,
		cancelled = false,
		elapsed = 0,
		results = {},
	}

	self._busy = true
	self._cancelled = false
	self._requestTimes = {}
	self._lastError = nil

	local started = time()

	local available, reason = self:IsAvailable()
	if not available then
		self._lastError = reason
		self:Log("error", reason or "Upload path unavailable.")
		if callbacks and callbacks.onComplete then
			callbacks.onComplete(summary)
		end
		self._busy = false
		return summary
	end

	-- Build the work list.
	local work: { any } = {}
	for _, record in ipairs(records or {}) do
		if record.selected then
			if skipClean and record.state == STATE_CLEAN then
				summary.skipped += 1
				if callbacks and callbacks.onSkip then
					callbacks.onSkip(#work + 1, #records, record, "unchanged since last upload")
				end
			else
				table.insert(work, record)
			end
		end
	end

	summary.total = #work
	if callbacks and callbacks.onStart then
		callbacks.onStart(summary.total)
	end

	if summary.total == 0 then
		summary.cancelled = self._cancelled
		summary.elapsed = time() - started
		if callbacks and callbacks.onComplete then
			callbacks.onComplete(summary)
		end
		self._busy = false
		return summary
	end

	for index, record in ipairs(work) do
		if self._cancelled then
			summary.cancelled = true
			break
		end

		if callbacks and callbacks.onItemStart then
			callbacks.onItemStart(index, summary.total, record)
		end

		local outcome = self:UploadOne(record.sequence, record.uploadOverrides)

		table.insert(summary.results, { record = record, outcome = outcome })

		if outcome.success then
			summary.succeeded += 1
			self:Log("info", outcome.message)
		else
			summary.failed += 1
			self._lastError = outcome.message
			self:Log("error", string.format("[%d/%d] %s", index, summary.total, outcome.message))
		end

		if callbacks and callbacks.onItemEnd then
			callbacks.onItemEnd(index, summary.total, record, outcome)
		end
		if callbacks and callbacks.onProgress then
			callbacks.onProgress(index, summary.total, record, outcome)
		end

		-- Let Studio paint.
		if index < summary.total then
			task.wait(self._options.InterItemDelay)
		end
	end

	summary.cancelled = self._cancelled
	summary.elapsed = time() - started

	if callbacks and callbacks.onComplete then
		callbacks.onComplete(summary)
	end

	self._busy = false
	return summary
end

--[[
	Runs :UploadBatch on a fresh coroutine so the calling (UI) thread is never
	blocked. Returns the thread.
]]
function UploadService:UploadBatchAsync(records: { any }, callbacks: BatchCallbacks?, skipClean: boolean?): thread
	return task.spawn(function()
		self:UploadBatch(records, callbacks, skipClean)
	end)
end

--------------------------------------------------------------------------------
-- Dry run (no network calls at all)
--------------------------------------------------------------------------------

--[[
	Simulates a batch so the whole pipeline (UI, progress, cache, registration)
	can be validated without spending the user's rate limit. Never calls
	CreateAssetAsync.
]]
function UploadService:DryRun(records: { any }, callbacks: BatchCallbacks?, skipClean: boolean?): BatchSummary
	local summary: BatchSummary = {
		total = 0,
		succeeded = 0,
		failed = 0,
		skipped = 0,
		cancelled = false,
		elapsed = 0,
		results = {},
	}

	local started = time()
	local work: { any } = {}
	for _, record in ipairs(records or {}) do
		if record.selected then
			if skipClean and record.state == STATE_CLEAN then
				summary.skipped += 1
				if callbacks and callbacks.onSkip then
					callbacks.onSkip(#work + 1, #records, record, "unchanged since last upload (dry run)")
				end
			else
				table.insert(work, record)
			end
		end
	end

	summary.total = #work
	if callbacks and callbacks.onStart then
		callbacks.onStart(summary.total)
	end

	for index, record in ipairs(work) do
		local outcome: UploadOutcome = {
			success = true,
			assetId = 900000000 + index,
			resultEnum = "Success (dry run)",
			message = string.format("Dry run: would upload '%s'.", record.name),
			attempts = 1,
			elapsed = 0,
			sequence = record.sequence,
			name = record.name,
		}
		summary.succeeded += 1
		table.insert(summary.results, { record = record, outcome = outcome })

		if callbacks and callbacks.onItemEnd then
			callbacks.onItemEnd(index, summary.total, record, outcome)
		end
		if callbacks and callbacks.onProgress then
			callbacks.onProgress(index, summary.total, record, outcome)
		end
		task.wait(0.02)
	end

	summary.elapsed = time() - started
	if callbacks and callbacks.onComplete then
		callbacks.onComplete(summary)
	end
	return summary
end

return UploadService
