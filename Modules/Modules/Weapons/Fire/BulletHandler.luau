local module = {}

local debugMode = false

local debris = game:GetService("Debris")
local tweenService = game:GetService("TweenService")
local replicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local assets = replicatedStorage.SPH_Assets
local modules = assets.Modules
local config = require(modules.Parent.GameConfig)
local hitFX = require(modules.Effects.Blood.HitFX)
local Network = require(modules.Core.Networking.SPH_Network)
local MaterialCodec = require(modules.Core.Networking.MaterialCodec)
local partCache = require(modules.Core.Utility.PartCache)
local pierceMod = require(modules.Weapons.Fire.PierceMod)
local attachmentManager = require(modules.Weapons.Attachments.AttachmentManager)
local visualisationManager = require(modules.Effects.Rendering.Visualisation_Manager)
local FastCast = require(modules.ThirdParty.FastCast)
local SmokeVoxelMod = require(modules.Effects.Environment.SmokeVoxelMod)
local SPH_Events = require(modules.Core.Networking.SPH_Events)

local sphWorkspace = workspace:WaitForChild("SPH_Workspace")
local bulletContainer = sphWorkspace:WaitForChild("Projectiles")
local cacheContainer = sphWorkspace:WaitForChild("Cache")

local VECTOR3_ZERO = Vector3.zero
local VECTOR2_ZERO = Vector2.zero
local BASE_BULLET = script.Bullet
local MAX_BULLETS = config.maxBullets or 300
local TRACER_START_DISTANCE = config.tracerStartDistance
local FIRE_EFFECT_DISTANCE = config.fireEffectDistance
local SUPPRESSION_DISTANCE = 60
local nextBulletId = 0

local suppression = SPH_Events.Find("CombatEvents", "Suppression")

if not suppression and RunService:IsClient() then
	suppression = SPH_Events.Get("CombatEvents", "Suppression")
end

local bulletProvider = partCache.new(BASE_BULLET:Clone(), MAX_BULLETS, cacheContainer)

local rayParams = RaycastParams.new()
rayParams.IgnoreWater = false
rayParams.RespectCanCollide = false
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local player, character, humanoidRootPart
local _characterAddedConn

local baseFilterInstances = {}
local trackedAccessories = {}
FastCast.VisualizeCasts = debugMode

local caster = FastCast.new()

local bulletBehavior = FastCast.newBehavior()
bulletBehavior.RaycastParams = rayParams
bulletBehavior.MaxDistance = config.maxBulletDistance
bulletBehavior.AutoIgnoreContainer = true
bulletBehavior.CosmeticBulletContainer = bulletContainer
bulletBehavior.CosmeticBulletProvider = bulletProvider
bulletBehavior.HighFidelityBehavior = FastCast.HighFidelityBehavior.Default
bulletBehavior.CanPierceFunction = pierceMod.CanPierce

local function CloneShotBehavior(carriedPierced)
	local shotBehavior = table.clone(bulletBehavior)

	local shotParams = RaycastParams.new()
	shotParams.IgnoreWater = rayParams.IgnoreWater
	shotParams.RespectCanCollide = rayParams.RespectCanCollide
	shotParams.FilterType = rayParams.FilterType

	local filterList = table.clone(rayParams.FilterDescendantsInstances)
	if carriedPierced then
		for _, part in ipairs(carriedPierced) do
			table.insert(filterList, part)
		end
	end
	shotParams.FilterDescendantsInstances = filterList

	shotBehavior.RaycastParams = shotParams
	return shotBehavior
end

local function resolveProjectileTemplate(projectileName: string): Instance?
	if not projectileName or projectileName == "" or projectileName == "Bullet" then
		return nil
	end
	local projectiles = assets.Projectiles

	local direct = projectiles:FindFirstChild(projectileName)
	if direct and not direct:IsA("Folder") then
		return direct
	end

	for _, folder in ipairs(projectiles:GetChildren()) do
		if folder:IsA("Folder") then
			local found = folder:FindFirstChild(projectileName)
			if found and not found:IsA("Folder") then
				return found
			end
		end
	end
	return nil
end

local function ResolveProjectileOrientation(wepStats, isUBGL)
	local orientation = wepStats.projectileOrientation
	if isUBGL and wepStats.UBGL and wepStats.UBGL.ProjectileOrientation then
		orientation = wepStats.UBGL.ProjectileOrientation
	end
	if typeof(orientation) ~= "CFrame" then
		return CFrame.identity
	end
	return orientation.Rotation
end

local function CoerceDropEnabled(value, fallback)
	if value == nil then
		return fallback
	end
	return value == true
end

local function ResolveDropEnabled(wepStats, isUBGL)
	if isUBGL and typeof(wepStats.UBGL) == "table" then
		local ubgl = wepStats.UBGL
		local dropFlag = ubgl.BulletDrop
		if dropFlag == nil then
			dropFlag = ubgl.bulletDrop
		end

		return CoerceDropEnabled(dropFlag, true)
	end
	return wepStats.bulletDrop == true
end

local function FreezeProjectilePhysics(instance)
	local function freezePart(part)
		part.Anchored = true
		part.CanCollide = false
		part.Massless = true
		part.AssemblyLinearVelocity = VECTOR3_ZERO
		part.AssemblyAngularVelocity = VECTOR3_ZERO
	end

	if instance:IsA("BasePart") then
		freezePart(instance)
	end
	for _, desc in ipairs(instance:GetDescendants()) do
		if desc:IsA("BasePart") then
			freezePart(desc)
		end
	end
end

local viewmodelRig = nil

local function RebuildRayFilter()
	local list = {character, workspace.CurrentCamera, bulletContainer, cacheContainer}
	if viewmodelRig then
		table.insert(list, viewmodelRig)
	end
	baseFilterInstances = list
	rayParams.FilterDescendantsInstances = list
end

module.SetViewmodelRig = function(rig)
	viewmodelRig = rig
	RebuildRayFilter()
end

local initialized = false

module.Initialize = function(newPlayer)
	if not initialized then
		initialized = true
		bulletContainer:ClearAllChildren()
		cacheContainer:ClearAllChildren()
		bulletProvider = partCache.new(BASE_BULLET:Clone(), MAX_BULLETS, cacheContainer)
	end

	player = newPlayer
	character = newPlayer.Character
	humanoidRootPart = character:WaitForChild("HumanoidRootPart")
	RebuildRayFilter()

	if _characterAddedConn then _characterAddedConn:Disconnect() end
	_characterAddedConn = newPlayer.CharacterAdded:Connect(function(newChar)
		character = newChar
		humanoidRootPart = newChar:WaitForChild("HumanoidRootPart")
		viewmodelRig = nil
		RebuildRayFilter()
	end)
end

local function ResetBullet(bulletPart)
	local baseBullet = BASE_BULLET

	bulletPart.BulletSmoke.Enabled = false
	bulletPart.PointLight.Enabled = false
	bulletPart.DistanceEffect.Enabled = false
	bulletPart.BeamLong.Enabled = false
	bulletPart.Transparency = 1
	bulletPart.CanCollide = false

	bulletPart.Color = baseBullet.Color
	bulletPart.BeamLong.Color = baseBullet.BeamLong.Color
	bulletPart.PointLight.Color = baseBullet.PointLight.Color
	bulletPart.DistanceEffect.Dot.ImageColor3 = baseBullet.DistanceEffect.Dot.ImageColor3
	bulletPart.DistanceEffect.Flare.ImageColor3 = baseBullet.DistanceEffect.Flare.ImageColor3

	local fakeBullet = bulletPart:FindFirstChild("FakeBullet")
	if fakeBullet then
		fakeBullet:Destroy()
	end
end

local activeAutoSounds = {}
local autoFireShotCount = {}
local autoFireTimers = {}

local function PlaySFX(parent, playerFired, isAutoFire, wepStats, isSuppressed, soundNameOverride)
	local camera = workspace.CurrentCamera
	if not camera then return end

	local originPos
	if parent:IsA("BasePart") then
		originPos = parent.Position
	elseif parent:IsA("Attachment") then
		originPos = parent.WorldPosition
	elseif parent:IsA("Model") and parent.PrimaryPart then
		originPos = parent.PrimaryPart.Position
	else
		return
	end

	local listenerPos = camera.CFrame.Position
	local distance = (listenerPos - originPos).Magnitude

	local soundToPlay
	if soundNameOverride then
		soundToPlay = soundNameOverride
	elseif distance >= config.echoDistanceTrigger then
		soundToPlay = isSuppressed and "SilencedEcho" or "Echo"
	else
		if isSuppressed then
			soundToPlay = isAutoFire and "SilencedAutoFire" or "SilencedFire"
		else
			soundToPlay = isAutoFire and "AutoFire" or "Fire"
		end
	end

	if isAutoFire and soundToPlay == "SilencedAutoFire" then
		local parentKey = tostring(playerFired.UserId)

		if autoFireTimers[parentKey] then
			task.cancel(autoFireTimers[parentKey])
			autoFireTimers[parentKey] = nil
		end

		autoFireShotCount[parentKey] = (autoFireShotCount[parentKey] or 0) + 1

		if autoFireShotCount[parentKey] < 2 then
			local fireSound = parent:FindFirstChild("SilencedFire")
			if fireSound and fireSound:IsA("Sound") then
				local newFire = fireSound:Clone()
				newFire.PlaybackSpeed += math.random(-10, 10) / config.fireSoundVariation
				newFire.Name = fireSound.Name .. "_Playing"

				local host = Instance.new("Part")
				host.Size = Vector3.new(0.2, 0.2, 0.2)
				host.CanCollide = false
				host.Transparency = 1
				host.Name = "TempSoundHost"

				local isLocalPlayer = (playerFired == player)
				if isLocalPlayer and character then
					local head = character:FindFirstChild("Head")
					if head then
						host.CFrame = head.CFrame + head.CFrame.LookVector * 2
						host.Anchored = false
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = head
						weld.Part1 = host
						weld.Parent = host
					else
						host.Anchored = true
						host.CFrame = workspace.CurrentCamera.CFrame
					end
				else
					host.Anchored = true
					host.CFrame = CFrame.new(originPos)
				end

				newFire.Parent = host
				host.Parent = workspace
				newFire:Play()
				debris:AddItem(host, newFire.TimeLength > 0 and newFire.TimeLength or 5)
			end

			autoFireTimers[parentKey] = task.delay(0.2, function()
				autoFireShotCount[parentKey] = nil
				autoFireTimers[parentKey] = nil
			end)

			return
		end

		if not activeAutoSounds[parentKey] then
			local autoFireSound = parent:FindFirstChild("SilencedAutoFire")
			if not autoFireSound or not autoFireSound:IsA("Sound") then
				return
			end

			local loopSound = autoFireSound:Clone()
			loopSound.Looped = true

			local host = Instance.new("Part")
			host.Size = Vector3.new(0.2, 0.2, 0.2)
			host.CanCollide = false
			host.Transparency = 1
			host.Name = "AutoFireHost"

			local isLocalPlayer = (playerFired == player)
			if isLocalPlayer and character then
				local head = character:FindFirstChild("Head")
				if head then
					host.CFrame = head.CFrame + head.CFrame.LookVector * 2
					host.Anchored = false
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = head
					weld.Part1 = host
					weld.Parent = host
				else
					host.Anchored = true
					host.CFrame = workspace.CurrentCamera.CFrame
				end
			else
				host.Anchored = true
				host.CFrame = CFrame.new(originPos)
			end

			loopSound.Parent = host
			host.Parent = workspace
			loopSound:Play()

			activeAutoSounds[parentKey] = {
				sound = loopSound,
				lastFireTime = tick(),
				parent = parent,
				host = host,
				isSuppressed = isSuppressed
			}

			task.spawn(function()
				local stopDuration = (wepStats and wepStats.autoFireSoundDuration) or 0.2

				while activeAutoSounds[parentKey] do
					task.wait(0.02)
					local data = activeAutoSounds[parentKey]
					if data then
						if not data.sound.IsPlaying then
							data.sound:Play()
						end

						if tick() - data.lastFireTime >= stopDuration then
							data.sound:Stop()
							if data.host and data.host.Parent then
								data.host:Destroy()
							end

							local autoTail = data.parent:FindFirstChild("SilencedAutoTail")
							if autoTail and autoTail:IsA("Sound") then
								local tailClone = autoTail:Clone()
								local tailHost = Instance.new("Part")
								tailHost.Size = Vector3.new(0.2,0.2,0.2)
								tailHost.CanCollide = false
								tailHost.Transparency = 1
								tailHost.Anchored = true
								tailHost.CFrame = CFrame.new(originPos)
								tailClone.Parent = tailHost
								tailHost.Parent = workspace
								tailClone:Play()
								debris:AddItem(tailHost, tailClone.TimeLength > 0 and tailClone.TimeLength or 2)
							end

							activeAutoSounds[parentKey] = nil
							autoFireShotCount[parentKey] = nil

							if autoFireTimers[parentKey] then
								task.cancel(autoFireTimers[parentKey])
								autoFireTimers[parentKey] = nil
							end

							break
						end
					else
						break
					end
				end
			end)
		else
			activeAutoSounds[parentKey].lastFireTime = tick()
		end

		return
	elseif isAutoFire and soundToPlay == "AutoFire" then
		local parentKey = tostring(playerFired.UserId)

		if autoFireTimers[parentKey] then
			task.cancel(autoFireTimers[parentKey])
			autoFireTimers[parentKey] = nil
		end

		autoFireShotCount[parentKey] = (autoFireShotCount[parentKey] or 0) + 1

		if autoFireShotCount[parentKey] < 2 then
			local fireSound = parent:FindFirstChild("Fire")
			if fireSound and fireSound:IsA("Sound") then
				local newFire = fireSound:Clone()
				newFire.PlaybackSpeed += math.random(-10, 10) / config.fireSoundVariation
				newFire.Name = fireSound.Name .. "_Playing"

				local host = Instance.new("Part")
				host.Size = Vector3.new(0.2, 0.2, 0.2)
				host.CanCollide = false
				host.Transparency = 1
				host.Name = "TempSoundHost"

				local isLocalPlayer = (playerFired == player)
				if isLocalPlayer and character then
					local head = character:FindFirstChild("Head")
					if head then
						host.CFrame = head.CFrame + head.CFrame.LookVector * 2
						host.Anchored = false
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = head
						weld.Part1 = host
						weld.Parent = host
					else
						host.Anchored = true
						host.CFrame = workspace.CurrentCamera.CFrame
					end
				else
					host.Anchored = true
					host.CFrame = CFrame.new(originPos)
				end

				newFire.Parent = host
				host.Parent = workspace
				newFire:Play()
				debris:AddItem(host, newFire.TimeLength > 0 and newFire.TimeLength or 5)
			end

			autoFireTimers[parentKey] = task.delay(0.2, function()
				autoFireShotCount[parentKey] = nil
				autoFireTimers[parentKey] = nil
			end)

			return
		end

		if not activeAutoSounds[parentKey] then
			local autoFireSound = parent:FindFirstChild("AutoFire")
			if not autoFireSound or not autoFireSound:IsA("Sound") then
				return
			end

			local loopSound = autoFireSound:Clone()
			loopSound.Looped = true

			local host = Instance.new("Part")
			host.Size = Vector3.new(0.2, 0.2, 0.2)
			host.CanCollide = false
			host.Transparency = 1
			host.Name = "AutoFireHost"

			local isLocalPlayer = (playerFired == player)
			if isLocalPlayer and character then
				local head = character:FindFirstChild("Head")
				if head then
					host.CFrame = head.CFrame + head.CFrame.LookVector * 2
					host.Anchored = false
					local weld = Instance.new("WeldConstraint")
					weld.Part0 = head
					weld.Part1 = host
					weld.Parent = host
				else
					host.Anchored = true
					host.CFrame = workspace.CurrentCamera.CFrame
				end
			else
				host.Anchored = true
				host.CFrame = CFrame.new(originPos)
			end

			loopSound.Parent = host
			host.Parent = workspace
			loopSound:Play()

			activeAutoSounds[parentKey] = {
				sound = loopSound,
				lastFireTime = tick(),
				parent = parent,
				host = host,
				isSuppressed = isSuppressed
			}

			task.spawn(function()
				local stopDuration = (wepStats and wepStats.autoFireSoundDuration) or 0.2

				while activeAutoSounds[parentKey] do
					task.wait(0.02)
					local data = activeAutoSounds[parentKey]
					if data then
						if not data.sound.IsPlaying then
							data.sound:Play()
						end

						if tick() - data.lastFireTime >= stopDuration then
							data.sound:Stop()
							if data.host and data.host.Parent then
								data.host:Destroy()
							end

							local autoTail = data.parent:FindFirstChild("AutoTail")
							if autoTail and autoTail:IsA("Sound") then
								local tailClone = autoTail:Clone()
								local tailHost = Instance.new("Part")
								tailHost.Size = Vector3.new(0.2,0.2,0.2)
								tailHost.CanCollide = false
								tailHost.Transparency = 1
								tailHost.Anchored = true
								tailHost.CFrame = CFrame.new(originPos)
								tailClone.Parent = tailHost
								tailHost.Parent = workspace
								tailClone:Play()
								debris:AddItem(tailHost, tailClone.TimeLength > 0 and tailClone.TimeLength or 2)
							end

							activeAutoSounds[parentKey] = nil
							autoFireShotCount[parentKey] = nil

							if autoFireTimers[parentKey] then
								task.cancel(autoFireTimers[parentKey])
								autoFireTimers[parentKey] = nil
							end

							break
						end
					else
						break
					end
				end
			end)
		else
			activeAutoSounds[parentKey].lastFireTime = tick()
		end

		return
	end

	local soundParent = parent
	if isSuppressed then
		local gunModel = parent:FindFirstAncestorWhichIsA("Model")
		if gunModel then
			local activeMuzzle = attachmentManager.GetActiveMuzzle(gunModel)
			if activeMuzzle then
				soundParent = activeMuzzle
			end
		end
	end

	for _, child in ipairs(parent:GetChildren()) do
		if child:IsA("Sound") and child.Name == soundToPlay then
			if child.Looped then
				child:Play()
			else
				local newFire = child:Clone()
				newFire.PlaybackSpeed += math.random(-10, 10) / config.fireSoundVariation
				newFire.Name = child.Name .. "_Playing"

				local host = Instance.new("Part")
				host.Size = Vector3.new(0.2, 0.2, 0.2)
				host.CanCollide = false
				host.Transparency = 1
				host.Name = "TempSoundHost"

				local isLocalPlayer = (playerFired == player)
				if isLocalPlayer and character then
					local head = character:FindFirstChild("Head")
					if head then
						host.CFrame = head.CFrame + head.CFrame.LookVector * 2
						host.Anchored = false
						local weld = Instance.new("WeldConstraint")
						weld.Part0 = head
						weld.Part1 = host
						weld.Parent = host
					else
						host.Anchored = true
						host.CFrame = workspace.CurrentCamera.CFrame
					end
				else
					host.Anchored = true
					host.CFrame = CFrame.new(originPos)
				end

				newFire.Parent = host
				host.Parent = workspace
				newFire:Play()
				debris:AddItem(host, newFire.TimeLength > 0 and newFire.TimeLength or 5)
			end
			break
		end
	end
end

caster.LengthChanged:Connect(function(cast, segmentOrigin, segmentDirection, length, segmentVelocity, cosmeticBulletObject)
	if not cosmeticBulletObject then return end
	local userData = cast.UserData
	if not userData then return end

	SmokeVoxelMod.DisturbSegment(segmentOrigin, segmentDirection, length)

	if config.suppressionEffects and player ~= userData.Player and not userData.Cracked then
		local camPos = workspace.CurrentCamera.CFrame.Position
		local distToCamera = (camPos - cosmeticBulletObject.Position).Magnitude
		local distFromOrigin = (camPos - userData.Origin).Magnitude

		if distToCamera <= SUPPRESSION_DISTANCE and distFromOrigin >= SUPPRESSION_DISTANCE then
			if config.teamSuppression or not (player.Team and userData.Player.Team and player.Team == userData.Player.Team) then
				if suppression then
					suppression:Fire(userData.SuppressionLevel or 1)
				end
				userData.Cracked = true
			end
		end
	end

	if not userData.Visible then
		local wepStats
		if userData.TurretFired then
			local turretModule = require(userData.IgnoreModel.Parent.TurretModule)
			wepStats = turretModule.guns[userData.Tool]
		else
			if not userData.Tool or not userData.Tool:FindFirstChild("SPH_Weapon") then return end
			wepStats = require(userData.Tool.SPH_Weapon.WeaponStats)
		end

		local tracersEnabled = wepStats.tracers ~= false and not userData.IsUBGL
		local distanceCheck = (userData.Origin - cosmeticBulletObject.Position).Magnitude > TRACER_START_DISTANCE

		if tracersEnabled and distanceCheck and (config.arcadeBullets or userData.TracerColor) then
			userData.Visible = true

			cosmeticBulletObject.Transparency = 0
			cosmeticBulletObject.BeamLong.Enabled = true
			cosmeticBulletObject.BulletSmoke.Enabled = true
			cosmeticBulletObject.PointLight.Enabled = true
			cosmeticBulletObject.DistanceEffect.Enabled = true

			if userData.TracerColor then
				local newColor = userData.TracerColor
				cosmeticBulletObject.Color = newColor
				cosmeticBulletObject.BeamLong.Color = ColorSequence.new(newColor)
				cosmeticBulletObject.PointLight.Color = newColor
				cosmeticBulletObject.BulletSmoke.Enabled = false
				cosmeticBulletObject.DistanceEffect.Dot.ImageColor3 = newColor
				cosmeticBulletObject.DistanceEffect.Flare.ImageColor3 = newColor
			end
		end
	end

	local bulletLength = cosmeticBulletObject.Size.Z * 0.5
	cosmeticBulletObject.CFrame = CFrame.new(segmentOrigin, segmentOrigin + segmentDirection) * CFrame.new(0, 0, -(length - bulletLength))

	local fakeBullet = cosmeticBulletObject:FindFirstChild("FakeBullet")
	if fakeBullet then
		fakeBullet.CFrame = cosmeticBulletObject.CFrame * (userData.ProjectileOrientation or CFrame.identity)
	end

	if userData.SegmentOrigin ~= segmentOrigin then
		if userData.LastPosition then
			userData.Travelled += (userData.LastPosition - userData.SegmentOrigin).Magnitude
		end
		userData.SegmentOrigin = segmentOrigin
	end

	userData.LastPosition = segmentOrigin + segmentDirection.Unit * length

	if userData.MotionBlur then
		userData.MotionBlur.Update(userData.LastPosition)
	end
end)

caster.RayHit:Connect(function(cast, raycastResult, segmentVelocity, cosmeticBulletObject)
	local userData = cast.UserData
	if not userData then return end
	local tool = userData.Tool
	if not tool or not tool:FindFirstChild("SPH_Weapon") then return end

	local skipDamage = userData.LastHitWasNonDamaging
	userData.LastHitWasNonDamaging = false

	local travelDistance = userData.Travelled
		+ (raycastResult.Position - userData.SegmentOrigin).Magnitude

	if not userData.FakeBullet and not skipDamage then
		userData.HitCount += 1

		local bloodParams
		if not userData.IsUBGL then
			bloodParams = hitFX.HitEffect(raycastResult.Position, raycastResult.Instance, raycastResult.Normal, raycastResult.Material)
		end

		Network.packets.BulletHit.send({
			Tool = (not userData.TurretFired) and userData.Tool or nil,
			TurretModel = userData.TurretFired and userData.IgnoreModel or nil,
			TurretIndex = userData.TurretFired and userData.Tool or nil,
			RaycastPosition = raycastResult.Position,
			RaycastNormal = raycastResult.Normal,
			RaycastInstance = raycastResult.Instance,
			RaycastMaterial = MaterialCodec.Encode(raycastResult.Material),
			BulletCFrame = cosmeticBulletObject and cosmeticBulletObject.CFrame or CFrame.new(raycastResult.Position),
			BloodParams = bloodParams,
			IsUBGL = userData.IsUBGL,
			BulletId = userData.BulletId,
			HitIndex = userData.HitCount,
			TravelDistance = travelDistance,
		})

		if config.suppressionEffects and player ~= userData.Player and not userData.Cracked then
			if suppression then
				suppression:Fire(userData.SuppressionLevel or 1)
			end
			userData.Cracked = true
		end
	end

	if userData.PendingVelocity then
		cast:SetVelocity(userData.PendingVelocity)
		userData.PendingVelocity = nil
	end

	local ricochet = userData.PendingRicochet
	if ricochet then
		userData.PendingRicochet = nil
		module.FireBullet(
			userData.IgnoreModel,
			ricochet.Position,
			ricochet.Velocity.Magnitude > 0 and ricochet.Velocity.Unit or Vector3.new(0, 0, -1),
			ricochet.Velocity,
			tool,
			userData.Player,
			userData.TracerColor,
			userData.FakeBullet,
			userData.TurretFired,
			userData.IsUBGL,
			ricochet.PiercedParts,
			travelDistance
		)
	end
end)

caster.CastTerminating:Connect(function(cast)
	local userData = cast.UserData
	if userData then
		userData.Terminated = true

		if userData.MotionBlurDelayThread then
			task.cancel(userData.MotionBlurDelayThread)
			userData.MotionBlurDelayThread = nil
		end

		if userData.MotionBlur then
			userData.MotionBlur.Remove()
			userData.MotionBlur = nil
		end
	end

	local bullet = cast.RayInfo.CosmeticBulletObject
	if not bullet or not bullet.Parent then return end
	if userData and userData.Visible then
		ResetBullet(bullet)
	end
	pcall(function()
		bulletProvider:ReturnPart(bullet)
	end)
end)

module.FireBullet = function(rig, bulletOrigin, bulletDirection, bulletVelocity, tool, playerFired, tracerColor, fake, turret, isUBGL, carriedPierced, carriedDistance)
	local wepStats
	if turret then
		local turretModule = require(rig.Parent.TurretModule)
		wepStats = turretModule.guns[tool]
	else
		wepStats = require(tool.SPH_Weapon.WeaponStats)
	end

	local dropEnabled = ResolveDropEnabled(wepStats, isUBGL)

	nextBulletId += 1
	local projectileOrientation = ResolveProjectileOrientation(wepStats, isUBGL)
	local userData = {
		Player = playerFired,
		TracerColor = tracerColor,
		Tool = tool,
		IgnoreModel = rig,
		FakeBullet = fake,
		Visible = false,
		Origin = bulletOrigin,
		SuppressionLevel = wepStats.suppressionLevel or 1,
		TurretFired = turret,
		IsUBGL = isUBGL,
		BulletId = nextBulletId,
		HitCount = 0,
		PiercedParts = carriedPierced or {},
		ProjectileOrientation = projectileOrientation,
		Travelled = carriedDistance or 0,
		SegmentOrigin = bulletOrigin,
	}

	if wepStats.motionBlur and not isUBGL then
		local mbColor = wepStats.motionBlurColor or tracerColor
		local motionBlurConfig = {
			size = wepStats.motionBlurSize or 0.05,
			bloom = wepStats.motionBlurBloom or 0,
			brightness = wepStats.motionBlurBrightness or 1,
			color = mbColor,
		}

		local delayEnabled = wepStats.motionBlurDelayEnabled
		local delayTime = wepStats.motionBlurDelay or 0

		if delayEnabled and delayTime > 0 then
			userData.MotionBlurDelayThread = task.delay(delayTime, function()
				if userData.Terminated then return end
				userData.MotionBlur = visualisationManager.new(motionBlurConfig, userData.LastPosition or bulletOrigin)
				userData.MotionBlurDelayThread = nil
			end)
		else
			userData.MotionBlur = visualisationManager.new(motionBlurConfig, bulletOrigin)
		end
	end

	if wepStats.serverOffset and not isUBGL and not turret and rig then
		local baseWeld = rig:FindFirstChild("BaseWeld")
		if baseWeld and baseWeld:IsA("JointInstance") then
			baseWeld.C0 = wepStats.serverOffset * CFrame.new(0, 0, 0.17) * CFrame.Angles(0.0349, math.random(-10, 10) / 100, 0)
			tweenService:Create(baseWeld, TweenInfo.new(0.3, Enum.EasingStyle.Back), {C0 = wepStats.serverOffset}):Play()
		end
	end

	local shotBehavior = CloneShotBehavior(userData.PiercedParts)
	local acceleration = dropEnabled and config.bulletAcceleration or VECTOR3_ZERO
	shotBehavior.Acceleration = acceleration

	local activeCast = caster:Fire(bulletOrigin, bulletDirection, bulletVelocity, shotBehavior)
	if not activeCast then
		return
	end
	activeCast:SetAcceleration(acceleration)
	activeCast.UserData = userData

	local bullet = activeCast.RayInfo.CosmeticBulletObject
	if bullet and bullet.Transparency == 0 then
		ResetBullet(bullet)
	end

	if not tracerColor then
		local projectileName = (isUBGL and wepStats.UBGL and wepStats.UBGL.Projectile) or wepStats.projectile
		local projectileModel = resolveProjectileTemplate(projectileName)
		if projectileModel then
			local fakeBullet = projectileModel:Clone()
			fakeBullet.Name = "FakeBullet"
			FreezeProjectilePhysics(fakeBullet)
			if bullet then
				fakeBullet.Parent = bullet
				fakeBullet.CFrame = bullet.CFrame * userData.ProjectileOrientation
			end
			userData.Visible = true
		end
	end

	return activeCast
end

local function HandleBackblast(gunModel)
	local base = gunModel:FindFirstChild("Grip") or gunModel:FindFirstChild("Base")
	if not base then return end

	local backblast = base:FindFirstChild("Backblast")
	if not backblast then return end

	for _, fx in ipairs(backblast:GetChildren()) do
		if fx:IsA("ParticleEmitter") then
			fx.Enabled = true
		end
	end

	task.delay(0.1, function()
		for _, fx in ipairs(backblast:GetChildren()) do
			if fx:IsA("ParticleEmitter") then
				fx.Enabled = false
			end
		end
	end)
end

module.FireFX = function(playerFired, gunModel, firePointName, muzzleChance, soundDelay, isAutoFire, isSuppressed, soundNameOverride)
	local activeMuzzle
	if firePointName == "Muzzle" then
		activeMuzzle = attachmentManager.GetActiveMuzzle(gunModel)

		if activeMuzzle then
			local muzzleConfig = attachmentManager.GetMuzzleAttachmentConfig(gunModel)
			if muzzleConfig then
			end
		end
	end

	if not activeMuzzle then
		local base = gunModel:FindFirstChild("Grip") or gunModel:FindFirstChild("Base")
		activeMuzzle = base and base:FindFirstChild(firePointName)
	end

	if not activeMuzzle then
		return
	end

	local firePoint = activeMuzzle

	HandleBackblast(gunModel)

	local base = gunModel:FindFirstChild("Grip") or gunModel:FindFirstChild("Base")

	local playerRootPart = playerFired.Character:FindFirstChild("HumanoidRootPart")
	if playerRootPart and (workspace.CurrentCamera.CFrame.Position - playerRootPart.Position).Magnitude <= FIRE_EFFECT_DISTANCE then
		local showMuzzle = math.random(10) <= muzzleChance

		for _, fx in ipairs(firePoint:GetChildren()) do
			if fx:IsA("ParticleEmitter") then
				local isFlash = fx.Name:find("Flash") ~= nil
				local isSmoke = fx.Name == "Smoke"

				if isSuppressed and isFlash then
					continue
				end

				local canEmit = not isFlash or showMuzzle

				if canEmit then
					local emitCount = fx:GetAttribute("EmitNumber")
					if emitCount then
						fx:Emit(emitCount)
					elseif fx:FindFirstChild("Particles") then
						fx:Emit(fx.Particles.Value)
					elseif isSmoke then
						fx:Emit(10)
					elseif isFlash then
						fx:Emit(5)
					end
				end
			elseif fx:IsA("Light") and showMuzzle then
				if not isSuppressed then
					fx.Enabled = true
					task.delay(0.01, function() fx.Enabled = false end)
				end
			end
		end
	end

	if soundDelay then
		task.wait(soundDelay)
	end

	local tool = playerFired.Character:FindFirstChildWhichIsA("Tool")
	local wepStats
	if tool and tool:FindFirstChild("SPH_Weapon") then
		wepStats = require(tool.SPH_Weapon.WeaponStats)
	end

	PlaySFX(base, playerFired, isAutoFire, wepStats, isSuppressed, soundNameOverride)
end

module.MoveBolt = function(gunModel, wepStats, direction, magAmmo, instant)
	if not gunModel then return end
	local grip = gunModel:FindFirstChild("Grip")
	if not grip then return end

	local distance = typeof(direction) == "CFrame" and direction or CFrame.new(0, 0, -direction)

	if instant then
		for _, name in ipairs(wepStats.fireMoveParts) do
			local m6d = grip:FindFirstChild(name)
			if m6d then
				m6d.C1 = distance
			end
		end
		return
	end

	local shouldReturn = magAmmo <= 0 and wepStats.emptyLockBolt
	local tInfo = TweenInfo.new(
		60 / wepStats.fireRate / 2,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.In,
		0,
		not shouldReturn
	)

	for _, name in ipairs(wepStats.fireMoveParts) do
		local m6d = grip:FindFirstChild(name)
		if m6d then
			m6d.C1 = CFrame.new()
			tweenService:Create(m6d, tInfo, {C1 = distance}):Play()
		end
	end
end

module.StopAutoSound = function(playerFired, gunModel)
	if not gunModel then return end
	local base = gunModel:FindFirstChild("Grip") or gunModel:FindFirstChild("Base")
	if not base then return end

	local parentKey = tostring(playerFired.UserId)

	if autoFireTimers[parentKey] then
		task.cancel(autoFireTimers[parentKey])
		autoFireTimers[parentKey] = nil
	end
	autoFireShotCount[parentKey] = nil

	local data = activeAutoSounds[parentKey]
	if not data then return end

	activeAutoSounds[parentKey] = nil

	data.sound:Stop()
	if data.host and data.host.Parent then
		data.host:Destroy()
	end

	local tailName = data.isSuppressed and "SilencedAutoTail" or "AutoTail"
	local autoTail = data.parent:FindFirstChild(tailName)
	if autoTail and autoTail:IsA("Sound") then
		local originPos
		if data.parent:IsA("BasePart") then
			originPos = data.parent.Position
		elseif data.parent:IsA("Attachment") then
			originPos = data.parent.WorldPosition
		else
			originPos = Vector3.zero
		end

		local tailClone = autoTail:Clone()
		local tailHost = Instance.new("Part")
		tailHost.Size = Vector3.new(0.2, 0.2, 0.2)
		tailHost.CanCollide = false
		tailHost.Transparency = 1
		tailHost.Anchored = true
		tailHost.CFrame = CFrame.new(originPos)
		tailClone.Parent = tailHost
		tailHost.Parent = workspace
		tailClone:Play()
		debris:AddItem(tailHost, tailClone.TimeLength > 0 and tailClone.TimeLength or 2)
	end
end

return module