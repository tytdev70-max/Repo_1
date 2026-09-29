local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PhysicsService = game:GetService("PhysicsService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local modules = assets.Modules
local explosionMod = require(modules.Effects.Explosions.ExplosionFX)

local eventsFolder = assets:WaitForChild("Events")
local explosionEventsFolder = eventsFolder:WaitForChild("ExplosionEvents")

local smokeSpawnRemote = explosionEventsFolder:FindFirstChild("SmokeSpawnRequest")
if not smokeSpawnRemote then
	smokeSpawnRemote = Instance.new("RemoteEvent")
	smokeSpawnRemote.Name = "SmokeSpawnRequest"
	smokeSpawnRemote.Parent = explosionEventsFolder
end

local module = {}

local smokeCloudFinishedRemote = explosionEventsFolder:FindFirstChild("SmokeCloudFinishedRequest")
if not smokeCloudFinishedRemote then
	smokeCloudFinishedRemote = Instance.new("RemoteEvent")
	smokeCloudFinishedRemote.Name = "SmokeCloudFinishedRequest"
	smokeCloudFinishedRemote.Parent = explosionEventsFolder
end

local smokeCatchUpRequestRemote = explosionEventsFolder:FindFirstChild("SmokeCatchUpRequest")
if not smokeCatchUpRequestRemote then
	smokeCatchUpRequestRemote = Instance.new("RemoteEvent")
	smokeCatchUpRequestRemote.Name = "SmokeCatchUpRequest"
	smokeCatchUpRequestRemote.Parent = explosionEventsFolder
end

local nextSmokeToken = 0
local function GetNextSmokeToken()
	nextSmokeToken += 1
	return "smoke_" .. tostring(nextSmokeToken) .. "_" .. tostring(os.clock())
end

local activeSmokeClouds = {}

local function GetGrenadesFolder()
	local sphWorkspace = workspace:WaitForChild("SPH_Workspace")
	local grenadesFolder = sphWorkspace:FindFirstChild("Grenades")
	if not grenadesFolder then
		grenadesFolder = Instance.new("Folder")
		grenadesFolder.Name = "Grenades"
		grenadesFolder.Parent = sphWorkspace
	end
	return grenadesFolder
end

local function FindNamedBasePart(model, partName)
	if not model then return nil end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name == partName then
			return desc
		end
	end
	return nil
end

function module.DetachGrenadeCosmeticGroup(gunModel, detachConfig, shellsFolder)
	if not gunModel or not detachConfig or not detachConfig.id or not detachConfig.parts then return end

	local attrName = "SPH_Detached_" .. detachConfig.id
	if gunModel:GetAttribute(attrName) then return end
	gunModel:SetAttribute(attrName, true)

	local grip = gunModel:FindFirstChild("Grip")

	for _, partName in ipairs(detachConfig.parts) do
		local part = FindNamedBasePart(gunModel, partName)
		if part and part:IsA("BasePart") then
			local motor = grip and grip:FindFirstChild(partName)
			if motor and motor:IsA("Motor6D") then
				motor:Destroy()
			end

			part.Parent = shellsFolder
			part.CollisionGroup = "Casings"
			part.CanCollide = true
			part.CanTouch = false
			part.CastShadow = true
			part.Anchored = false
			part.Massless = true
			part.Transparency = part:GetAttribute("OriginalTransparency") or 0
			part.CanQuery = true
			part.AssemblyLinearVelocity = Vector3.new(
				math.random(-20, 20) / 10, math.random(10, 30) / 10, math.random(-20, 20) / 10
			)
			part.AssemblyAngularVelocity = Vector3.new(
				math.random(-6, 6), math.random(-6, 6), math.random(-6, 6)
			)

			local fadeDelay = detachConfig.fadeDelay or 1
			local fadeTime = detachConfig.fadeTime or 0.3
			Debris:AddItem(part, fadeDelay + fadeTime + 1)

			task.delay(fadeDelay, function()
				if not part or not part.Parent then return end
				TweenService:Create(part, TweenInfo.new(fadeTime), {Transparency = 1}):Play()
			end)
		end
	end
end

function module.DetachAllGrenadeCosmetics(gunModel, grenadeConfig, shellsFolder)
	if not gunModel or not grenadeConfig or not grenadeConfig.detachables then return end
	for _, detachConfig in ipairs(grenadeConfig.detachables) do
		module.DetachGrenadeCosmeticGroup(gunModel, detachConfig, shellsFolder)
	end
end

module.FindNamedBasePart = FindNamedBasePart

local throwRaycastParams = nil

local function GetThrowRaycastParams()
	if not throwRaycastParams then
		throwRaycastParams = RaycastParams.new()
		throwRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
		throwRaycastParams.IgnoreWater = true
		throwRaycastParams.RespectCanCollide = true
		for _, group in ipairs(PhysicsService:GetRegisteredCollisionGroups()) do
			if group.name == "Grenades" then
				throwRaycastParams.CollisionGroup = "Grenades"
				break
			end
		end
	end
	return throwRaycastParams
end

local function BuildThrowFilter(character, ignoreModel)
	local filter = {}
	if character then table.insert(filter, character) end
	if ignoreModel then table.insert(filter, ignoreModel) end
	return filter
end

local function GetProjectileRadius(primary)
	return math.max(primary.Size.X, primary.Size.Y, primary.Size.Z) * 0.5
end

local function ResolveSpawnOrigin(character, primary, origin, ignoreModel)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return origin end

	local bodyPosition = rootPart.Position
	local offset = origin - bodyPosition
	local distance = offset.Magnitude
	if distance < 0.01 then return origin end

	local direction = offset.Unit
	local radius = GetProjectileRadius(primary)

	local params = GetThrowRaycastParams()
	params.FilterDescendantsInstances = BuildThrowFilter(character, ignoreModel)

	local forwardHit = workspace:Raycast(bodyPosition, offset, params)
	if forwardHit then
		local clearDistance = math.max(0, (forwardHit.Position - bodyPosition).Magnitude - radius - 0.05)
		return bodyPosition + direction * clearDistance, forwardHit.Normal
	end

	params.FilterDescendantsInstances = BuildThrowFilter(character, ignoreModel)
	local backwardHit = workspace:Raycast(origin, -offset, params)
	if backwardHit then
		return bodyPosition - direction * (radius + 0.1), -backwardHit.Normal
	end

	return origin
end

local function GetBlockingNormal(character, primary, spawnOrigin, throwDirection, ignoreModel)
	local params = GetThrowRaycastParams()
	params.FilterDescendantsInstances = BuildThrowFilter(character, ignoreModel)

	local probeDistance = GetProjectileRadius(primary) + 1
	local result = workspace:Raycast(spawnOrigin, throwDirection * probeDistance, params)
	return result and result.Normal or nil
end

function module.Throw(player, wepStats, origin, direction, isDeathDrop, isLowThrow)
	local grenadeConfig = wepStats.grenade
	if not grenadeConfig then
		warn("[GrenadeHandler] '" .. tostring(wepStats.projectile) .. "' has no wepStats.grenade config table.")
		return
	end

	local lowThrowConfig = (isLowThrow == true) and grenadeConfig.lowThrow or nil

	local function GetConfigValue(key, default)
		if lowThrowConfig and lowThrowConfig[key] ~= nil then
			return lowThrowConfig[key]
		elseif grenadeConfig[key] ~= nil then
			return grenadeConfig[key]
		else
			return default
		end
	end

	local projectiles = assets.Projectiles
	local template = projectiles:FindFirstChild(wepStats.projectile)
	if not template then
		for _, folder in ipairs(projectiles:GetChildren()) do
			if folder:IsA("Folder") then
				local found = folder:FindFirstChild(wepStats.projectile)
				if found then
					template = found
					break
				end
			end
		end
	end
	if not template then
		warn("[GrenadeHandler] No projectile model named '" .. tostring(wepStats.projectile) .. "' found under SPH_Assets.Projectiles.")
		return
	end

	local grenadeModel = template:Clone()

	local primary = grenadeModel.PrimaryPart
		or grenadeModel:FindFirstChild("Handle")
		or grenadeModel:FindFirstChildWhichIsA("BasePart", true)

	if not primary then
		warn("[GrenadeHandler] Projectile model '" .. tostring(wepStats.projectile) .. "' has no BasePart to use as PrimaryPart.")
		grenadeModel:Destroy()
		return
	end

	grenadeModel.PrimaryPart = primary

	local physicalProps = PhysicalProperties.new(
		GetConfigValue("density", 2.5),
		GetConfigValue("friction", 0.6),
		GetConfigValue("bounciness", 0.35)
	)

	for _, part in ipairs(grenadeModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CustomPhysicalProperties = physicalProps
			part.CollisionGroup = "Grenades"

			if part == primary then
				part.CanCollide = true
				part.CanTouch = true
			else
				part.CanCollide = false
				part.CanTouch = false
				CollectionService:AddTag(part, "SPH_NoCollide")

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = primary
				weld.Part1 = part
				weld.Parent = primary
			end
		end
	end

	for _, part in ipairs(grenadeModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Transparency = 0
			part.LocalTransparencyModifier = 0
		end
	end

	local throwerCharacter = player and player.Character
	local spawnOrigin, blockedNormal = ResolveSpawnOrigin(throwerCharacter, primary, origin, grenadeModel)

	grenadeModel:SetPrimaryPartCFrame(CFrame.new(spawnOrigin, spawnOrigin + direction))
	grenadeModel.Parent = GetGrenadesFolder()

	primary.AssemblyLinearVelocity = Vector3.zero
	primary.AssemblyAngularVelocity = Vector3.zero

	if isDeathDrop then
		primary.AssemblyLinearVelocity = Vector3.new(
			math.random(-3, 3) / 10,
			0,
			math.random(-3, 3) / 10
		)
		primary.AssemblyAngularVelocity = Vector3.new(
			math.random(-3, 3),
			math.random(-3, 3),
			math.random(-3, 3)
		)
	else
		local throwSpeed = GetConfigValue("throwSpeed", 60)
		local upwardAngle = math.rad(GetConfigValue("throwUpwardAngle", 0))
		local pitchedDirection = (CFrame.new(Vector3.zero, direction) * CFrame.Angles(-upwardAngle, 0, 0)).LookVector

		local surfaceNormal = blockedNormal or GetBlockingNormal(throwerCharacter, primary, spawnOrigin, pitchedDirection, grenadeModel)
		if surfaceNormal and pitchedDirection:Dot(surfaceNormal) < 0 then
			local reflected = pitchedDirection - 2 * pitchedDirection:Dot(surfaceNormal) * surfaceNormal
			primary.AssemblyLinearVelocity = reflected.Unit * throwSpeed * 0.35
		else
			primary.AssemblyLinearVelocity = pitchedDirection * throwSpeed
		end
		primary.AssemblyAngularVelocity = GetConfigValue("spinVelocity", Vector3.new(10, 5, 5))
	end

	local ownerOk = pcall(function()
		primary:SetNetworkOwner(player)
	end)
	if not ownerOk then
		warn("[GrenadeHandler] Could not set network owner for '" .. tostring(wepStats.projectile) .. "'; simulating on the server instead.")
	end

	local exploded = false

	local BOUNCE_SOUND_COOLDOWN = 0.15  -- seconds between plays
	local BOUNCE_MIN_SPEED      = 1     -- studs/sec
	local lastBounceSoundTime   = 0

	local bounceSoundFolder = assets.Sounds:FindFirstChild("GrenadeBounce")

	local function PlayBounceSound()
		if not bounceSoundFolder then return end

		local now = tick()
		if now - lastBounceSoundTime < BOUNCE_SOUND_COOLDOWN then return end

		if primary.AssemblyLinearVelocity.Magnitude < BOUNCE_MIN_SPEED then return end

		lastBounceSoundTime = now

		local soundPool = bounceSoundFolder:GetChildren()
		if #soundPool == 0 then return end

		local template = soundPool[math.random(#soundPool)]
		if not template:IsA("Sound") then return end

		local newSound = template:Clone()
		newSound.PlaybackSpeed += math.random(-5, 5) / 100
		newSound.Parent = primary
		newSound:Play()
		Debris:AddItem(newSound, newSound.TimeLength + 0.1)
	end

	local bounceConn
	bounceConn = primary.Touched:Connect(function(hit)
		if exploded then return end
		if hit:IsDescendantOf(grenadeModel) then return end
		if player.Character and hit:IsDescendantOf(player.Character) then return end
		PlayBounceSound()
	end)

	grenadeModel.Destroying:Connect(function()
		if bounceConn then
			bounceConn:Disconnect()
			bounceConn = nil
		end
	end)

	local fuseTime = GetConfigValue("fuseTime", 3)
	Debris:AddItem(grenadeModel, fuseTime + 8)

	local safetyConn

	local function Detonate()
		if exploded then return end
		exploded = true
		if safetyConn then
			safetyConn:Disconnect()
			safetyConn = nil
		end
		if grenadeModel and grenadeModel.Parent then
			local explosionOrigin = primary.Position

			local flashRadius = GetConfigValue("flashRadius", 0)
			local flashbangConfig = nil
			if flashRadius > 0 then
				flashbangConfig = {
					flashRadius = flashRadius,
					flashMaxDuration = GetConfigValue("flashMaxDuration", 3),
					flashMinDuration = GetConfigValue("flashMinDuration", 0.5),
					flashFacingFalloff = GetConfigValue("flashFacingFalloff", 1),
					flashCoreFraction = GetConfigValue("flashCoreFraction", 0),
					flashFalloffExponent = GetConfigValue("flashFalloffExponent", 1),

					flashWhiteFlashEnabled     = GetConfigValue("flashWhiteFlashEnabled", true),
					flashWhiteFlashTime        = GetConfigValue("flashWhiteFlashTime", 0.08),
					flashWhiteFlashMaxDistance = GetConfigValue("flashWhiteFlashMaxDistance", nil),

					flashBlackoutEnabled     = GetConfigValue("flashBlackoutEnabled", true),
					flashBlackoutFadeInTime  = GetConfigValue("flashBlackoutFadeInTime", 0.25),
					flashBlackoutMaxDistance = GetConfigValue("flashBlackoutMaxDistance", nil),

					flashGlareEnabled            = GetConfigValue("flashGlareEnabled", true),
					flashGlares                  = GetConfigValue("flashGlares", nil),
					flashGlareBackFacingCutoff   = GetConfigValue("flashGlareBackFacingCutoff", 0),

					flashDesaturateEnabled          = GetConfigValue("flashDesaturateEnabled", true),
					flashDesaturateMaxDistance      = GetConfigValue("flashDesaturateMaxDistance", nil),
					flashDesaturateCurveExponent    = GetConfigValue("flashDesaturateCurveExponent", 0.5),
					flashDesaturateMaxContrast      = GetConfigValue("flashDesaturateMaxContrast", 0.6),
					flashDesaturateMaxBrightness    = GetConfigValue("flashDesaturateMaxBrightness", 0.35),

					flashBlurEnabled           = GetConfigValue("flashBlurEnabled", true),
					flashBlurMaxSize           = GetConfigValue("flashBlurMaxSize", 28),
					flashBlurMaxDistance       = GetConfigValue("flashBlurMaxDistance", nil),
					flashBlurFadeInTime        = GetConfigValue("flashBlurFadeInTime", 0.15),
					flashBlurFadeOutMultiplier = GetConfigValue("flashBlurFadeOutMultiplier", 1.6),

					flashMuffleEnabled = GetConfigValue("flashMuffleEnabled", true),
				}
			end

			local smokeCfg = grenadeConfig.smoke
			local isSmokeGrenade = smokeCfg ~= nil

			explosionMod(
				explosionOrigin,
				GetConfigValue("blastRadius", 15),
				GetConfigValue("explosionType", "Frag"),
				player,
				flashbangConfig,
				isSmokeGrenade and {
					isSmoke = true,
					skipVisualFX = true,
					skipExplosionSound = GetConfigValue("disableExplosionSound", true),
					skipCameraShake = GetConfigValue("disableCameraShake", true),
				} or nil
			)

			if isSmokeGrenade then
				local smokeCfgToSend = smokeCfg
				if not smokeCfg.shapeSeed then
					smokeCfgToSend = table.clone(smokeCfg)
					smokeCfgToSend.shapeSeed = math.random(1, 1000000)
				end
				local cloudToken = GetNextSmokeToken()
				smokeSpawnRemote:FireAllClients(explosionOrigin, smokeCfgToSend, cloudToken)
				activeSmokeClouds[cloudToken] = {
					origin = explosionOrigin,
					config = smokeCfgToSend,
					spawnClock = os.clock(),
				}

				for _, part in ipairs(grenadeModel:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CanCollide = false
						part.CanTouch = false
						part.Anchored = true
					end
				end

				local growTime = smokeCfg.growTime or 2
				local dissipateStartTime = smokeCfg.dissipateStartTime or 10
				local dissipateTime = smokeCfg.dissipateTime or 4
				local puffFadeGrace = smokeCfg.puffFadeGrace or 1.5
				local canisterFadeTime = smokeCfg.canisterFadeTime or 1.5
				local hissFadeTime = smokeCfg.hissFadeTime or 0.6

				local hissDuration = growTime + dissipateStartTime
				local emitterSettleDuration = dissipateTime + puffFadeGrace

				local hissSound
				if smokeCfg.hissSoundId and smokeCfg.hissSoundId ~= 0 and smokeCfg.hissSoundId ~= "" then
					local hissHost = grenadeModel.PrimaryPart or grenadeModel:FindFirstChildWhichIsA("BasePart")
					if hissHost then
						hissSound = Instance.new("Sound")
						hissSound.Name = "SmokeHiss"
						local id = smokeCfg.hissSoundId
						hissSound.SoundId = (typeof(id) == "number") and ("rbxassetid://" .. tostring(id)) or tostring(id)
						hissSound.Volume = smokeCfg.hissVolume or 1
						hissSound.Looped = true
						hissSound.RollOffMode = Enum.RollOffMode.InverseTapered
						hissSound.RollOffMaxDistance = math.max((smokeCfg.radius or 16) * 8, 120)
						hissSound.Parent = hissHost
						hissSound:Play()
					end
				end

				local hissStopped = false
				local function StopHiss()
					if hissStopped or not hissSound or not hissSound.Parent then return end
					hissStopped = true
					local snd = hissSound
					local tween = TweenService:Create(snd, TweenInfo.new(hissFadeTime, Enum.EasingStyle.Quad), {Volume = 0})
					tween:Play()
					tween.Completed:Once(function()
						if snd and snd.Parent then
							snd:Stop()
							snd:Destroy()
						end
					end)
				end

				task.delay(hissDuration, StopHiss)

				task.spawn(function()
					local completedEvent = Instance.new("BindableEvent")
					local reportConn
					reportConn = smokeCloudFinishedRemote.OnServerEvent:Connect(function(_, token)
						if token == cloudToken then
							completedEvent:Fire()
						end
					end)

					local safetyMargin = 5
					local maxWait = hissDuration + emitterSettleDuration + safetyMargin
					local timeoutThread = task.delay(maxWait, function()
						completedEvent:Fire()
					end)

					completedEvent.Event:Wait()

					if reportConn then
						reportConn:Disconnect()
					end
					task.cancel(timeoutThread)
					completedEvent:Destroy()
					activeSmokeClouds[cloudToken] = nil

					StopHiss()
					if not grenadeModel or not grenadeModel.Parent then return end
					for _, part in ipairs(grenadeModel:GetDescendants()) do
						if part:IsA("BasePart") then
							TweenService:Create(part, TweenInfo.new(canisterFadeTime, Enum.EasingStyle.Quad), {Transparency = 1}):Play()
						end
					end
					Debris:AddItem(grenadeModel, canisterFadeTime + 0.1)
				end)
			else
				grenadeModel:Destroy()
			end
		end
	end

	safetyConn = RunService.Heartbeat:Connect(function()
		if exploded or not primary or not primary.Parent then
			if safetyConn then
				safetyConn:Disconnect()
				safetyConn = nil
			end
			return
		end
		if primary.Position.Y < (workspace.FallenPartsDestroyHeight + 50) then
			Detonate()
		end
	end)

	task.delay(fuseTime, Detonate)

	return grenadeModel
end

if RunService:IsServer() then
	smokeCatchUpRequestRemote.OnServerEvent:Connect(function(player)
		for cloudToken, cloud in pairs(activeSmokeClouds) do
			local elapsedTime = os.clock() - cloud.spawnClock
			local cfgToSend = table.clone(cloud.config)
			cfgToSend.__elapsedTime = elapsedTime
			smokeSpawnRemote:FireClient(player, cloud.origin, cfgToSend, cloudToken)
		end
	end)
end

return module