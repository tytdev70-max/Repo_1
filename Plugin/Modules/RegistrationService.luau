--[[
	RegistrationService.luau
	------------------------
	Module 3 of 6 - the registration module.

	For every successfully uploaded animation this module writes the result back
	into the rig so the ids are never lost:

		<rig>
		 └─ UploadedAnimations            (Folder, created if missing)
		      ├─ <AnimationName>           (StringValue, .Value = asset id)
		      ├─ <AnimationName>           (StringValue, .Value = asset id)
		      └─ ...

	Rules
		* The folder is named exactly "UploadedAnimations" and lives directly
		  inside the rig.
		* Each StringValue is named after the animation and its .Value holds the
		  asset id.
		* Re-uploading an animation updates the existing StringValue instead of
		  creating a duplicate, so the folder never accumulates stale entries.
		* Nothing is ever destroyed unless the caller explicitly asks for it.

	The plugin's own binary cache StringValue lives in a *separate* folder
	("_AnimUploaderCache") so registration and caching never fight over children.
]]

local RegistrationService = {}
RegistrationService.__index = RegistrationService

RegistrationService.Defaults = {
	-- Name of the folder created inside the rig.
	FolderName = "UploadedAnimations",

	-- "Numeric" -> StringValue.Value = "13164837337"
	-- "Content"  -> StringValue.Value = "rbxassetid://13164837337"
	ValueFormat = "Numeric",

	-- When a child with the animation's name already exists but is NOT a
	-- StringValue (e.g. an old Animation object), replace it. Off by default so
	-- the plugin never silently destroys user data.
	ReplaceMismatchedClasses = false,

	-- Optionally tag the rig and stamp the folder with attributes.
	TagRig = true,
	StampFolderAttributes = true,

	-- Optional: also drop an Animation instance next to each StringValue.
	-- Off by default; StringValues are what the spec asks for.
	AlsoCreateAnimationObjects = false,
}

export type RegistrationResult = {
	name: string,
	assetId: number,
	value: string,
	action: string, -- "created" | "updated" | "skipped" | "failed"
	instance: StringValue?,
	error: string?,
}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function RegistrationService.new(options: { [string]: any }?): RegistrationService
	local self = setmetatable({}, RegistrationService)
	self._options = {}
	for key, value in pairs(RegistrationService.Defaults) do
		self._options[key] = value
	end
	if options then
		for key, value in pairs(options or {}) do
			self._options[key] = value
		end
	end
	self._written = {} -- { [string]: StringValue }
	return self
end

function RegistrationService:SetOptions(options: { [string]: any })
	for key, value in pairs(options or {}) do
		self._options[key] = value
	end
	return self
end

--------------------------------------------------------------------------------
-- Folder management
--------------------------------------------------------------------------------

--[[
	Returns the `UploadedAnimations` folder inside `rig`, creating it if needed.

	If an existing child has the right name but the wrong class it is left alone
	and an error is raised - we never destroy something we did not create.
]]
function RegistrationService:EnsureFolder(rig: Instance): Folder
	if not rig then
		error("RegistrationService:EnsureFolder requires a rig.", 2)
	end

	local existing = rig:FindFirstChild(self._options.FolderName)
	if existing then
		if existing:IsA("Folder") then
			if self._options.StampFolderAttributes then
				self:_stampFolder(existing :: Folder)
			end
			return existing :: Folder
		end
		error(
			string.format(
				"'%s' already exists as a %s and cannot be used as the animation folder.",
				self._options.FolderName,
				existing.ClassName
			),
			2
		)
	end

	local folder = Instance.new("Folder")
	folder.Name = self._options.FolderName
	folder.Parent = rig

	if self._options.StampFolderAttributes then
		self:_stampFolder(folder)
	end

	if self._options.TagRig then
		pcall(function()
			rig:AddTag("AnimSavesUploaded")
		end)
	end

	return folder
end

function RegistrationService:_stampFolder(folder: Folder)
	pcall(function()
		folder:SetAttribute("CreatedBy", "AnimSaves Bulk Uploader")
		folder:SetAttribute("LastUpdated", os.time())
	end)
end

--[[
	Returns the folder if it already exists, without creating anything.
]]
function RegistrationService:FindFolder(rig: Instance): Folder?
	if not rig then
		return nil
	end
	local existing = rig:FindFirstChild(self._options.FolderName)
	if existing and existing:IsA("Folder") then
		return existing :: Folder
	end
	return nil
end

--------------------------------------------------------------------------------
-- Value formatting
--------------------------------------------------------------------------------

function RegistrationService:FormatValue(assetId: number): string
	if self._options.ValueFormat == "Content" then
		return "rbxassetid://" .. tostring(math.floor(assetId))
	end
	return tostring(math.floor(assetId))
end

--------------------------------------------------------------------------------
-- Single registration
--------------------------------------------------------------------------------

--[[
	Creates or updates the StringValue for one uploaded animation.

	Returns a RegistrationResult describing what happened. Never throws.
]]
function RegistrationService:Register(rig: Instance, name: string, assetId: number): RegistrationResult
	local result: RegistrationResult = {
		name = name,
		assetId = math.floor(assetId),
		value = self:FormatValue(assetId),
		action = "failed",
		instance = nil,
		error = nil,
	}

	if not rig then
		result.error = "No rig supplied."
		return result
	end
	if type(name) ~= "string" or #name == 0 then
		result.error = "Animation name is empty."
		return result
	end
	if type(assetId) ~= "number" or assetId <= 0 then
		result.error = string.format("Invalid asset id %s for '%s'.", tostring(assetId), name)
		return result
	end

	local ok, err = pcall(function()
		local folder = self:EnsureFolder(rig)

		-- Prefer the instance we already wrote this session (handles duplicate
		-- animation names inside the same rig deterministically).
		local value: StringValue? = self._written[name]
		if value and value.Parent ~= folder then
			value = nil
		end

		if not value then
			local existing = folder:FindFirstChild(name)
			if existing then
				if existing:IsA("StringValue") then
					value = existing :: StringValue
					result.action = "updated"
				elseif self._options.ReplaceMismatchedClasses then
					existing:Destroy()
					warn(string.format("[AnimSavesUploader] Replaced '%s' (%s) with a StringValue.", name, existing.ClassName))
				else
					error(
						string.format(
							"'%s' already exists as a %s inside %s. Enable ReplaceMismatchedClasses to overwrite it.",
							name,
							existing.ClassName,
							folder:GetFullName()
						),
						0
					)
				end
			end
		else
			result.action = "updated"
		end

		if not value then
			value = Instance.new("StringValue")
			value.Name = name
			result.action = "created"
		end

		value.Value = result.value
		value.Parent = folder

		-- Optional convenience: an Animation instance carrying the same id.
		if self._options.AlsoCreateAnimationObjects then
			local anim = folder:FindFirstChild(name .. "_Animation")
			if not anim then
				anim = Instance.new("Animation")
				anim.Name = name .. "_Animation"
				anim.Parent = folder
			end
			(anim :: Animation).AnimationId = result.value
		end

		self._written[name] = value
		result.instance = value
	end)

	if not ok then
		result.action = "failed"
		result.error = tostring(err)
		warn("[AnimSavesUploader] Registration failed for '" .. tostring(name) .. "': " .. tostring(err))
		return result
	end

	return result
end

--------------------------------------------------------------------------------
-- Batch registration
--------------------------------------------------------------------------------

--[[
	Registers every successful upload from an UploadService batch summary.

	Accepts either an UploadService BatchSummary ({ results = { {record, outcome} } })
	or a plain array of { name = ..., assetId = ... } rows.

	Returns { registered, updated, skipped, failed, results }.
]]
function RegistrationService:RegisterBatch(rig: Instance, batch: any): {
	registered: number,
	updated: number,
	skipped: number,
	failed: number,
	results: { RegistrationResult },
}
	local tally = { registered = 0, updated = 0, skipped = 0, failed = 0, results = {} }

	if not rig then
		warn("[AnimSavesUploader] RegisterBatch called without a rig.")
		return tally
	end

	local rows: { { name: string, assetId: number } } = {}

	if type(batch) == "table" and type(batch.results) == "table" then
		for _, item in ipairs(batch.results) do
			local outcome = item.outcome
			if outcome and outcome.success and outcome.assetId and outcome.assetId > 0 then
				table.insert(rows, { name = outcome.name or (item.record and item.record.name) or "Unknown", assetId = outcome.assetId })
			end
		end
	elseif type(batch) == "table" then
		for _, item in ipairs(batch) do
			if type(item) == "table" and item.assetId and item.assetId > 0 then
				table.insert(rows, { name = item.name or "Unknown", assetId = item.assetId })
			end
		end
	end

	for _, row in ipairs(rows) do
		local result = self:Register(rig, row.name, row.assetId)
		table.insert(tally.results, result)
		if result.action == "created" then
			tally.registered += 1
		elseif result.action == "updated" then
			tally.updated += 1
		else
			tally.failed += 1
		end
	end

	return tally
end

--------------------------------------------------------------------------------
-- Reading back / reconciliation
--------------------------------------------------------------------------------

--[[
	Returns a map of animation name -> asset id read from the existing
	`UploadedAnimations` folder. Used to cross-check the binary cache.
]]
function RegistrationService:GetExistingIds(rig: Instance): { [string]: number }
	local ids: { [string]: number } = {}
	local folder = self:FindFolder(rig)
	if not folder then
		return ids
	end
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("StringValue") then
			local digits = child.Value:match("(%d+)%s*$")
			if digits then
				ids[child.Name] = tonumber(digits) or 0
			end
		end
	end
	return ids
end

--[[
	Cross-checks the registration folder against a list of cache records and
	marks each record VERIFIED when the folder agrees with the cache.

	Returns the number of records that could be verified. This is what turns the
	binary cache's FLAG_VERIFIED bit on.
]]
function RegistrationService:Reconcile(rig: Instance, records: { any }): number
	local existing = self:GetExistingIds(rig)
	local verified = 0

	for _, record in ipairs(records or {}) do
		local folderId = existing[record.name]
		if folderId and folderId > 0 and record.cachedAssetId and folderId == record.cachedAssetId then
			record.flags = bit32.bor(record.flags, 4) -- FLAG_VERIFIED
			verified += 1
		elseif folderId and folderId > 0 and record.cachedAssetId and folderId ~= record.cachedAssetId then
			-- The folder is newer than the cache: trust the folder and refresh
			-- the record so the next upload decision uses the right id.
			record.cachedAssetId = folderId
			record.flags = bit32.bor(record.flags, 4)
			verified += 1
		end
	end

	return verified
end

--------------------------------------------------------------------------------
-- Cleanup
--------------------------------------------------------------------------------

--[[
	Empties the `UploadedAnimations` folder (but keeps the folder itself).
	Only ever called from an explicit user action.
]]
function RegistrationService:ClearFolder(rig: Instance): number
	local folder = self:FindFolder(rig)
	if not folder then
		return 0
	end
	local removed = 0
	for _, child in ipairs(folder:GetChildren()) do
		child:Destroy()
		removed += 1
	end
	self._written = {}
	return removed
end

--[[
	Forgets the session's instance cache. Call this when the rig changes so stale
	StringValue references are never reused.
]]
function RegistrationService:ResetSession()
	self._written = {}
	return self
end

return RegistrationService
