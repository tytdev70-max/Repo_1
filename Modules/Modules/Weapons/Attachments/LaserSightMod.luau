local LaserSightMod = {}
local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()

local workspace = game:GetService("Workspace")

local LASER_BEAM_LENGTH = 1.8

local deps = {}

local laserDotPart, laserDotLight
local laserSourceProxy, laserBeamEndProxy
local laserBeamFP, laserBeamTP

local otherPlayerLasers = {}

local localLaserRayParams = RaycastParams.new()
localLaserRayParams.FilterType = Enum.RaycastFilterType.Exclude
localLaserRayParams.RespectCanCollide = true

local WORKSPACE_INSTANCE_NAMES = {
	LocalLaserDot = true,
	OtherPlayerLaserDot = true,
}

local TERRAIN_INSTANCE_NAMES = {
	LaserSourceProxy = true,
	LaserBeamEndProxy = true,
	FirstPersonLaser = true,
	ThirdPersonLaser = true,
	OtherLaserBeamEnd = true,
	OtherPlayerLaser = true,
}

local function DestroyEntry(data)
	if not data then return end
	if data.beam    and data.beam.Parent    then data.beam:Destroy()    end
	if data.beamEnd and data.beamEnd.Parent then data.beamEnd:Destroy() end
	if data.dot     and data.dot.Parent     then data.dot:Destroy()     end
end

local function EntryIsStale(otherChar, data)
	if not otherChar or not otherChar.Parent then return true end
	local laserPart = data.laserPart
	if not laserPart or not laserPart.Parent then return true end
	return not laserPart:IsDescendantOf(otherChar)
end

local function ClearOtherPlayerLasers()
	for otherChar, data in pairs(otherPlayerLasers) do
		DestroyEntry(data)
		otherPlayerLasers[otherChar] = nil
	end
end

local function SweepOrphanedInstances()
	for _, child in ipairs(workspace:GetChildren()) do
		if WORKSPACE_INSTANCE_NAMES[child.Name] then
			child:Destroy()
		end
	end
	for _, child in ipairs(workspace.Terrain:GetChildren()) do
		if TERRAIN_INSTANCE_NAMES[child.Name] then
			child:Destroy()
		end
	end
end

local function DestroyLocalLaserInstances()
	if laserDotPart      then laserDotPart:Destroy()      end
	if laserSourceProxy  then laserSourceProxy:Destroy()  end
	if laserBeamEndProxy then laserBeamEndProxy:Destroy() end
	if laserBeamFP       then laserBeamFP:Destroy()       end
	if laserBeamTP       then laserBeamTP:Destroy()       end

	laserDotPart, laserDotLight = nil, nil
	laserSourceProxy, laserBeamEndProxy = nil, nil
	laserBeamFP, laserBeamTP = nil, nil
end

local function CreateLocalLaserInstances()
	laserDotPart = Instance.new("Part")
	laserDotPart.Name = "LocalLaserDot"
	laserDotPart.Shape = Enum.PartType.Ball
	laserDotPart.Size = Vector3.new(0.045, 0.045, 0.045)
	laserDotPart.Material = Enum.Material.Neon
	laserDotPart.Color = Color3.fromRGB(255, 30, 30)
	laserDotPart.Anchored = true
	laserDotPart.CanCollide = false
	laserDotPart.CanQuery = false
	laserDotPart.CanTouch = false
	laserDotPart.CastShadow = false
	laserDotPart.CFrame = deps.storageCFrame
	laserDotPart.Parent = workspace

	laserDotLight = Instance.new("PointLight")
	laserDotLight.Color = Color3.fromRGB(255, 60, 60)
	laserDotLight.Shadows = true
	laserDotLight.Brightness = 0.5
	laserDotLight.Range = 1
	laserDotLight.Parent = laserDotPart

	laserSourceProxy = Instance.new("Attachment")
	laserSourceProxy.Name = "LaserSourceProxy"
	laserSourceProxy.Parent = workspace.Terrain

	laserBeamEndProxy = Instance.new("Attachment")
	laserBeamEndProxy.Name = "LaserBeamEndProxy"
	laserBeamEndProxy.Parent = workspace.Terrain

	laserBeamFP = Instance.new("Beam")
	laserBeamFP.Name = "FirstPersonLaser"
	laserBeamFP.Attachment0 = laserSourceProxy
	laserBeamFP.Attachment1 = laserBeamEndProxy
	laserBeamFP.LightInfluence = 0
	laserBeamFP.Brightness = 3
	laserBeamFP.Segments = 4
	laserBeamFP.Width0 = 0.022
	laserBeamFP.Width1 = 0.004
	laserBeamFP.FaceCamera = true
	laserBeamFP.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0,    0.05),
		NumberSequenceKeypoint.new(0.55, 0.60),
		NumberSequenceKeypoint.new(1,    1.0),
	})
	laserBeamFP.Color = ColorSequence.new(Color3.fromRGB(255, 30, 30))
	laserBeamFP.Parent = workspace.Terrain
	laserBeamFP.Enabled = false

	laserBeamTP = laserBeamFP:Clone()
	laserBeamTP.Name = "ThirdPersonLaser"
	laserBeamTP.Parent = workspace.Terrain
	laserBeamTP.Enabled = false
end

function LaserSightMod.Init(dependencies)
	deps = dependencies
	DestroyLocalLaserInstances()
	ClearOtherPlayerLasers()
	SweepOrphanedInstances()
	CreateLocalLaserInstances()
end

local function ApplyLaserGlareState(fpLaserSource, enabled, laserColor)
	if not deps.glareMod then return end
	local tpLaserSource = nil
	if deps.getThirdPersonGunModel then
		local tpGunModel = deps.getThirdPersonGunModel()
		tpLaserSource = tpGunModel and deps.attachmentSystem.GetLaserSource(tpGunModel)
	end
	deps.glareMod.SetLaserModelActive(fpLaserSource, tpLaserSource, vars.firstPerson, enabled, laserColor)
end

function LaserSightMod.ToggleLocalLaser()
	if not laserDotPart then return end
	local wepStats = vars.wepStats
	local gunModel = vars.gunModel
	local loadedAnims = vars.loadedAnims

	local fireAnimPlaying = wepStats and wepStats.fireAnim
		and loadedAnims[wepStats.fireAnim]
		and loadedAnims[wepStats.fireAnim].IsPlaying

	if vars.togglingAttachment or deps.isAnimationBusy() or vars.sprinting
		or vars.holdStance ~= 0 or fireAnimPlaying then return end

	local laserSource = deps.attachmentSystem.GetLaserSource(gunModel)

	if wepStats.activateFlashlightLaser and not deps.isAnimationBusy() then
		vars.togglingAttachment = true
		local animTrack = deps.playAnimation(wepStats.activateFlashlightLaser, {priority = Enum.AnimationPriority.Action2})

		if animTrack then
			local keyframeConnection
			keyframeConnection = animTrack.KeyframeReached:Connect(function(keyframeName)
				if keyframeName == "Button" then
					vars.laserEnabled = not vars.laserEnabled
					deps.playRepSound("Button")
					deps.playerToggleAttachment.send({ AttachmentType = 1, Enabled = vars.laserEnabled })
					local laserColor = Color3.fromRGB(255, 30, 30)
					if laserSource and laserSource:FindFirstChild("Color") then
						laserColor = laserSource.Color.Value
						laserDotPart.Color = laserColor
						laserDotLight.Color = laserColor
						laserBeamFP.Color = ColorSequence.new(laserColor)
						laserBeamTP.Color = ColorSequence.new(laserColor)
					end
					ApplyLaserGlareState(laserSource, vars.laserEnabled, laserColor)
					keyframeConnection:Disconnect()
				end
			end)
			animTrack.Stopped:Once(function()
				vars.togglingAttachment = false
			end)
		else
			vars.laserEnabled = not vars.laserEnabled
			if not vars.firstPerson then laserBeamTP.Enabled = true end
			deps.playRepSound("Button")
			deps.playerToggleAttachment.send({ AttachmentType = 1, Enabled = vars.laserEnabled })
			local laserColor = Color3.fromRGB(255, 30, 30)
			if laserSource and laserSource:FindFirstChild("Color") then
				laserColor = laserSource.Color.Value
				laserDotPart.Color = laserColor
				laserDotLight.Color = laserColor
				laserBeamFP.Color = ColorSequence.new(laserColor)
				laserBeamTP.Color = ColorSequence.new(laserColor)
			end
			ApplyLaserGlareState(laserSource, vars.laserEnabled, laserColor)
			vars.togglingAttachment = false
		end
	else
		vars.laserEnabled = not vars.laserEnabled
		deps.playRepSound("Button")
		deps.playerToggleAttachment.send({ AttachmentType = 1, Enabled = vars.laserEnabled })
		local laserSource = deps.attachmentSystem.GetLaserSource(gunModel)
		local laserColor = Color3.fromRGB(255, 30, 30)
		if laserSource and laserSource:FindFirstChild("Color") then
			laserColor = laserSource.Color.Value
			laserDotPart.Color = laserColor
			laserDotLight.Color = laserColor
			laserBeamFP.Color = ColorSequence.new(laserColor)
			laserBeamTP.Color = ColorSequence.new(laserColor)
		end
		ApplyLaserGlareState(laserSource, vars.laserEnabled, laserColor)
	end
end

function LaserSightMod.UpdateLocalLaser()
	if not laserDotPart or not laserBeamFP or not laserBeamTP then return end
	local equipped = vars.equipped
	local gunModel = vars.gunModel

	if vars.laserEnabled and equipped then
		local laserStillPresent = gunModel.Grip:FindFirstChild("Laser") or deps.attachmentSystem.HasLaser(gunModel)
		if not laserStillPresent then
			vars.laserEnabled = false
			laserDotPart.CFrame = deps.storageCFrame
			laserBeamFP.Enabled = false
			laserBeamTP.Enabled = false
			laserBeamTP.Attachment0 = nil
		end
	end

	if equipped and vars.laserEnabled then
		local fpLaserSourceSync = deps.attachmentSystem.GetLaserSource(gunModel)
		local tpModelSync = deps.getThirdPersonGunModel and deps.getThirdPersonGunModel()
		local tpLaserSourceSync = tpModelSync and deps.attachmentSystem.GetLaserSource(tpModelSync)
		if deps.glareMod and (fpLaserSourceSync or tpLaserSourceSync) then
			local syncColor = (fpLaserSourceSync and fpLaserSourceSync:FindFirstChild("Color") and fpLaserSourceSync.Color.Value)
				or (tpLaserSourceSync and tpLaserSourceSync:FindFirstChild("Color") and tpLaserSourceSync.Color.Value)
				or Color3.fromRGB(255, 30, 30)
			deps.glareMod.SetLaserModelActive(fpLaserSourceSync, tpLaserSourceSync, vars.firstPerson, true, syncColor)
		end

		if not laserBeamFP.Enabled and not laserBeamTP.Enabled then
			local laserSrc = deps.attachmentSystem.GetLaserSource(gunModel)
			local laserColor = (laserSrc and laserSrc:FindFirstChild("Color") and laserSrc.Color.Value)
				or Color3.fromRGB(255, 30, 30)
			laserDotPart.Color  = laserColor
			laserDotLight.Color = laserColor
			laserBeamFP.Color   = ColorSequence.new(laserColor)
			laserBeamTP.Color   = ColorSequence.new(laserColor)
		end

		local laserPoint
		if vars.firstPerson then
			laserPoint = deps.attachmentSystem.GetLaserSource(gunModel)
		else
			local tpModel = deps.getThirdPersonGunModel()
			laserPoint = tpModel and deps.attachmentSystem.GetLaserSource(tpModel)
		end

		if laserPoint and laserPoint:IsA("Attachment") then
			laserSourceProxy.WorldCFrame = laserPoint.WorldCFrame

			local t = tick()
			local animWidth = math.max(0.008, 0.022
				+ math.sin(t * 58) * 0.003
				+ math.sin(t * 31) * 0.002)
			laserBeamFP.Width0 = animWidth
			laserBeamTP.Width0 = animWidth

			if vars.firstPerson then
				if not laserBeamFP.Enabled then laserBeamFP.Enabled = true  end
				if laserBeamTP.Enabled      then laserBeamTP.Enabled = false end
			else
				laserBeamTP.Attachment0 = laserPoint
				if not laserBeamTP.Enabled then laserBeamTP.Enabled = true  end
				if laserBeamFP.Enabled      then laserBeamFP.Enabled = false end
			end

			localLaserRayParams.FilterDescendantsInstances = {gunModel, deps.character}
			local rayResult = workspace:Raycast(
				laserPoint.WorldPosition,
				laserPoint.WorldCFrame.LookVector * 600,
				localLaserRayParams
			)

			if rayResult then
				local hitDist = (rayResult.Position - laserPoint.WorldPosition).Magnitude
				laserBeamEndProxy.WorldCFrame = laserPoint.WorldCFrame
					* CFrame.new(0, 0, -math.min(hitDist, LASER_BEAM_LENGTH))
				laserDotPart.CFrame = CFrame.new(rayResult.Position + rayResult.Normal * 0.04)
			else
				laserBeamEndProxy.WorldCFrame = laserPoint.WorldCFrame * CFrame.new(0, 0, -LASER_BEAM_LENGTH)
				laserDotPart.CFrame = deps.storageCFrame
			end
		else
			laserBeamFP.Enabled = false
			laserBeamTP.Enabled = false
			laserDotPart.CFrame = deps.storageCFrame
		end
	elseif laserBeamFP.Enabled or laserBeamTP.Enabled then
		laserBeamFP.Enabled = false
		laserBeamTP.Enabled = false
		laserDotPart.CFrame = deps.storageCFrame
	end
end

function LaserSightMod.HandleToggleAttachmentReplicate(Data)
	local laserPart, toggle, otherCharacter = Data.LaserPart, Data.Toggle, Data.OtherCharacter
	if not otherCharacter or otherCharacter == deps.character then return end
	if not laserPart or laserPart.Name ~= "Laser" then return end

	if toggle then
		local existing = otherPlayerLasers[otherCharacter]
		if existing then
			if existing.laserPart == laserPart and existing.beam and existing.beam.Parent then return end
			DestroyEntry(existing)
			otherPlayerLasers[otherCharacter] = nil
		end

		local laserColor = Color3.fromRGB(255, 30, 30)
		if laserPart:FindFirstChild("Color") then
			laserColor = laserPart.Color.Value
		end

		if deps.glareMod then
			deps.glareMod.SetLaserActive(laserPart, true, laserColor)
		end

		local dotPart = Instance.new("Part")
		dotPart.Name = "OtherPlayerLaserDot"
		dotPart.Shape = Enum.PartType.Ball
		dotPart.Size = Vector3.new(0.045, 0.045, 0.045)
		dotPart.Material = Enum.Material.Neon
		dotPart.Color = laserColor
		dotPart.Anchored = true
		dotPart.CanCollide = false
		dotPart.CanQuery = false
		dotPart.CanTouch = false
		dotPart.CastShadow = false
		dotPart.CFrame = deps.storageCFrame
		dotPart.Parent = workspace
		local dotLight = Instance.new("PointLight")
		dotLight.Color = laserColor
		dotLight.Shadows = true
		dotLight.Brightness = 0.5
		dotLight.Range = 1
		dotLight.Parent = dotPart

		local beamEnd = Instance.new("Attachment")
		beamEnd.Name = "OtherLaserBeamEnd"
		beamEnd.Parent = workspace.Terrain

		local beam = Instance.new("Beam")
		beam.Name = "OtherPlayerLaser"
		beam.Attachment0 = laserPart
		beam.Attachment1 = beamEnd
		beam.LightInfluence = 0
		beam.Brightness = 3
		beam.Segments = 4
		beam.Width0 = 0.022
		beam.Width1 = 0.004
		beam.FaceCamera = true
		beam.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0,    0.05),
			NumberSequenceKeypoint.new(0.55, 0.60),
			NumberSequenceKeypoint.new(1,    1.0),
		})
		beam.Color = ColorSequence.new(laserColor)
		beam.Enabled = true
		beam.Parent = workspace.Terrain

		otherPlayerLasers[otherCharacter] = {
			beam     = beam,
			beamEnd  = beamEnd,
			dot      = dotPart,
			dotLight = dotLight,
			laserPart = laserPart,
		}
	else
		DestroyEntry(otherPlayerLasers[otherCharacter])
		otherPlayerLasers[otherCharacter] = nil
		if deps.glareMod then
			deps.glareMod.SetLaserActive(laserPart, false)
		end
	end
end

function LaserSightMod.UpdateOtherPlayerLasers()
	for otherChar, data in pairs(otherPlayerLasers) do
		if EntryIsStale(otherChar, data) then
			DestroyEntry(data)
			otherPlayerLasers[otherChar] = nil
			continue
		end

		local otherHumanoid = otherChar:FindFirstChildOfClass("Humanoid")
		if otherHumanoid and otherHumanoid.Health <= 0 then
			DestroyEntry(data)
			otherPlayerLasers[otherChar] = nil
			continue
		end

		data.beamEnd.WorldCFrame = data.laserPart.WorldCFrame * CFrame.new(0, 0, -LASER_BEAM_LENGTH)

		local t = tick()
		data.beam.Width0 = math.max(0.008, 0.022 + math.sin(t * 58) * 0.003 + math.sin(t * 31) * 0.002)

		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = {otherChar}
		rp.RespectCanCollide = true
		local laserDir = data.laserPart.WorldCFrame.LookVector
		local hit = workspace:Raycast(data.laserPart.WorldPosition, laserDir * 600, rp)
		if hit then
			local hitDist = (hit.Position - data.laserPart.WorldPosition).Magnitude
			data.beamEnd.WorldCFrame = data.laserPart.WorldCFrame
				* CFrame.new(0, 0, -math.min(hitDist, LASER_BEAM_LENGTH))
			data.dot.CFrame = CFrame.new(hit.Position + hit.Normal * 0.04)
		else
			data.beamEnd.WorldCFrame = data.laserPart.WorldCFrame * CFrame.new(0, 0, -LASER_BEAM_LENGTH)
			data.dot.CFrame = deps.storageCFrame
		end
	end
end

function LaserSightMod.Reset()
	if laserDotPart then laserDotPart.CFrame = deps.storageCFrame end
	if laserBeamFP then laserBeamFP.Enabled = false end
	if laserBeamTP then
		laserBeamTP.Enabled = false
		laserBeamTP.Attachment0 = laserSourceProxy
	end
end

function LaserSightMod.Destroy()
	DestroyLocalLaserInstances()
	ClearOtherPlayerLasers()
	SweepOrphanedInstances()
end

return LaserSightMod