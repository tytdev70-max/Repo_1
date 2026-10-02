--!strict

local Players = game:GetService("Players")

local MAX_OPACITY: number = 0.45
local FADE_IN_SPEED: number = 9
local FADE_OUT_SPEED: number = 12
local SNAP_EPSILON: number = 0.002

local AimVignetteMod = {}

local vignette: ImageLabel? = nil
local targetTransparency: number = 1
local currentTransparency: number = 1

local function ResolveVignette(): ImageLabel?
	if vignette and vignette.Parent then
		return vignette
	end

	vignette = nil

	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	local ui = playerGui:FindFirstChild("SPH_UI")
	local found = ui and ui:FindFirstChild("AimVignette")
	if found and found:IsA("ImageLabel") then
		vignette = found
	end

	return vignette
end

local function Write(transparency: number)
	local label = ResolveVignette()
	if label then
		label.ImageTransparency = transparency
	end
end

function AimVignetteMod.SetAiming(aiming: boolean)
	targetTransparency = if aiming then MAX_OPACITY else 1
end

function AimVignetteMod.Update(deltaTime: number)
	if currentTransparency == targetTransparency then
		return
	end

	local speed = if targetTransparency < currentTransparency then FADE_IN_SPEED else FADE_OUT_SPEED
	local alpha = math.clamp(deltaTime * speed, 0, 1)
	currentTransparency += (targetTransparency - currentTransparency) * alpha

	if math.abs(targetTransparency - currentTransparency) <= SNAP_EPSILON then
		currentTransparency = targetTransparency
	end

	Write(currentTransparency)
end

function AimVignetteMod.Reset()
	targetTransparency = 1
	currentTransparency = 1
	Write(1)
	vignette = nil
end

return AimVignetteMod
