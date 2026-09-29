--!strict

--// Modules
local ScopeConfig = require(script:WaitForChild("ScopeConfig"))
local Activate = require(script:WaitForChild("Activate"))
local Detect = require(script:WaitForChild("Detect"))
local Patcher = require(script:WaitForChild("Patcher"))

local Main = {}

--// Helpers

local function hasAimPart(model: Model): boolean
	local prefix = ScopeConfig.aimPartPrefix
	for _, child in model:GetChildren() do
		if child:IsA("BasePart") and string.sub(child.Name, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

--// Functions
function Main.init(character: Model)
	Patcher.init()
	Detect.init()

	for _, child in character:GetChildren() do
		if child:IsA("Model") and hasAimPart(child) then
			Activate.start(child, Patcher)
		end
	end
end

return Main