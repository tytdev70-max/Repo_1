local MagEjection = {}

local TweenService   = game:GetService("TweenService")
local Debris         = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")
local Players        = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local EJECTION_SPEED_MIN     = 2
local EJECTION_SPEED_MAX     = 5
local IMPACT_COOLDOWN        = 0.15
local MIN_IMPACT_VELOCITY    = 3.5
local FADE_DELAY             = 4
local FADE_TIME              = 1.5
local TOTAL_LIFETIME         = 6
local FADE_TWEEN_INFO        = TweenInfo.new(FADE_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
local PHYSICAL_PROPERTIES    = PhysicalProperties.new(0.7, 0.4, 0.3)

-- Cached asset path
local function getMagSoundsFolder(folderName)
	local ejectionRoot = ReplicatedStorage
		:FindFirstChild("SPH_Assets")
		and ReplicatedStorage.SPH_Assets.Modules
		and ReplicatedStorage.SPH_Assets.Modules.Weapons
		and ReplicatedStorage.SPH_Assets.Modules.Weapons.Fire
		and ReplicatedStorage.SPH_Assets.Modules.Weapons.Fire.MagEjection
	return ejectionRoot and ejectionRoot:FindFirstChild(folderName or "MagSounds")
end

-- ─── Collision Groups ────────────────────────────────────────────────────────

local collisionGroupSetup = false
local function setupCollisionGroups()
	if collisionGroupSetup then return end
	collisionGroupSetup = true

	for _, name in { "Debris", "Players" } do
		if not PhysicsService:IsCollisionGroupRegistered(name) then
			PhysicsService:RegisterCollisionGroup(name)
		end
	end

	PhysicsService:CollisionGroupSetCollidable("Debris", "Players", false)
	PhysicsService:CollisionGroupSetCollidable("Debris", "Default", true)
end

local function setPartGroup(part, group)
	if part:IsA("BasePart") then
		part.CollisionGroup = group
	end
end

local function setCharacterCollisionGroup(character)
	if not character or not character.Parent then return end

	local function applyToAll()
		for _, desc in character:GetDescendants() do
			setPartGroup(desc, "Players")
		end
	end

	applyToAll()

	local conns = {}
	conns[1] = character.DescendantAdded:Connect(function(desc)
		setPartGroup(desc, "Players")
	end)

	local function cleanup()
		for _, c in conns do c:Disconnect() end
	end

	conns[2] = character.AncestryChanged:Connect(function()
		if not character.Parent then cleanup() end
	end)

	task.delay(1, function()
		if character.Parent then
			applyToAll()
		else
			cleanup()
		end
	end)
end

-- ─── Magazine Finding ────────────────────────────────────────────────────────

local VALID_MAG_NAMES = { "" }

local function findMagazineInModel(model, wepStats)
	if not model then return nil end

	local namesToSearch = VALID_MAG_NAMES

	if wepStats and wepStats.MagDropName then
		local raw = wepStats.MagDropName
		namesToSearch = type(raw) == "table" and raw or { raw }
	end

	for _, name in namesToSearch do
		local mag = model:FindFirstChild(name, true)
		if mag and (mag:IsA("BasePart") or mag:IsA("Model")) then
			return mag
		end
	end
end

-- ─── Clone Helper ────────────────────────────────────────────────────────────

local function cloneMag(mag)
	local clone = mag:Clone()
	if clone:IsA("Model") and not clone.PrimaryPart then
		clone.PrimaryPart = clone:FindFirstChildWhichIsA("BasePart")
	end
	return clone
end

-- ─── Physics & Lifecycle ─────────────────────────────────────────────────────

local function setupMagPhysics(magClone, ejectionCFrame, player, magSoundsFolder)
	local allParts = {}

	local function preparePart(part)
		part.Anchored               = false
		part.CanCollide             = false
		part.CollisionGroup         = "Debris"
		part.CanTouch               = true
		part.CanQuery               = true
		part.CastShadow             = false
		part.CustomPhysicalProperties = PHYSICAL_PROPERTIES
		allParts[#allParts + 1]     = part
	end

	if magClone:IsA("Model") then
		for _, desc in magClone:GetDescendants() do
			if desc:IsA("BasePart") then preparePart(desc) end
		end

		local primary = magClone.PrimaryPart
		if primary then
			for _, part in allParts do
				if part ~= primary then
					local weld   = Instance.new("WeldConstraint")
					weld.Part0   = primary
					weld.Part1   = part
					weld.Parent  = primary
				end
			end
			magClone:SetPrimaryPartCFrame(ejectionCFrame)
		end
	else
		preparePart(magClone)
		magClone.CFrame = ejectionCFrame
	end

	local mainPart = if magClone:IsA("Model") then magClone.PrimaryPart else magClone

	-- Velocity
	local dir = (ejectionCFrame.RightVector * -1.2)
		+ (ejectionCFrame.UpVector * -0.3)
		+ (ejectionCFrame.LookVector * 0.2)

	local speed = EJECTION_SPEED_MIN + math.random() * (EJECTION_SPEED_MAX - EJECTION_SPEED_MIN)

	pcall(function() mainPart:SetNetworkOwner(player) end)

	mainPart.AssemblyLinearVelocity  = dir.Unit * speed
	mainPart.AssemblyAngularVelocity = Vector3.new(
		math.random(-15, 15),
		math.random(-8,   8),
		math.random(-15, 15)
	)

	-- Enable collision after brief settle delay
	task.delay(0.15, function()
		if not magClone.Parent then return end
		for _, part in allParts do
			if part.Parent then part.CanCollide = true end
		end
	end)

	-- One-shot impact sound
	if magSoundsFolder then
		local validSounds = {}
		for _, s in magSoundsFolder:GetChildren() do
			if s:IsA("Sound") then validSounds[#validSounds + 1] = s end
		end

		if #validSounds > 0 then
			local lastImpact = 0
			local touchConn
			touchConn = mainPart.Touched:Connect(function(hit)
				if not hit or not hit:IsA("BasePart") or not hit.Parent then return end
				if player.Character and hit:IsDescendantOf(player.Character) then return end
				if hit.CollisionGroup == "Debris" then return end

				local now = tick()
				if now - lastImpact < IMPACT_COOLDOWN then return end

				local vel = mainPart.AssemblyLinearVelocity.Magnitude
				if vel < MIN_IMPACT_VELOCITY then return end

				lastImpact = now
				touchConn:Disconnect()

				local snd = validSounds[math.random(#validSounds)]:Clone()
				snd.Parent        = mainPart
				snd.Volume        = 0.65 * math.clamp(vel / 15, 0.4, 1)
				snd.PlaybackSpeed = math.random(95, 105) / 100
				snd:Play()
				Debris:AddItem(snd, snd.TimeLength + 0.5)
			end)

			magClone.Destroying:Connect(function() touchConn:Disconnect() end)
		end
	end

	-- Fade and destroy
	task.delay(FADE_DELAY, function()
		if not magClone.Parent then return end
		for _, part in allParts do
			if part.Parent then
				TweenService:Create(part, FADE_TWEEN_INFO, { Transparency = 1 }):Play()
			end
		end
		task.wait(FADE_TIME)
		if magClone.Parent then magClone:Destroy() end
	end)

	Debris:AddItem(magClone, TOTAL_LIFETIME)
end

-- ─── Public API ──────────────────────────────────────────────────────────────

function MagEjection.setup()
	setupCollisionGroups()

	for _, player in Players:GetPlayers() do
		if player.Character then
			setCharacterCollisionGroup(player.Character)
		end
		player.CharacterAdded:Connect(setCharacterCollisionGroup)
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(setCharacterCollisionGroup)
	end)
end

function MagEjection.ejectMag(player, gunModel, magFolder, ejectionCFrame)
	if not gunModel then
		warn("MagEjection: gunModel is nil")
		return
	end

	local mag = findMagazineInModel(gunModel)
	if not mag then
		warn("MagEjection: No mag found in " .. gunModel.Name)
		return
	end

	-- Resolve CFrame fallback
	local startCFrame = ejectionCFrame
	if not startCFrame then
		local ref = mag:IsA("BasePart") and mag
			or (mag:IsA("Model") and (mag.PrimaryPart or mag:FindFirstChildWhichIsA("BasePart")))
		startCFrame = (ref and ref.CFrame)
			or (gunModel.PrimaryPart and gunModel.PrimaryPart.CFrame)
			or CFrame.new()
	end

	local clone = cloneMag(mag)
	clone.Parent = magFolder

	setupMagPhysics(clone, startCFrame, player, getMagSoundsFolder())
end

function MagEjection.ejectMagServer(player, toolName, ejectionCFrame, dropPartNames, shellFolder, magDropFolderSounds)
	local assets = ReplicatedStorage:FindFirstChild("SPH_Assets")
	if not assets then
		warn("MagEjection Server: SPH_Assets not found")
		return
	end

	local weaponModels = assets:FindFirstChild("WeaponModels")
	if not weaponModels then
		warn("MagEjection Server: WeaponModels not found")
		return
	end

	local gunTemplate = weaponModels:FindFirstChild(toolName)
	if not gunTemplate then
		warn("MagEjection Server: No gun model found for " .. toolName)
		return
	end

	-- Load wepStats if available
	local statsModule = gunTemplate:FindFirstChild("SPH_Weapon")
		and gunTemplate.SPH_Weapon:FindFirstChild("WeaponStats")
	local wepStats = statsModule and require(statsModule)

	if type(dropPartNames) ~= "table" then
		dropPartNames = { dropPartNames or "" }
	end

	local soundsFolder = getMagSoundsFolder(
		(magDropFolderSounds and magDropFolderSounds ~= "") and magDropFolderSounds or "MagSounds"
	)

	for _, partName in dropPartNames do
		local mag = gunTemplate:FindFirstChild(partName, true)
			or findMagazineInModel(gunTemplate, wepStats)

		if not mag then
			warn("MagEjection Server: Could not find part '" .. tostring(partName) .. "' in " .. toolName)
			continue
		end

		local clone = cloneMag(mag)
		clone.Parent = shellFolder

		-- Reset transparency
		if clone:IsA("BasePart") then
			clone.Transparency = 0
		else
			for _, p in clone:GetDescendants() do
				if p:IsA("BasePart") then p.Transparency = 0 end
			end
		end

		setupMagPhysics(clone, ejectionCFrame, player, soundsFolder)
	end
end

MagEjection.setCharacterCollisionGroup = setCharacterCollisionGroup

return MagEjection