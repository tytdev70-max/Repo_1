--[[
	AttachmentSystem.ConfigLoader
	─────────────────────────────
	Discovers attachment definitions under the configured root folder, loads
	their `Customization` module, caches it, and answers the questions the rest
	of the system (and the host) needs to ask:

		• is this category/name a well-formed request?
		• does a definition exist for it?
		• is it compatible with this weapon?
		• which attachments can this weapon physically take?

	The asset root is resolved *lazily*. Nothing here yields or waits, so this
	module can be required at any point in the host's startup order without
	risking a deadlock.
]]

local Config = require(script.Parent.Config)

local Loader = {}

local cache: { [string]: any } = {}
local rootLookupAttempted = false
local warnedMissingRoot = false

local function warnOnce(message: string, ...)
	if warnedMissingRoot then return end
	warnedMissingRoot = true
	warn("[AttachmentSystem] " .. string.format(message, ...))
end

-- ─── Root resolution ────────────────────────────────────────────────────────

--[[
	Resolve the folder that holds one child folder per attachment category.
	Order of preference:
	  1. an explicit root set by the host through Configure()
	  2. `ReplicatedStorage.<assetRootName>.<attachmentFolderName>`
	  3. `ReplicatedStorage.<attachmentFolderName>`

	Returns nil (never yields) when nothing is available, in which case every
	other function in the system degrades to a safe no-op.
]]
function Loader.GetRoot(): Folder?
	local configured = Config.GetRoot()
	if configured then
		return configured
	end

	if rootLookupAttempted then
		return nil
	end
	rootLookupAttempted = true

	local replicated = game:GetService("ReplicatedStorage")
	local assetsName  = Config.Assets.assetRootName
	local folderName  = Config.Assets.attachmentFolderName

	local direct = replicated:FindFirstChild(folderName)
	if direct and direct:IsA("Folder") then
		Config.SetRoot(direct)
		return direct
	end

	if type(assetsName) == "string" and assetsName ~= "" then
		local assetRoot = replicated:FindFirstChild(assetsName)
		if assetRoot then
			local folder = assetRoot:FindFirstChild(folderName)
			if folder and folder:IsA("Folder") then
				Config.SetRoot(folder)
				return folder
			end
		end
	end

	return nil
end

-- Called by Configure() so a new host can swap the root without restarting.
function Loader.Reset()
	cache = {}
	rootLookupAttempted = false
	warnedMissingRoot = false
end

-- ─── Basic lookup ───────────────────────────────────────────────────────────

function Loader.GetCategoryFolder(category: string): Folder?
	if type(category) ~= "string" or category == "" then
		return nil
	end

	local root = Loader.GetRoot()
	if not root then
		warnOnce("no attachment root folder found; the attachment system is inert. " ..
			"Call AttachmentSystem.Configure({ root = <Folder> }) to supply one.")
		return nil
	end

	local folder = root:FindFirstChild(category)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

function Loader.GetAttachmentFolder(attachmentName: string, category: string): Folder?
	if type(attachmentName) ~= "string" or attachmentName == "" then
		return nil
	end
	local categoryFolder = Loader.GetCategoryFolder(category)
	if not categoryFolder then
		return nil
	end
	local folder = categoryFolder:FindFirstChild(attachmentName)
	if folder and folder:IsA("Folder") then
		return folder
	end
	return nil
end

--[[
	Load (and cache) the Customization module for an attachment.

	Returns the module table, or nil when the attachment does not exist or its
	Customization module errors. The result is never a partial table.
]]
function Loader.Load(attachmentName: string, category: string): any?
	if type(attachmentName) ~= "string" or attachmentName == "" then
		return nil
	end
	if type(category) ~= "string" or category == "" then
		return nil
	end

	local key = category .. "/" .. attachmentName
	local cached = cache[key]
	if cached ~= nil then
		return cached or nil
	end

	local folder = Loader.GetAttachmentFolder(attachmentName, category)
	if not folder then
		cache[key] = false
		return nil
	end

	local module = folder:FindFirstChild(Config.Assets.customizationName)
	if not module or not module:IsA("ModuleScript") then
		cache[key] = false
		return nil
	end

	local ok, config = pcall(require, module)
	if not ok or type(config) ~= "table" then
		cache[key] = false
		return nil
	end

	cache[key] = config
	return config
end

-- ─── Validation ─────────────────────────────────────────────────────────────

--[[
	Structural validation, independent of whether the attachment exists.
	Matches the limits the server already enforces so a malformed request is
	rejected on the client too.
]]
function Loader.IsValidRequest(attachmentName: any, category: any): boolean
	if type(category) ~= "string" or category == "" then
		return false
	end
	if type(attachmentName) ~= "string" or attachmentName == "" then
		return false
	end
	if #attachmentName > Config.Limits.maxNameLength then
		return false
	end
	if #category > Config.Limits.maxNameLength then
		return false
	end

	if Config.IsStrict() and Config.Categories[category] == nil then
		return false
	end
	return true
end

--[[
	Compatibility check. A definition may omit `IsCompatible` entirely, in
	which case it is treated as universal. Errors thrown by the check are
	treated as "incompatible" rather than being allowed to escape into callers.
]]
function Loader.IsCompatible(attachmentName: string, category: string, weaponName: string?): boolean
	local config = Loader.Load(attachmentName, category)
	if not config then
		return false
	end

	if type(config.IsCompatible) ~= "function" then
		return true
	end

	local ok, result = pcall(config.IsCompatible, weaponName)
	return ok and result == true
end

-- ─── Enumeration ────────────────────────────────────────────────────────────

--[[
	Every attachment defined for a category, as a sorted list of names.
	Used by the Gunsmith and by any host that wants to build its own picker.
]]
function Loader.List(category: string): {string}
	local names = {}
	local folder = Loader.GetCategoryFolder(category)
	if folder then
		for _, child in ipairs(folder:GetChildren()) do
			if child:IsA("Folder") then
				table.insert(names, child.Name)
			end
		end
	end
	table.sort(names)
	return names
end

--[[
	Which of `category`'s attachments a given weapon model can physically take.

	Two independent conditions must both hold:
	  1. the model has an `Attachment` named after the attachment under the
	     category's mount part, and
	  2. the definition's `IsCompatible` accepts the weapon's name.
]]
function Loader.ListCompatible(weaponModel: Instance?, category: string, weaponName: string?): {string}
	local result = {}
	if not weaponModel or not weaponModel:IsA("Model") then
		return result
	end

	local mountName = Config.GetCategoryPartName(category)
	local mountPart = weaponModel:FindFirstChild(mountName, true)

	for _, name in ipairs(Loader.List(category)) do
		if mountPart then
			local mountPoint = mountPart:FindFirstChild(name)
			if mountPoint and mountPoint:IsA("Attachment") then
				if Loader.IsCompatible(name, category, weaponName) then
					table.insert(result, name)
				end
			end
		end
	end

	return result
end

--[[
	Resolve the name of the part that acts as the rig root for an attachment.
	Prefers the definition's explicit `RootPart`; otherwise the first BasePart
	or MeshPart inside the source folder.
]]
function Loader.ResolveRootPartName(attachmentFolder: Folder, config: any): string?
	local declared = config and config.RootPart
	if type(declared) == "string" and declared ~= "" then
		return declared
	end
	if not attachmentFolder then
		return nil
	end

	local first = attachmentFolder:FindFirstChildOfClass("BasePart")
		or attachmentFolder:FindFirstChildOfClass("MeshPart")
	return first and first.Name or nil
end

-- ─── Cache control ──────────────────────────────────────────────────────────

function Loader.ClearCache()
	cache = {}
end

function Loader.GetCacheSize(): number
	local count = 0
	for _, value in pairs(cache) do
		if value ~= false then
			count += 1
		end
	end
	return count
end

return Loader
