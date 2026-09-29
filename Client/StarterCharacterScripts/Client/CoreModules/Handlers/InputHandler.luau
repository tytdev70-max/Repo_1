-- Handlers/InputHandler
-- userInputService.InputChanged: mouse wheel zoom, gamepad zoom, touch pinch zoom.

local StateInit   = require(script.Parent.Parent.Boot.StateInit)
local CameraSetup = require(script.Parent.Parent.Boot.CameraSetup)
local ServiceRefs = require(script.Parent.Parent.Boot.ServiceRefs)

local vars             = StateInit.vars
local config           = StateInit.config
local defaultFOV       = StateInit.defaultFOV
local aimFOVTargetRef  = StateInit.aimFOVTargetRef
local scrollZoomInStep = StateInit.scrollZoomInStep
local scrollZoomOutStep= StateInit.scrollZoomOutStep
local gamepadZoomDeadzone = StateInit.gamepadZoomDeadzone
local gamepadZoomStep  = StateInit.gamepadZoomStep
local touchPinchZoomScale = StateInit.touchPinchZoomScale

local userInputService = ServiceRefs.userInputService
local players          = ServiceRefs.players
local player           = players.LocalPlayer

local InputHandler = {}

local function tryAdjustAimFOVWithRange(delta: number): boolean
	if not (vars.aiming and vars.equipped and vars.wepStats) then return false end

	local hasZoomRange = vars.wepStats.aimFovMin
		and vars.wepStats.aimFovMax
		and vars.wepStats.aimFovMin < vars.wepStats.aimFovMax
	if not hasZoomRange then return false end

	local canZoom = not (vars.sightIndex == 2 and vars.wepStats.AimPart2Zoom == false)
	if not canZoom then return false end

	vars.lastZoomChangeTime = tick()
	vars.isArmReverting     = false
	local maxFOV = vars.wepStats.aimFovMax or defaultFOV
	vars.aimFOVTarget = math.clamp(vars.aimFOVTarget - delta, vars.wepStats.aimFovMin, maxFOV)
	aimFOVTargetRef.value = vars.aimFOVTarget
	return true
end

InputHandler.tryAdjustAimFOVWithRange = tryAdjustAimFOVWithRange

local function isHoldForScrollZoomHeld(): boolean
	local keys = config.holdForScrollZoom
	if not keys or #keys == 0 then return true end
	for _, keyCode in keys do
		if userInputService:IsKeyDown(keyCode) then return true end
	end
	return false
end

function InputHandler.init()
	userInputService.InputChanged:Connect(function(input: InputObject)
		if vars.aiming and vars.equipped and input.UserInputType == Enum.UserInputType.MouseWheel then
			local canZoom = not (vars.sightIndex == 2 and vars.wepStats.AimPart2Zoom == false)
			if canZoom
				and vars.wepStats.LPVOZoom
				and vars.wepStats.LPVOZoom.Enabled
				and isHoldForScrollZoomHeld() then
				vars.lastZoomChangeTime = tick()
				vars.isArmReverting     = false
				local maxFOV   = vars.wepStats.aimFovMax or defaultFOV
				local scrollStep = input.Position.Z
					* (if input.Position.Z > 0 then scrollZoomInStep else scrollZoomOutStep)
				vars.aimFOVTarget = math.clamp(
					vars.aimFOVTarget - scrollStep,
					vars.wepStats.aimFovMin, maxFOV)
				aimFOVTargetRef.value = vars.aimFOVTarget
			else
				vars.aimSensitivity = math.clamp(
					vars.aimSensitivity - 0.01 * -input.Position.Z, 0.005, 1)
				userInputService.MouseDeltaSensitivity = vars.aimSensitivity
				player:SetAttribute("SavedAimSensitivity", vars.aimSensitivity)
			end
		end

		local hasZoomRange = vars.wepStats
			and vars.wepStats.aimFovMin
			and vars.wepStats.aimFovMax
			and vars.wepStats.aimFovMin < vars.wepStats.aimFovMax

		if vars.aiming and vars.equipped and hasZoomRange
			and input.UserInputType == Enum.UserInputType.Gamepad1
			and input.KeyCode == Enum.KeyCode.Thumbstick2 then
			local verticalAxis = input.Position.Y
			if math.abs(verticalAxis) > gamepadZoomDeadzone then
				tryAdjustAimFOVWithRange(verticalAxis * gamepadZoomStep)
			end
		end

		if vars.aiming and vars.equipped and hasZoomRange
			and input.UserInputType == Enum.UserInputType.Touch then
			local touches: { InputObject } = {}
			for _, touch in pairs(vars.activeTouches) do
				table.insert(touches, touch)
			end
			if #touches == 2 then
				if not vars._lastPinchDistance then
					vars._lastPinchDistance = (touches[1].Position - touches[2].Position).Magnitude
				else
					local newDist = (touches[1].Position - touches[2].Position).Magnitude
					local delta = (newDist - vars._lastPinchDistance) * touchPinchZoomScale
					vars._lastPinchDistance = newDist
					tryAdjustAimFOVWithRange(delta)
				end
			else
				vars._lastPinchDistance = nil
			end
		end
	end)
end

return InputHandler