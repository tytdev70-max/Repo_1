local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local config = require(ReplicatedStorage.SPH_Assets.GameConfig)

local EXPLOSION_REMOTE_NAME = "ExplosionFXRemote"
local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local events = assets:WaitForChild("Events")
local explosionEvents = events:WaitForChild("ExplosionEvents")
local explosionRemote = explosionEvents:FindFirstChild(EXPLOSION_REMOTE_NAME) :: RemoteEvent

if not explosionRemote then
	local re = Instance.new("RemoteEvent")
	re.Name = EXPLOSION_REMOTE_NAME
	re.Parent = explosionEvents
	explosionRemote = re
end

local GlassShatterMod = require(assets.Modules.Effects.Environment.GlassShatterMod)

local objectDestructionModule
local function getObjectDestruction()
	if not objectDestructionModule then
		objectDestructionModule = require(assets.Modules.Effects.Environment.ObjectDestruction)
	end
	return objectDestructionModule
end

local DebugViz = require(assets.Modules.Effects.Explosions.ExplosionDebugViz)

local explosionOverlapParams = OverlapParams.new()
explosionOverlapParams.MaxParts = 500
explosionOverlapParams.RespectCanCollide = false

local ringingEarSounds = {9069161602}

local explosionSound = {
	ids = {101767123218902, 166047750, 126212934401370},
	volume = 10
}

local explosionEchoFar = {
	ids = {111942421000268, 85043931123332, 80052929458664, 122570561415463, 120612597459070},
	volume = 2
}

local flashbangSound = {
	ids = {108148425472172},
	volume = 1
}

local function getRandomSoundId(soundTable)
	if #soundTable.ids > 0 then
		return soundTable.ids[math.random(#soundTable.ids)]
	end
	return soundTable.ids[1] or 0
end

local function getSoundForDistance(isEcho)
	return isEcho and explosionEchoFar or explosionSound
end

local function sendSoundToPlayer(player, explosionData)
	if player and player.Parent and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
		pcall(function()
			explosionRemote:FireClient(player, explosionData)
		end)
	end
end

local function hasLineOfSightToPoints(origin, points, extraExclusions, debugRecorder)
	local exclusions = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			exclusions[#exclusions + 1] = pl.Character
		end
	end
	local sphWorkspace = workspace:FindFirstChild("SPH_Workspace")
	if sphWorkspace then
		exclusions[#exclusions + 1] = sphWorkspace
	end
	if extraExclusions then
		for _, inst in ipairs(extraExclusions) do
			exclusions[#exclusions + 1] = inst
		end
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.RespectCanCollide = false

	local LAG_COMPENSATION = 1.0
	local rayOrigin = origin + Vector3.new(0, 0.5, 0)

	for _, point in ipairs(points) do
		local direction = point - rayOrigin
		local distance  = direction.Magnitude
		if distance < 0.1 then
			if debugRecorder then debugRecorder(rayOrigin, point, true, nil) end
			return true
		end
		local result = workspace:Raycast(rayOrigin, direction, params)
		local clear = not result or result.Distance >= distance - LAG_COMPENSATION
		if debugRecorder then debugRecorder(rayOrigin, point, clear, result and result.Instance) end
		if clear then
			return true
		end
	end

	return false
end

local function hasLineOfSight(origin, targetCharacter, debugRecorder)
	local hrp = targetCharacter:FindFirstChild("HumanoidRootPart")
	if not hrp then return false end

	local checkPoints = {
		hrp.Position,
		hrp.Position + Vector3.new(0,  1.5, 0),
		hrp.Position + Vector3.new(0, -1.0, 0),
		hrp.Position + Vector3.new( 0.6, 0.5, 0),
		hrp.Position + Vector3.new(-0.6, 0.5, 0),
		hrp.Position + Vector3.new(0, 0.5,  0.5),
		hrp.Position + Vector3.new(0, 0.5, -0.5),
	}

	return hasLineOfSightToPoints(origin, checkPoints, nil, debugRecorder)
end

local function GetFlashIntensity(dist, flashRadius, coreFraction, falloffExponent)
	if not flashRadius or flashRadius <= 0 then return 0 end
	coreFraction = math.clamp(tonumber(coreFraction) or 0, 0, 0.95)
	local coreDist = flashRadius * coreFraction
	if dist <= coreDist then
		return 1
	end
	local falloffRange = math.max(flashRadius - coreDist, 0.01)
	local t = math.clamp(1 - ((dist - coreDist) / falloffRange), 0, 1)
	return t ^ math.max(tonumber(falloffExponent) or 1, 0.01)
end

local function GetFalloffMultiplier(dist, radius, exponent)
	if radius <= 0 then return 0 end
	local t = math.clamp(1 - (dist / radius), 0, 1)
	return t ^ (exponent or 1)
end

local function getObjectSamplePoints(hitObject)
	local center, size
	if hitObject:IsA("Model") then
		if hitObject.PrimaryPart then
			center = hitObject.PrimaryPart.Position
		else
			center = hitObject:GetBoundingBox().Position
		end
		local ok, extents = pcall(function() return hitObject:GetExtentsSize() end)
		size = ok and extents or Vector3.new(2, 2, 2)
	else
		center = hitObject.Position
		size = hitObject.Size
	end

	local points = { center }
	if size.Y > 4 then
		points[#points + 1] = center + Vector3.new(0, size.Y * 0.35, 0)
	end
	return points
end

local function Explode(explosionOrigin: Vector3, blastRadius: number, explosionType: string, playerResponsible: Player, flashbangConfig, options)
	local opts = options
	if typeof(opts) ~= "table" then
		opts = { skipVisualFX = opts == true }
	end
	local skipVisualFX = opts.skipVisualFX == true
	local skipExplosionSound = opts.skipExplosionSound == true
	local skipCameraShake = opts.skipCameraShake == true
	local isSmoke = opts.isSmoke == true

	local effectsFolder = script:FindFirstChild(explosionType)
	local removeTime = 10
	local explosion = Instance.new("Attachment", workspace.Terrain)
	explosion.WorldPosition = explosionOrigin

	local debugEnabled = config.explosionDebug == true
	local debugRayRecorder = nil
	if debugEnabled then
		debugRayRecorder = function(rayOrigin, rayTarget, wasClear, _blockingInstance)
			DebugViz.DrawRay(rayOrigin, rayTarget, wasClear and DebugViz.Colors.Hit or DebugViz.Colors.Blocked)
		end
	end

	if not skipVisualFX then
		if effectsFolder then
			local effects = effectsFolder:GetChildren()
			local lightsFound = {}

			for _, effect in ipairs(effects) do
				local newEffect = effect:Clone()
				newEffect.Parent = explosion

				if newEffect:IsA("ParticleEmitter") then
					newEffect:Emit(newEffect:FindFirstChild("Count") and newEffect.Count.Value or 1)
					if newEffect.Lifetime.Max > removeTime then
						removeTime = newEffect.Lifetime.Max
					end
				elseif newEffect:IsA("Light") then
					newEffect.Enabled = true
					table.insert(lightsFound, newEffect)
				end
			end

			if #lightsFound > 0 then
				task.delay(0.1, function()
					for _, light in ipairs(lightsFound) do
						if light and light.Parent then
							light.Enabled = false
						end
					end
				end)
			end
		else
			warn("[ExplosionFX] No FX folder named '" .. tostring(explosionType) .. "' found under ExplosionFX module - exploding without visual effects.")
		end
	end

	local humanoidsHit = {}

	local function tryDamageCharacter(characterModel, playerHit)
		local humanoid = characterModel:FindFirstChildWhichIsA("Humanoid")
		local hrp = characterModel:FindFirstChild("HumanoidRootPart")
		if not humanoid or not hrp or humanoid.Health <= 0 then return end
		if table.find(humanoidsHit, humanoid) then return end

		if playerHit and playerResponsible and playerHit ~= playerResponsible then
			if not playerHit.Neutral and not playerResponsible.Neutral
				and playerHit.Team == playerResponsible.Team
				and not config.teamKill then
				return
			end
		end

		local dist = (explosionOrigin - hrp.Position).Magnitude

		local NETWORK_LAG_BUFFER = 2
		if dist > blastRadius * 2 + NETWORK_LAG_BUFFER then return end

		local los = true
		if config.explosionRaycast then
			los = hasLineOfSight(explosionOrigin, characterModel, debugRayRecorder)
		end
		if not los then return end

		table.insert(humanoidsHit, humanoid)
		dist = math.max(dist, 0.01)
		local falloffRadius = blastRadius * 1.5
		local damage = GetFalloffMultiplier(dist, falloffRadius, config.explosionFalloffExponent) * (blastRadius / 1.5 * 100)

		local healthBefore = humanoid.Health
		if healthBefore > 0 and healthBefore - damage <= 0 then
			local existingKiller = characterModel:FindFirstChild("Killer")
			if not existingKiller and playerResponsible then
				local killerTag = Instance.new("ObjectValue")
				killerTag.Name = "Killer"
				killerTag.Value = playerResponsible
				killerTag.Parent = characterModel
			end
		end

		pcall(function() humanoid:TakeDamage(damage) end)

		if debugEnabled then
			DebugViz.MarkTarget(hrp.Position, DebugViz.Colors.ValidTarget)
		end
	end

	local function tryDamageDestructible(hitObject)
		if hitObject:GetAttribute("Destroyed") then return end

		local objectPosition
		if hitObject:IsA("Model") then
			if hitObject.PrimaryPart then
				objectPosition = hitObject.PrimaryPart.Position
			else
				objectPosition = hitObject:GetBoundingBox().Position
			end
		else
			objectPosition = hitObject.Position
		end

		local effectiveRadius = blastRadius * 1.5
		local dist = (explosionOrigin - objectPosition).Magnitude
		if dist > effectiveRadius then return end

		local ignoreLOS = hitObject:GetAttribute("SPH_IgnoreExplosionLOS") == true
		local checkLOS = config.explosionRaycast and (config.explosionRaycastDestructibles ~= false) and not ignoreLOS

		local los = true
		if checkLOS then
			los = hasLineOfSightToPoints(explosionOrigin, getObjectSamplePoints(hitObject), {hitObject}, debugRayRecorder)
		end
		if not los then return end

		local destructionType = hitObject:GetAttribute("DestructionType")

		if destructionType == "Instant" then
			if debugEnabled then
				DebugViz.MarkTarget(objectPosition, DebugViz.Colors.ValidTarget)
			end
			getObjectDestruction().DestroyObject(hitObject, playerResponsible)
			return
		end

		local currentHP = hitObject:GetAttribute("HP")
		if type(currentHP) ~= "number" then return end

		dist = math.max(dist, 0.01)
		local falloff = GetFalloffMultiplier(dist, effectiveRadius, config.explosionFalloffExponent)
		local damage = falloff * (blastRadius / 1.5 * 100) * (config.explosionDestructibleDamageMultiplier or 1)
		if damage <= 0 then return end

		hitObject:SetAttribute("HP", currentHP - damage)

		if debugEnabled then
			DebugViz.MarkTarget(objectPosition, DebugViz.Colors.ValidTarget)
		end

		if currentHP - damage <= 0 then
			getObjectDestruction().DestroyObject(hitObject, playerResponsible)
		end
	end

	local function tryShatterGlass(glassPart)
		local effectiveRadius = blastRadius * 1.5
		local dist = (explosionOrigin - glassPart.Position).Magnitude
		if dist > effectiveRadius then return end

		local los = true
		if config.explosionRaycast then
			los = hasLineOfSightToPoints(explosionOrigin, {glassPart.Position}, {glassPart}, debugRayRecorder)
		end
		if not los then return end

		local pushDirection = glassPart.Position - explosionOrigin
		if GlassShatterMod.Shatter(glassPart, glassPart.Position, pushDirection) and debugEnabled then
			DebugViz.MarkTarget(glassPart.Position, DebugViz.Colors.ValidTarget)
		end
	end

	local playerCharacters = {}
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			playerCharacters[pl.Character] = true
			tryDamageCharacter(pl.Character, pl)
		end
	end

	local partsInRange = workspace:GetPartBoundsInRadius(explosionOrigin, blastRadius * 2, explosionOverlapParams)
	local seenModels = {}
	local seenDestructibles = {}
	local seenGlass = {}

	for _, hitPart in ipairs(partsInRange) do
		local model = hitPart:FindFirstAncestorWhichIsA("Model")
		if model and not seenModels[model] and not playerCharacters[model] then
			seenModels[model] = true
			if model:FindFirstChildWhichIsA("Humanoid") then
				tryDamageCharacter(model, nil)
			end
		end

		if GlassShatterMod.IsGlass(hitPart) and not seenGlass[hitPart] then
			seenGlass[hitPart] = true
			tryShatterGlass(hitPart)
		end

		local destructibleObject
		if hitPart.Parent and CollectionService:HasTag(hitPart.Parent, "SPH_Destructible") then
			destructibleObject = hitPart.Parent
		elseif CollectionService:HasTag(hitPart, "SPH_Destructible") then
			destructibleObject = hitPart
		end

		if destructibleObject and not seenDestructibles[destructibleObject] then
			seenDestructibles[destructibleObject] = true
			tryDamageDestructible(destructibleObject)
		end
	end

	for _, destructibleInstance in ipairs(CollectionService:GetTagged("SPH_Destructible")) do
		if not seenDestructibles[destructibleInstance] then
			seenDestructibles[destructibleInstance] = true
			tryDamageDestructible(destructibleInstance)
		end
	end

	for _, hitPart in ipairs(partsInRange) do
		if not hitPart.Anchored then
			local isPartOfTool      = hitPart:FindFirstAncestorOfClass("Tool") ~= nil
			local ancestorModel     = hitPart:FindFirstAncestorWhichIsA("Model")
			local isPartOfCharacter = ancestorModel and ancestorModel:FindFirstChild("Humanoid") ~= nil
			local isAccessory       = hitPart:FindFirstAncestorWhichIsA("Accessory") ~= nil

			if not isPartOfTool and not isPartOfCharacter and not isAccessory then
				local dist = (hitPart.Position - explosionOrigin).Magnitude
				if dist <= blastRadius * 1.5 then
					local tempAtt = Instance.new("Attachment")
					tempAtt.Name = "ExplosionForceAttachment"
					tempAtt.Parent = hitPart

					local force = Instance.new("VectorForce")
					force.Name = "ExplosionVectorForce"
					force.Attachment0 = tempAtt
					local forceDirection = (hitPart.Position - explosionOrigin).Unit
					local forceMagnitude = math.clamp(10000 / math.max(dist, 1), 1000, 10000)
					force.Force = forceDirection * forceMagnitude
					force.RelativeTo = Enum.ActuatorRelativeTo.World
					force.Parent = hitPart

					Debris:AddItem(tempAtt, 0.1)
					Debris:AddItem(force, 0.1)
				end
			end
		end
	end

	local maxAudibleDistance = 2000
	local echoDistanceTrigger = config.echoGrenadeTrigger or 300
	local isFlashbangType = flashbangConfig ~= nil and flashbangConfig.flashRadius ~= nil and flashbangConfig.flashRadius > 0

	for _, pl in ipairs(Players:GetPlayers()) do
		local ch = pl.Character
		if ch and ch:FindFirstChild("HumanoidRootPart") then
			local hrpPos = ch.HumanoidRootPart.Position
			local dist = (hrpPos - explosionOrigin).Magnitude

			if dist <= maxAudibleDistance then
				local explosionData = {
					blastRadius = blastRadius,
					origin = explosionOrigin,
					distance = dist,
					explosionType = explosionType,
					isSmoke = isSmoke,
					skipCameraShake = skipCameraShake,
					SmokeDisturbOrigin = explosionOrigin,
					SmokeDisturbRadius = blastRadius,
				}

				if not skipExplosionSound then
					local shouldPlayEcho = dist >= echoDistanceTrigger
					local ringId = ringingEarSounds[math.random(#ringingEarSounds)]

					local isInFlashRange = isFlashbangType and dist <= flashbangConfig.flashRadius

					if isInFlashRange and config.explosionRaycast then
						isInFlashRange = hasLineOfSight(explosionOrigin, ch, debugRayRecorder)
					end

					local flashIntensity = 0
					if isInFlashRange then
						flashIntensity = GetFlashIntensity(dist, flashbangConfig.flashRadius, flashbangConfig.flashCoreFraction, flashbangConfig.flashFalloffExponent)
					end

					local audioIntensity
					if isInFlashRange then
						audioIntensity = flashIntensity
					elseif isFlashbangType then
						audioIntensity = 0
					elseif blastRadius > 0 then
						audioIntensity = math.clamp((blastRadius * 2 - dist) / (blastRadius * 2), 0, 1)
					else
						audioIntensity = 0
					end

					local soundTableForPlayer = flashbangConfig and flashbangSound or getSoundForDistance(shouldPlayEcho)
					local selectedSoundId = getRandomSoundId(soundTableForPlayer)
					local volumeMultiplier = math.clamp(1 - (dist / maxAudibleDistance), 0.1, 1)
					local adjustedVolume = soundTableForPlayer.volume * volumeMultiplier

					explosionData.ringId = ringId
					explosionData.audioIntensity = audioIntensity
					explosionData.explosionSoundId = selectedSoundId
					explosionData.explosionSoundVolume = adjustedVolume
					explosionData.isEcho = shouldPlayEcho
					explosionData.isFlashbang = isFlashbangType

					if isInFlashRange then
						local minDur = flashbangConfig.flashMinDuration or 0.5
						local maxDur = flashbangConfig.flashMaxDuration or 3

						explosionData.isFlashbang = true
						explosionData.flashIntensity = flashIntensity
						explosionData.flashDuration = minDur + (maxDur - minDur) * flashIntensity
						explosionData.flashFacingFalloff = flashbangConfig.flashFacingFalloff or 1

						explosionData.flashWhiteFlashEnabled     = flashbangConfig.flashWhiteFlashEnabled
						explosionData.flashWhiteFlashTime        = flashbangConfig.flashWhiteFlashTime
						explosionData.flashWhiteFlashMaxDistance = flashbangConfig.flashWhiteFlashMaxDistance

						explosionData.flashBlackoutEnabled     = flashbangConfig.flashBlackoutEnabled
						explosionData.flashBlackoutFadeInTime  = flashbangConfig.flashBlackoutFadeInTime
						explosionData.flashBlackoutMaxDistance = flashbangConfig.flashBlackoutMaxDistance

						explosionData.flashGlareEnabled          = flashbangConfig.flashGlareEnabled
						explosionData.flashGlares                = flashbangConfig.flashGlares
						explosionData.flashGlareBackFacingCutoff = flashbangConfig.flashGlareBackFacingCutoff

						explosionData.flashDesaturateEnabled       = flashbangConfig.flashDesaturateEnabled
						explosionData.flashDesaturateMaxDistance   = flashbangConfig.flashDesaturateMaxDistance
						explosionData.flashDesaturateCurveExponent = flashbangConfig.flashDesaturateCurveExponent
						explosionData.flashDesaturateMaxContrast   = flashbangConfig.flashDesaturateMaxContrast
						explosionData.flashDesaturateMaxBrightness = flashbangConfig.flashDesaturateMaxBrightness

						explosionData.flashBlurEnabled           = flashbangConfig.flashBlurEnabled
						explosionData.flashBlurMaxSize           = flashbangConfig.flashBlurMaxSize
						explosionData.flashBlurMaxDistance       = flashbangConfig.flashBlurMaxDistance
						explosionData.flashBlurFadeInTime        = flashbangConfig.flashBlurFadeInTime
						explosionData.flashBlurFadeOutMultiplier = flashbangConfig.flashBlurFadeOutMultiplier

						explosionData.flashMuffleEnabled = flashbangConfig.flashMuffleEnabled
					end
				end

				sendSoundToPlayer(pl, explosionData)
			end
		end
	end

	if debugEnabled then
		DebugViz.DrawRadius(explosionOrigin, blastRadius * 1.5, DebugViz.Colors.EffectiveRadius)
		DebugViz.DrawRadius(explosionOrigin, blastRadius * 2, DebugViz.Colors.QueryRadius)
	end

	Debris:AddItem(explosion, removeTime)
end

return Explode