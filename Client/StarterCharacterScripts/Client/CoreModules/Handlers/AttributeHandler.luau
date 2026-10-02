-- Handlers/AttributeHandler
-- Sprinting, Stance, Airborne attribute change signals.

local CharacterRefs       = require(script.Parent.Parent.Boot.CharacterRefs)
local StateInit           = require(script.Parent.Parent.Boot.StateInit)
local SpringsAndThrottles = require(script.Parent.Parent.Boot.SpringsAndThrottles)
local AssetRefs           = require(script.Parent.Parent.Boot.AssetRefs)
local SystemInits         = require(script.Parent.Parent.ModuleInits.SystemModuleInits)
local ViewmodelSetup      = require(script.Parent.Parent.Boot.ViewmodelSetup)

local character       = CharacterRefs.character
local humanoid        = CharacterRefs.humanoid
local vars            = StateInit.vars
local config          = StateInit.config

local gunRecoilSpring = SpringsAndThrottles.gunRecoilSpring
local swaySpring      = SpringsAndThrottles.swaySpring

local WeaponBindings      = SystemInits.WeaponBindings
local proceduralWalkCycle = ViewmodelSetup.proceduralWalkCycle

local toggleViewmodelSprint = AssetRefs.toggleViewmodelSprint

local AttributeHandler = {}

function AttributeHandler.init()
	-- Sprinting
	character:GetAttributeChangedSignal("Sprinting"):Connect(function()
		vars.sprinting = character:GetAttribute("Sprinting") == true
		local stance = character:GetAttribute("Stance")
		if vars.sprinting and vars.equipped and (stance == "Standing" or not stance) then
			WeaponBindings.ToggleSprint(true)
		else
			WeaponBindings.ToggleSprint(false)
		end
	end)

	toggleViewmodelSprint.Event:Connect(function(toggle: boolean)
		local stance = character:GetAttribute("Stance")
		if toggle and (stance == "Crouched" or stance == "Prone") then
			WeaponBindings.ToggleSprint(false)
			vars.sprinting = false
			character:SetAttribute("Sprinting", false)
			character:SetAttribute("HoldingSprint", false)
		else
			WeaponBindings.ToggleSprint(toggle)
			vars.sprinting = toggle
		end
		if not toggle then vars.aimHeld = false end
	end)

	-- Stance
	character:GetAttributeChangedSignal("Stance"):Connect(function()
		local stance = character:GetAttribute("Stance")
		if ((stance == "Crouched") or (config.proneEnabled and stance == "Prone")) and vars.sprinting then
			vars.sprinting = false
			WeaponBindings.ToggleSprint(false)
			character:SetAttribute("Sprinting", false)
			character:SetAttribute("HoldingSprint", false)
		end
		if stance == "Crouched" or stance == "Prone" then
			toggleViewmodelSprint:Fire(false)
		end
	end)

	-- Airborne
	local lastAirborne: number = 0
	character:GetAttributeChangedSignal("Airborne"):Connect(function()
		local newValue = character:GetAttribute("Airborne") == true
		local airTime  = tick() - lastAirborne

		if not newValue and vars.airborne and airTime >= 0.5 then
			if vars.equipped then
				gunRecoilSpring:shove(Vector3.new(-1, 0, -0.15))
				swaySpring:shove(Vector3.new(0, -0.55, 0.15))
			end
			local onWater = humanoid.FloorMaterial == Enum.Material.Water
			if not onWater then
				local rootPart = character:FindFirstChild("HumanoidRootPart")
				if rootPart and rootPart:IsA("BasePart") then
					local raycastParams = RaycastParams.new()
					raycastParams.FilterDescendantsInstances = { character }
					raycastParams.FilterType = Enum.RaycastFilterType.Exclude
					local result = workspace:Raycast(
						rootPart.Position, Vector3.new(0, -5, 0), raycastParams)
					if result and result.Material == Enum.Material.Water then
						onWater = true
					end
				end
			end

			vars.stepPhase      = vars.stepPhase % 1
			vars.currentStep    = math.floor(vars.stepPhase * 2)
			vars.lastStepTime   = tick() - proceduralWalkCycle.Config.stepImpactDuration

		elseif newValue and not vars.airborne then
			if vars.equipped then
				gunRecoilSpring:shove(Vector3.new(0.5, 0, 0.12))
				swaySpring:shove(Vector3.new(0, 0.45, -0.2))
				vars.walkInertiaPos = vars.walkInertiaPos * 0.5
				vars.walkInertiaRot = vars.walkInertiaRot * 0.5
			end
		end

		vars.airborne = newValue
		if vars.airborne then lastAirborne = tick() end
	end)
end

return AttributeHandler