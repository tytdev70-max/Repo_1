--!nonstrict
-- GunAttachments/Registry
-- Content lookup and config loading.
--
-- Content layout (configurable root + config module name):
--     <contentRoot>/<Slot>/<AttachmentName>/<configModuleName>   (ModuleScript)
--     <contentRoot>/<Slot>/<AttachmentName>/<parts...>           (BaseParts to clone)

local Util = require(script.Parent.Util)
local Types = require(script.Parent.Types)

type AttachmentConfig = Types.AttachmentConfig

export type Registry = {
	GetContentRoot: (self: Registry) -> Instance?,
	GetContentFolder: (self: Registry, slot: string, name: string) -> Instance?,
	LoadConfig: (self: Registry, slot: string, name: string) -> AttachmentConfig?,
	IsCompatible: (self: Registry, config: AttachmentConfig, tool: Instance?, slot: string, name: string) -> boolean,
	ClearCache: (self: Registry) -> (),
}

local Registry = {}
Registry.__index = Registry

function Registry.new(options: { [string]: any }, log: Util.Logger): Registry
	local self = setmetatable({
		_contentRoot = options.contentRoot,
		_configModuleName = options.configModuleName,
		_isCompatibleHook = options.hooks and options.hooks.isCompatible,
		_requireFn = options.services and options.services.require or require,
		_cache = {} :: { [string]: AttachmentConfig },
		_warned = {} :: { [string]: boolean },
		_log = log,
	}, Registry)
	return (self :: any) :: Registry
end

function Registry:GetContentRoot(): Instance?
	local root = (self :: any)._contentRoot
	if type(root) == "function" then
		local ok, result = pcall(root)
		return if ok then result else nil
	end
	return root
end

function Registry:GetContentFolder(slot: string, name: string): Instance?
	local root = (self :: any):GetContentRoot()
	if not root then
		return nil
	end
	local slotFolder = root:FindFirstChild(slot)
	if not slotFolder then
		return nil
	end
	return slotFolder:FindFirstChild(name)
end

-- Same semantics as the original LoadAttachmentConfig: returns nil on any failure,
-- caches only successful loads (so content added later at runtime can still load).
function Registry:LoadConfig(slot: string, name: string): AttachmentConfig?
	local registry = self :: any
	if type(slot) ~= "string" or type(name) ~= "string" then
		return nil
	end
	local cacheKey = slot .. "/" .. name
	local cached = registry._cache[cacheKey]
	if cached then
		return cached
	end

	local folder = registry:GetContentFolder(slot, name)
	if not folder then
		return nil
	end
	local module = folder:FindFirstChild(registry._configModuleName)
	if not module then
		return nil
	end

	local ok, config = pcall(registry._requireFn, module)
	if not ok then
		registry._log.warn(("Config '%s' failed to load: %s"):format(cacheKey, tostring(config)))
		return nil
	end
	if type(config) ~= "table" then
		registry._log.warn(("Config '%s' did not return a table"):format(cacheKey))
		return nil
	end

	registry._cache[cacheKey] = config
	return config
end

-- Compatibility check. The optional hook can veto or force a result; returning nil
-- from the hook defers to the config's own IsCompatible. A config without
-- IsCompatible is treated as universally compatible (old code errored here).
function Registry:IsCompatible(config: AttachmentConfig, tool: Instance?, slot: string, name: string): boolean
	local registry = self :: any
	local hook = registry._isCompatibleHook
	if hook then
		local ok, verdict = pcall(hook, config, tool, slot, name)
		if ok and verdict ~= nil then
			return verdict == true
		end
	end

	local check = config.IsCompatible
	if type(check) ~= "function" then
		local key = slot .. "/" .. name
		if not registry._warned[key] then
			registry._warned[key] = true
			registry._log.warn(("Config '%s' has no IsCompatible(); treating as compatible"):format(key))
		end
		return true
	end

	local weaponName = tool and (tool :: any).Name or ""
	local ok, result = pcall(check, weaponName)
	if not ok then
		registry._log.warn(("IsCompatible for '%s/%s' errored: %s"):format(slot, name, tostring(result)))
		return false
	end
	-- Truthiness (not `== true`) matches the original `if not IsCompatible(...)` check.
	return result ~= nil and result ~= false
end

function Registry:ClearCache()
	table.clear((self :: any)._cache)
end

return Registry
