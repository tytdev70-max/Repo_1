local ArmPositionMod = {}

local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()
local animBase
local rig
local camera
local defaultFOV
local attachmentSystem
local ubglSystem
local playRepSound
local repLPVORing
local repGripHand
local lpvoThrottle
local lpvoArmThrottle

local lpvoLockedArmMotor: Motor6D? = nil
local prevFOV: number = 0

local function FindArmMotorByName(armName: string): Motor6D?
	local m = animBase:FindFirstChild(armName)
	if m and m:IsA("Motor6D") then return m end

	for _, child in ipairs(animBase:GetChildren()) do
		if child:IsA("Motor6D") then
			local p0, p1 = child.Part0, child.Part1
			if (p0 and p0.Name == armName) or (p1 and p1.Name == armName) then
				return child
			end
		end
	end

	local armPart = rig:FindFirstChild(armName)
	if armPart then
		for _, child in ipairs(animBase:GetChildren()) do
			if child:IsA("Motor6D") and (child.Part0 == armPart or child.Part1 == armPart) then
				return child
			end
		end
	end

	return nil
end
ArmPositionMod.FindArmMotorByName = FindArmMotorByName

--[[
	A magnified optic can supply its own lever ring, so the actuator has to
	prefer the fitted optic's part over the weapon's own. The attachment system
	owns that resolution rule.
]]
local function FindLeverRingPart(gunModel: Model, leverRingName: string): BasePart?
	if not leverRingName then return nil end
	local lever = attachmentSystem.GetLeverRingPart(gunModel, leverRingName)
	if lever and lever:IsA("BasePart") then
		return lever
	end
	return nil
end
ArmPositionMod.FindLeverRingPart = FindLeverRingPart

local function FindLeverRingMotor(gunModel: Model, leverRingPart: BasePart?, leverRingName: string): Motor6D?
	if not leverRingPart then return nil end

	local ownMotor = leverRingPart:FindFirstChildOfClass("Motor6D")
	if ownMotor then
		return ownMotor
	end

	local gripMotor = gunModel.Grip and gunModel.Grip:FindFirstChild(leverRingName)
	if gripMotor and gripMotor:IsA("Motor6D") then
		return gripMotor
	end

	return nil
end
ArmPositionMod.FindLeverRingMotor = FindLeverRingMotor

function ArmPositionMod.Init(deps)
	animBase = deps.animBase
	rig = deps.rig
	camera = deps.camera
	defaultFOV = deps.defaultFOV
	attachmentSystem = deps.attachmentSystem
	ubglSystem = deps.ubglSystem


	playRepSound = deps.playRepSound
	repLPVORing = deps.repLPVORing
	repGripHand = deps.repGripHand
	lpvoThrottle = deps.lpvoThrottle
	lpvoArmThrottle = deps.lpvoArmThrottle

	lpvoLockedArmMotor = nil
	prevFOV = defaultFOV
end

local function UpdateLPVO(dt: number)
	local equipped = vars.equipped
	local wepStats = vars.wepStats
	local gunModel = vars.gunModel
	local aiming = vars.aiming

	if equipped and wepStats and wepStats.LPVOZoom and wepStats.LPVOZoom.Enabled and aiming then
		local leverRingName = wepStats.LPVOZoom.leverRingName
		local leverRing = FindLeverRingPart(gunModel, leverRingName)
		if leverRing and leverRing:IsA("BasePart") then
			local leverMotor = FindLeverRingMotor(gunModel, leverRing, leverRingName)
			if leverMotor and leverMotor:IsA("Motor6D") and not vars.lpvoOriginalCFrame then
				vars.lpvoOriginalCFrame = leverMotor.C0
			end
			if leverMotor and leverMotor:IsA("Motor6D") and vars.lpvoOriginalCFrame then
				local maxFOV = wepStats.aimFovMax or defaultFOV
				local minFOV = wepStats.aimFovMin or 10
				local currentFOV = camera.FieldOfView

				local fovDelta = currentFOV - prevFOV
				if math.abs(fovDelta) > 0.1 then
					if fovDelta < 0 then
						playRepSound("ZoomIn")
					elseif fovDelta > 0 then
						playRepSound("ZoomOut")
					end
				end
				prevFOV = currentFOV

				local zoomRatio = math.clamp((maxFOV - currentFOV) / (maxFOV - minFOV), 0, 1)
				local targetRotation = zoomRatio * wepStats.LPVOZoom.leverRingMaxRotation
				vars.lpvoRingCurrentRotation = vars.lpvoRingCurrentRotation + (targetRotation - vars.lpvoRingCurrentRotation) * 0.3
				local rotationSide = string.lower(wepStats.LPVOZoom.rotationSide or "right")
				local rotZ = 0
				if rotationSide == "left" then
					rotZ = math.rad(vars.lpvoRingCurrentRotation)
				elseif rotationSide == "right" then
					rotZ = math.rad(vars.lpvoRingCurrentRotation)
				end
				local moveDistanceX = wepStats.LPVOZoom.moveCFrameLeftRight or 0
				local moveDistanceY = wepStats.LPVOZoom.moveCFrameUpDown or 0
				local xOffset = zoomRatio * moveDistanceX
				local yOffset = zoomRatio * moveDistanceY
				leverMotor.C0 = vars.lpvoOriginalCFrame * CFrame.new(xOffset, yOffset, 0) * CFrame.Angles(0, 0, rotZ)

				local armName = wepStats.LPVOZoom.armToMove or "Right Arm"
				local armMotor = FindArmMotorByName(armName)

				local hasGrip = attachmentSystem.HasGrip(gunModel)

				if wepStats.LPVOZoom.moveArm == true then
					if armMotor then
						armMotor.Transform = CFrame.new()
						lpvoLockedArmMotor = armMotor
						if not vars.lpvoArmOriginalC0 then
							if vars.gripHandOriginalC0 and vars.currentGripArm == armName then
								vars.lpvoArmOriginalC0 = vars.gripHandOriginalC0
							else
								vars.lpvoArmOriginalC0 = armMotor.C0
							end
						end

						local idleTime = tick() - vars.lastZoomChangeTime

						if idleTime > 1 then
							vars.isArmReverting = true

							if hasGrip then
								vars.lpvoArmActive = false
								vars.lpvoArmPriority = false
								vars.lpvoContestedArmName = nil
								vars.isArmReverting = false
								lpvoLockedArmMotor = nil

								if vars.lpvoServerInteractionActive then
									vars.lpvoServerInteractionActive = false
									repLPVORing.send({
										LeverC0 = leverMotor.C0,
										ArmC0 = nil,
										State = "Exit",
									})
								end
							else
								vars.lpvoArmActive = true
								vars.lpvoArmPriority = false
								vars.lpvoContestedArmName = nil

								local revertSpeed = wepStats.LPVOZoom.armRevertSpeed or 15
								local alpha = math.clamp(dt * 60 * revertSpeed * 0.075, 0, 0.4)
								armMotor.C0 = armMotor.C0:Lerp(vars.lpvoArmOriginalC0, alpha)

								local posDiff = (armMotor.C0.Position - vars.lpvoArmOriginalC0.Position).Magnitude
								local rotDiffCFrame = armMotor.C0 * vars.lpvoArmOriginalC0:Inverse()
								local _, rotAngle = rotDiffCFrame:ToAxisAngle()
								if posDiff < 0.001 and math.abs(rotAngle) < 0.01 then
									armMotor.C0 = vars.lpvoArmOriginalC0
									vars.lpvoArmActive = false
									lpvoLockedArmMotor = nil

									if vars.lpvoServerInteractionActive then
										vars.lpvoServerInteractionActive = false
										repLPVORing.send({
											LeverC0 = leverMotor.C0,
											ArmC0 = nil,
											State = "Exit",
										})
									end
								elseif vars.lpvoServerInteractionActive
									and lpvoArmThrottle:ShouldSend(armMotor.C0, 0.01, function(a, b)
										local posDelta = (a.Position - b.Position).Magnitude
										local _, rotDelta = (a * b:Inverse()):ToAxisAngle()
										return posDelta + math.abs(rotDelta)
									end)
								then
									repLPVORing.send({
										LeverC0 = leverMotor.C0,
										ArmC0 = armMotor.C0,
										State = "Update",
									})
								end
							end
						else
							vars.lpvoArmActive = true
							vars.lpvoArmPriority = true
							vars.lpvoContestedArmName = armName
							vars.isArmReverting = false

							local armRotationMultiplier = wepStats.LPVOZoom.armRotationMultiplier or 0.2
							local armTwistAmount = vars.lpvoRingCurrentRotation * armRotationMultiplier
							local armRotationSide = string.lower(wepStats.LPVOZoom.rotationSideArm or rotationSide)
							local armTwistZ = 0
							if armRotationSide == "left" then
								armTwistZ = math.rad(armTwistAmount)
							else
								armTwistZ = math.rad(-armTwistAmount)
							end

							local armXOffset, armYOffset, armZOffset
							if wepStats.LPVOZoom.zoomPosition then
								local zoomPos = wepStats.LPVOZoom.zoomPosition
								armXOffset = zoomPos.X
								armYOffset = zoomPos.Y
								armZOffset = zoomPos.Z
							else
								local leverRingWorldPos = leverRing.Position
								local gripWorldCFrame = gunModel.Grip.CFrame
								local armOriginalWorldPos = (gripWorldCFrame * vars.lpvoArmOriginalC0).Position
								local offsetToLever = gripWorldCFrame:VectorToObjectSpace(leverRingWorldPos - armOriginalWorldPos)
								local followStrength = 0.5
								armXOffset = offsetToLever.X * followStrength
								armYOffset = offsetToLever.Y * followStrength
								armZOffset = 0
							end

							local targetCFrame = vars.lpvoArmOriginalC0 * CFrame.new(armXOffset, armYOffset, armZOffset) * CFrame.Angles(0, 0, armTwistZ)
							local armMoveAlpha = math.clamp(dt * 60 * (wepStats.LPVOZoom.armMoveSpeed or 18) * 0.06, 0, 0.5)
							armMotor.C0 = armMotor.C0:Lerp(targetCFrame, armMoveAlpha)

							local leverShouldSend = lpvoThrottle:ShouldSend(leverMotor.C0, 0.01, function(a, b)
								return (a.Position - b.Position).Magnitude
							end)
							local armShouldSend = armMotor and lpvoArmThrottle:ShouldSend(armMotor.C0, 0.01, function(a, b)
								local posDelta = (a.Position - b.Position).Magnitude
								local _, rotDelta = (a * b:Inverse()):ToAxisAngle()
								return posDelta + math.abs(rotDelta)
							end)

							if not vars.lpvoServerInteractionActive then
								vars.lpvoServerInteractionActive = true
								repLPVORing.send({
									LeverC0 = leverMotor.C0,
									ArmC0 = armMotor and armMotor.C0 or nil,
									State = "Enter",
								})
							elseif leverShouldSend or armShouldSend then
								repLPVORing.send({
									LeverC0 = leverMotor.C0,
									ArmC0 = armMotor and armMotor.C0 or nil,
									State = "Update",
								})
							end
						end
					end
				end
			end
		end
	else
		vars.isArmReverting = false
		vars.lpvoArmPriority = false
		vars.lpvoContestedArmName = nil
		vars.lastZoomDirection = 0
		vars.lpvoRingCurrentRotation = vars.lpvoRingCurrentRotation + (0 - vars.lpvoRingCurrentRotation) * 0.2

		if vars.lpvoOriginalCFrame and gunModel and wepStats and wepStats.LPVOZoom then
			local leverRing = FindLeverRingPart(gunModel, wepStats.LPVOZoom.leverRingName)
			if leverRing and leverRing:IsA("BasePart") then
				local leverMotor = FindLeverRingMotor(gunModel, leverRing, wepStats.LPVOZoom.leverRingName)
				if leverMotor and leverMotor:IsA("Motor6D") then
					local rotationSide = string.lower(wepStats.LPVOZoom.rotationSide or "right")
					local rotZ = 0
					if rotationSide == "left" then
						rotZ = math.rad(vars.lpvoRingCurrentRotation)
					elseif rotationSide == "right" then
						rotZ = math.rad(vars.lpvoRingCurrentRotation)
					end
					local maxFOV = wepStats.aimFovMax or defaultFOV
					local minFOV = wepStats.aimFovMin or 10
					local currentFOV = camera.FieldOfView
					local zoomRatio = math.clamp((maxFOV - currentFOV) / (maxFOV - minFOV), 0, 1)
					local moveDistanceX = wepStats.LPVOZoom.moveCFrameLeftRight or 0
					local moveDistanceY = wepStats.LPVOZoom.moveCFrameUpDown or 0
					local xOffset = zoomRatio * moveDistanceX
					local yOffset = zoomRatio * moveDistanceY
					leverMotor.C0 = vars.lpvoOriginalCFrame * CFrame.new(xOffset, yOffset, 0) * CFrame.Angles(0, 0, rotZ)
				end
			end
		end

		local hasGrip = attachmentSystem.HasGrip(gunModel)

		if hasGrip and vars.lpvoServerInteractionActive then
			vars.lpvoServerInteractionActive = false
			local exitLeverC0 = CFrame.new()
			if wepStats.LPVOZoom then
				local exitLeverPart = FindLeverRingPart(gunModel, wepStats.LPVOZoom.leverRingName)
				local exitLeverMotor = exitLeverPart and FindLeverRingMotor(gunModel, exitLeverPart, wepStats.LPVOZoom.leverRingName)
				if exitLeverMotor then
					exitLeverC0 = exitLeverMotor.C0
				end
			end
			repLPVORing.send({
				LeverC0 = exitLeverC0,
				ArmC0 = nil,
				State = "Exit",
			})
		end

		if vars.lpvoArmOriginalC0 and not hasGrip then
			local leverMotor = gunModel and gunModel.Grip:FindFirstChild(wepStats.LPVOZoom.leverRingName)
			local armName = wepStats and wepStats.LPVOZoom and wepStats.LPVOZoom.armToMove or "Right Arm"
			local armMotor = FindArmMotorByName(armName)
			if armMotor then
				armMotor.Transform = CFrame.new()
				vars.lpvoArmActive = true
				lpvoLockedArmMotor = armMotor
				local revertSpeed = wepStats and wepStats.LPVOZoom and wepStats.LPVOZoom.armRevertSpeed or 12
				local alpha = math.clamp(dt * revertSpeed * 0.15, 0, 0.35)
				armMotor.C0 = armMotor.C0:Lerp(vars.lpvoArmOriginalC0, alpha)

				vars.isArmReverting = true

				if lpvoArmThrottle:ShouldSend(armMotor.C0, 0.01, function(a, b)
						local posDelta = (a.Position - b.Position).Magnitude
						local _, rotDelta = (a * b:Inverse()):ToAxisAngle()
						return posDelta + math.abs(rotDelta)
					end) then
					repLPVORing.send({
						LeverC0 = leverMotor and leverMotor.C0 or CFrame.new(),
						ArmC0 = armMotor.C0,
						State = "Update",
					})
				end

				if (armMotor.C0.Position - vars.lpvoArmOriginalC0.Position).Magnitude < 0.001 then
					armMotor.C0 = vars.lpvoArmOriginalC0
					vars.lpvoArmOriginalC0 = nil
					vars.isArmReverting = false
					vars.lpvoArmActive = false
					lpvoLockedArmMotor = nil
					vars.lpvoServerInteractionActive = false
					repLPVORing.send({
						LeverC0 = leverMotor and leverMotor.C0 or CFrame.new(),
						ArmC0 = nil,
						State = "Exit",
					})
				end
			else
				vars.lpvoArmOriginalC0 = nil
				vars.isArmReverting = false
				vars.lpvoArmActive = false
				lpvoLockedArmMotor = nil
			end
		end
	end
end

local function UpdateGripHand(dt: number)
	local equipped = vars.equipped
	local gunModel = vars.gunModel
	local wepStats = vars.wepStats
	local loadedAnims = vars.loadedAnims
	local sprinting = vars.sprinting
	local reloading = vars.reloading

	if equipped and gunModel then
		local gripData = attachmentSystem.GetGrip(gunModel, equipped.Name)

		if gripData then
			local armName = gripData.handToPosition or "Left Arm"
			local armMotor = FindArmMotorByName(armName)

			if armMotor then
				if not vars.gripHandOriginalC0 then
					vars.gripHandOriginalC0 = armMotor.C0
				end
				vars.currentGripArm = armName

				local boltCloseAnimPlaying = false
				if wepStats.boltClose and loadedAnims[wepStats.boltClose] then
					boltCloseAnimPlaying = loadedAnims[wepStats.boltClose].IsPlaying
				end

				local isIdle = vars.holdStance == 0
					and not sprinting
					and not reloading
					and not vars.inspecting
					and not vars.chambering
					and not vars.magCheckDebounce
					and not vars.fireModeCheckDebounce
					and not vars.switchingFireMode
					and not vars.togglingAttachment
					and not vars.equipping
					and not vars.unequipping
					and not vars.blocked
					and not boltCloseAnimPlaying
					and not ubglSystem.IsActive()
					and not ubglSystem.IsToggling()

				local lpvoOwnsArm = vars.lpvoArmPriority and vars.lpvoContestedArmName == armName

				if lpvoOwnsArm then
					vars.isGripHandActive = false
					vars.lastGripHandC0 = nil
				elseif isIdle then
					vars.isGripHandActive = true

					local armPart = rig:FindFirstChild(armName)
					local handEndLocalOffset = CFrame.new(1.2, -1.2, -0.2)
					local desiredArmCenterWorldCFrame
					if gripData.matchRotation then
						desiredArmCenterWorldCFrame = gripData.gripWorldCFrame * handEndLocalOffset:Inverse()
					else
						local restWorldCFrame = animBase.CFrame * vars.gripHandOriginalC0
						local restRotationOnly = restWorldCFrame - restWorldCFrame.Position
						local handEndWorldPosition = gripData.gripWorldCFrame.Position
						local centerToHandWorld = restRotationOnly:VectorToWorldSpace(Vector3.new(0, -(armPart.Size.Y / 2), 0))
						desiredArmCenterWorldCFrame = restRotationOnly + (handEndWorldPosition - centerToHandWorld)
					end
					local targetC0 = animBase.CFrame:ToObjectSpace(desiredArmCenterWorldCFrame)

					if targetC0 then
						if vars.firstPerson then
							local alpha = math.clamp(dt * gripData.transitionSpeed, 0, 0.5)
							armMotor.C0 = armMotor.C0:Lerp(targetC0, alpha)
						end

						if not vars.lastGripHandC0 or (targetC0.Position - vars.lastGripHandC0.Position).Magnitude > 0.08 then
							vars.lastGripHandC0 = targetC0
							repGripHand.send({ ArmC0 = targetC0, ArmName = armName })
						end
					end
				else
					vars.isGripHandActive = false

					if vars.firstPerson then
						local alpha = math.clamp(dt * 20, 0, 0.5)
						armMotor.C0 = armMotor.C0:Lerp(vars.gripHandOriginalC0, alpha)

						if (armMotor.C0.Position - vars.gripHandOriginalC0.Position).Magnitude < 0.005 then
							armMotor.C0 = vars.gripHandOriginalC0
						end
					end

					if vars.lastGripHandC0 ~= nil then
						vars.lastGripHandC0 = nil
						repGripHand.send({ ArmC0 = nil, ArmName = armName })
					end
				end
			end
		else
			if vars.isGripHandActive and vars.gripHandOriginalC0 and vars.currentGripArm then
				local armMotor = FindArmMotorByName(vars.currentGripArm)
				if armMotor then
					local alpha = math.clamp(dt * 20, 0, 0.5)
					armMotor.C0 = armMotor.C0:Lerp(vars.gripHandOriginalC0, alpha)

					if vars.lastGripHandC0 ~= nil then
						vars.lastGripHandC0 = nil
						repGripHand.send({ ArmC0 = nil, ArmName = vars.currentGripArm })
					end

					if (armMotor.C0.Position - vars.gripHandOriginalC0.Position).Magnitude < 0.005 then
						armMotor.C0 = vars.gripHandOriginalC0
						vars.gripHandOriginalC0 = nil
						vars.isGripHandActive = false
						vars.currentGripArm = nil
					end
				end
			end
		end
	end
end

function ArmPositionMod.Update(dt: number)
	if not vars.equipped then
		return
	end

	UpdateLPVO(dt)
	UpdateGripHand(dt)
end

function ArmPositionMod.ResetLockedArmTransform()
	if vars.lpvoArmActive and lpvoLockedArmMotor and lpvoLockedArmMotor.Parent then
		lpvoLockedArmMotor.Transform = CFrame.new()
	end
end

function ArmPositionMod.Cleanup()
	local wepStats = vars.wepStats

	if vars.gripHandOriginalC0 and vars.currentGripArm then
		local armMotor = FindArmMotorByName(vars.currentGripArm)
		if armMotor then
			armMotor.C0 = vars.gripHandOriginalC0
			armMotor:SetAttribute("OriginalC0_Grip", nil)
		end
		repGripHand.send({ ArmC0 = nil, ArmName = vars.currentGripArm })
		vars.gripHandOriginalC0 = nil
		vars.isGripHandActive = false
		vars.currentGripArm = nil
		vars.lastGripHandC0 = nil
	end

	if vars.lpvoArmOriginalC0 then
		local armName = wepStats and wepStats.LPVOZoom and wepStats.LPVOZoom.armToMove or "Right Arm"
		local armMotor = FindArmMotorByName(armName)
		if armMotor then
			armMotor.C0 = vars.lpvoArmOriginalC0
			armMotor:SetAttribute("OriginalC0", nil)
		end
		vars.lpvoArmOriginalC0 = nil
	end

	if vars.lpvoServerInteractionActive then
		repLPVORing.send({
			LeverC0 = CFrame.new(),
			ArmC0 = nil,
			State = "Exit",
		})
	end

	vars.lpvoArmActive = false
	vars.lpvoArmPriority = false
	vars.lpvoContestedArmName = nil
	lpvoLockedArmMotor = nil
	vars.lpvoServerInteractionActive = false
end

function ArmPositionMod.ResetState()
	vars.lpvoRingCurrentRotation = 0
	vars.lpvoOriginalCFrame = nil
	vars.lastZoomDirection = 0
	vars.lpvoArmOriginalC0 = nil
	vars.lpvoArmActive = false
	vars.lpvoArmPriority = false
	vars.lpvoContestedArmName = nil
	vars.lpvoServerInteractionActive = false
	lpvoLockedArmMotor = nil
	prevFOV = defaultFOV
end

return ArmPositionMod