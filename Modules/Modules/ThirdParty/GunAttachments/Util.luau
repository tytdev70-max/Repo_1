--!nonstrict
-- GunAttachments/Util
-- Small, dependency-free helpers shared by the package.

local Util = {}

-- Deep copy of plain data tables. Functions, Instances, CFrames etc. are copied by
-- reference (same semantics as the original SPH implementation). Handles cycles.
function Util.deepCopy<T>(original: T, seen: { [any]: any }?): T
	if type(original) ~= "table" then
		return original
	end
	local map = seen or {}
	if map[original] then
		return map[original]
	end
	local copy = {}
	map[original] = copy
	for key, value in pairs(original :: any) do
		copy[Util.deepCopy(key, map)] = Util.deepCopy(value, map)
	end
	return (setmetatable(copy, getmetatable(original :: any)) :: any) :: T
end

-- Calls fn with args inside pcall. Returns (ok, result-or-error).
function Util.safeCall(fn: any, ...: any): (boolean, any)
	if type(fn) ~= "function" then
		return false, "not a function"
	end
	return pcall(fn, ...)
end

-- Instance-kind helpers. They tolerate test doubles by only relying on :IsA.
function Util.isA(value: any, className: string): boolean
	if value == nil then
		return false
	end
	local ok, result = pcall(function()
		return value:IsA(className)
	end)
	return ok and result == true
end

function Util.isAlive(instance: any): boolean
	if instance == nil then
		return false
	end
	local ok, parent = pcall(function()
		return instance.Parent
	end)
	return ok and parent ~= nil
end

-- Builds a logger from user options. `log = false` silences everything.
export type Logger = {
	warn: (...any) -> (),
	debug: (...any) -> (),
}

function Util.makeLogger(option: any, prefix: string): Logger
	local function noop(...: any) end
	if option == false then
		return { warn = noop, debug = noop }
	end
	local userWarn = type(option) == "table" and option.warn or nil
	local userDebug = type(option) == "table" and option.debug or nil
	return {
		warn = function(...: any)
			if userWarn then
				userWarn(prefix, ...)
			else
				warn(prefix, ...)
			end
		end,
		debug = function(...: any)
			if userDebug then
				userDebug(prefix, ...)
			end
		end,
	}
end

-- Shallow array copy.
function Util.copyArray<T>(array: { T }?): { T }
	local result = {}
	if array then
		for index, value in ipairs(array) do
			result[index] = value
		end
	end
	return result
end

return Util
