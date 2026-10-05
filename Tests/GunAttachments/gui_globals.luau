-- Roblox GUI globals for running Customize/View/Template in the Luau CLI.
-- run.py injects these as locals at the top of the copied Template module.
local Mocks = require("./mocks")

local G = {}

local function udim(scale, offset)
	return { Scale = scale or 0, Offset = offset or 0 }
end
local UDim2MT = {}
UDim2MT.__eq = function(a, b)
	return a.X.Scale == b.X.Scale and a.X.Offset == b.X.Offset and a.Y.Scale == b.Y.Scale and a.Y.Offset == b.Y.Offset
end
UDim2MT.__tostring = function(u)
	return ("{%g,%g},{%g,%g}"):format(u.X.Scale, u.X.Offset, u.Y.Scale, u.Y.Offset)
end
G.UDim2 = {
	new = function(xs, xo, ys, yo)
		return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo) }, UDim2MT)
	end,
}
G.UDim2.fromScale = function(x, y)
	return G.UDim2.new(x, 0, y, 0)
end

local V2MT = { __eq = function(a, b) return a.X == b.X and a.Y == b.Y end }
G.Vector2 = { new = function(x, y) return setmetatable({ X = x or 0, Y = y or 0 }, V2MT) end }

local C3MT = {
	__eq = function(a, b) return a.R == b.R and a.G == b.G and a.B == b.B end,
	__tostring = function(c) return ("rgb(%d,%d,%d)"):format(c.R * 255 + 0.5, c.G * 255 + 0.5, c.B * 255 + 0.5) end,
}
G.Color3 = {
	new = function(r, g, b) return setmetatable({ R = r or 0, G = g or 0, B = b or 0 }, C3MT) end,
}
G.Color3.fromRGB = function(r, g, b)
	return G.Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

G.TweenInfo = { new = function(...) return { ... } end }
local function enumTable(prefix)
	return setmetatable({}, { __index = function(_, key) return prefix .. "." .. key end })
end
G.Enum = setmetatable({}, { __index = function(_, key) return enumTable("Enum." .. key) end })

-- Tweens apply instantly; Completed is fired on demand by tests (G.flushTweens).
local pending = {}
local TweenService = {}
function TweenService:Create(instance, _info, props)
	local completed = Mocks.newSignal()
	return {
		Completed = completed,
		Play = function()
			for key, value in pairs(props) do
				instance[key] = value
			end
			table.insert(pending, completed)
		end,
		Cancel = function() end,
	}
end
function G.flushTweens()
	local list = pending
	pending = {}
	for _, signal in ipairs(list) do
		signal:Fire()
	end
end

G.game = {
	GetService = function(_, name)
		if name == "TweenService" then
			return TweenService
		end
		error("gui_globals: no service " .. tostring(name))
	end,
}
G.Instance = { new = Mocks.Instance.new }

G.warnings = {}
G.warn = function(...)
	table.insert(G.warnings, table.concat(table.pack(...) :: any, " ", 1, select("#", ...)))
end
G.delayed = {}
G.task = {
	delay = function(_, fn) table.insert(G.delayed, fn) end,
	spawn = function(fn, ...) fn(...) end,
}
G.typeof = function(value)
	local mt = getmetatable(value)
	if mt == C3MT then return "Color3" end
	if mt == UDim2MT then return "UDim2" end
	return type(value)
end

return G
