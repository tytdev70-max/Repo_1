local Method = {}
Method.aimpartZOffset = 0

local SPEARHEAD_ASSETS_FOLDER_NAME = "SPH_Assets"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local camera = workspace.CurrentCamera
local Default = require(script.Parent:WaitForChild("Default"))

function Method.autoDetectMethod(): string?
	local spearheadFolder = ReplicatedStorage:FindFirstChild(SPEARHEAD_ASSETS_FOLDER_NAME)
	if spearheadFolder then
		return script.Name
	end
	return nil
end

function Method.modelDetectionPath(): Instance
	local weaponRig = camera:WaitForChild("WeaponRig")
	local weaponFolder = weaponRig:WaitForChild("Weapon")
	return weaponFolder
end

function Method.modelDetectionMethod(obj: Instance): Model?
	return obj :: Model
end

Method.parentingMethod = Default.parentingMethod

return Method