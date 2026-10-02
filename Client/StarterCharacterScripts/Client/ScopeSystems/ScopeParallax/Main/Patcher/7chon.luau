local Method = {}
Method.aimpartZOffset = 0.5

local SEVENCHON_CHARACTER_FOLDER_NAME = "Saude"
local SEVENCHON_CLIENT_SCRIPT_NAME = "ACS_Clientv2"
local SEVENCHON_VERSION_MARKER_NAME = "Debugs"

local StarterPlayer = game:GetService("StarterPlayer")
local StarterCharacterScripts = StarterPlayer.StarterCharacterScripts
local Default = require(script.Parent:WaitForChild("Default"))

function Method.autoDetectMethod(): string?
	local characterFolder = StarterCharacterScripts:FindFirstChild(SEVENCHON_CHARACTER_FOLDER_NAME)
	if not characterFolder then
		return nil
	end

	local clientScript = characterFolder:FindFirstChild(SEVENCHON_CLIENT_SCRIPT_NAME)
	if not clientScript then
		return nil
	end

	if clientScript:FindFirstChild(SEVENCHON_VERSION_MARKER_NAME) then
		return script.Name
	end

	return nil
end

Method.modelDetectionPath = Default.modelDetectionPath
Method.modelDetectionMethod = Default.modelDetectionMethod

function Method.parentingMethod(scopeFocusPart: Instance)
	task.spawn(function()
		repeat
			task.wait()
		until scopeFocusPart:FindFirstChildWhichIsA("Motor6D")
		scopeFocusPart.Parent = workspace
	end)
end

return Method