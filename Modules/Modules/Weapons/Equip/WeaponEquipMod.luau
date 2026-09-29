local WeaponEquipMod = {}

local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()
local SPH_Events = require(Modules.Core.Networking.SPH_Events)
local character
local humanoid
local assets
local weldMod
local storageCFrame
local camera
local assetPreloader
local rig
local lArm
local rArm
local vmShirt
local player
local config
local perGunSightIndex
local animCache
local equipConnections
local bulletHandler
local overheatThrottle
local lpvoThrottle
local headPoseReplicationMod
local ubglSystem
local switchWeapon
local replicatedStorage
local armPositionMod
local aimFOVTargetRef
local defaultFOV
local userInputService
local ContentProvider
local grenadeClient
local attachmentSystem
local mobileSupport
local warnPrefix
local recoilSpring
local gunRecoilSpring
local aimingSystemMod

local clearThirdPersonGunCache
local unequip
local unbindAiming
local collectAndManageSights
local applySavedAttachmentsToViewmodel
local refreshViewmodel
local bindGunInputs
local equipAnim
local idleAnim
local moveBoltAction
local syncThirdPersonProjectile
local playAnimation

local getThirdPersonGunModel

function WeaponEquipMod.Init(deps)
	getThirdPersonGunModel = deps.getThirdPersonGunModel
	character = deps.character
	humanoid = deps.humanoid
	assets = deps.assets
	weldMod = deps.weldMod
	storageCFrame = deps.storageCFrame
	camera = deps.camera
	assetPreloader = deps.assetPreloader
	rig = deps.rig
	lArm = deps.lArm
	rArm = deps.rArm
	vmShirt = deps.vmShirt
	player = deps.player
	config = deps.config
	perGunSightIndex = deps.perGunSightIndex
	animCache = deps.animCache
	equipConnections = deps.equipConnections
	bulletHandler = deps.bulletHandler
	overheatThrottle = deps.overheatThrottle
	lpvoThrottle = deps.lpvoThrottle
	headPoseReplicationMod = deps.headPoseReplicationMod
	ubglSystem = deps.ubglSystem
	switchWeapon = deps.switchWeapon
	replicatedStorage = deps.replicatedStorage
	armPositionMod = deps.armPositionMod
	aimFOVTargetRef = deps.aimFOVTargetRef
	defaultFOV = deps.defaultFOV
	userInputService = deps.userInputService
	ContentProvider = deps.ContentProvider
	grenadeClient = deps.grenadeClient
	attachmentSystem = deps.attachmentSystem
	mobileSupport = deps.mobileSupport
	warnPrefix = deps.warnPrefix
	recoilSpring = deps.recoilSpring
	gunRecoilSpring = deps.gunRecoilSpring
	aimingSystemMod = deps.aimingSystemMod

	clearThirdPersonGunCache = deps.clearThirdPersonGunCache
	unequip = deps.unequip
	unbindAiming = deps.unbindAiming
	collectAndManageSights = deps.collectAndManageSights
	applySavedAttachmentsToViewmodel = deps.applySavedAttachmentsToViewmodel
	refreshViewmodel = deps.refreshViewmodel
	bindGunInputs = deps.bindGunInputs
	equipAnim = deps.equipAnim
	idleAnim = deps.idleAnim
	moveBoltAction = deps.moveBoltAction
	syncThirdPersonProjectile = deps.syncThirdPersonProjectile
	playAnimation = deps.playAnimation


end

function WeaponEquipMod.EquipWeapon(newChild)
	clearThirdPersonGunCache()
	if vars.equipped then
		vars.switchingWeapons = true
		character:SetAttribute("SwitchingWeapons", true)
	end

	userInputService.MouseIconEnabled = false
	task.spawn(function()
		task.wait()
		userInputService.MouseIconEnabled = false
		task.wait(0.03)
		userInputService.MouseIconEnabled = false
	end)

	character:SetAttribute("BackpackDisabled", true)

	if vars.unequipping then
		repeat task.wait() until not vars.unequipping
	end

	local currentlyEquipped = vars.equipped
	if currentlyEquipped and currentlyEquipped ~= newChild then
		local backpack = player:FindFirstChildOfClass("Backpack")
		if backpack then
			newChild.Parent = backpack
		end
		vars.queuedTool = newChild
		unequip(currentlyEquipped, false)
		return
	end

	vars.reloading = false
	userInputService.MouseIconEnabled = false
	vars.hipRotation = Vector2.zero
	vars.equipping = true
	vars.equipGeneration = vars.equipGeneration + 1
	local capturedEquipGen = vars.equipGeneration
	vars.blocked = false
	vars.laserEnabled = false
	vars.flashlightEnabled = false
	vars.flashFX.beamFP.Enabled = false
	vars.flashFX.beamTP.Enabled = false
	vars.cycled = true
	vars.chambering = false
	vars.holdingM1 = false
	vars.nextScheduledFireTime = nil
	vars.canFire = true
	vars.bulletsCurrentlyFired = 0
	vars.preFirePlaying = false
	vars.preFireReady = false
	vars.preFireLocked = false
	if vars.preFireTrack then
		vars.preFireTrack:Stop(0)
		vars.preFireTrack = nil
	end

	vars.currentHeat = 0
	vars.isOverheated = false
	vars.lastShotTime = 0
	vars.cooldownStartTime = 0

	armPositionMod.ResetState()

	overheatThrottle:Reset()
	lpvoThrottle:Reset()
	headPoseReplicationMod.ResetLocalThrottle()

	switchWeapon.send(newChild)

	ubglSystem.Cleanup()

	vars.equipped = newChild

	local setupEvent = SPH_Events.Find("GunEvents", "SetupCustomizeGUI")
	if setupEvent and setupEvent:IsA("BindableEvent") then
		setupEvent:Fire(newChild)
	end

	if perGunSightIndex[newChild.Name] then
		vars.sightIndex = perGunSightIndex[newChild.Name]
	else
		vars.sightIndex = 1
		perGunSightIndex[newChild.Name] = 1
	end

	local equipped = vars.equipped
	local wepStats = require(equipped.SPH_Weapon.WeaponStats)
	vars.wepStats = wepStats

	if wepStats.weaponType == "Grenade" then
		unbindAiming()
		grenadeClient.EquipGrenadeTool(newChild)
		return
	end

	attachmentSystem.StoreBaseStats(equipped, wepStats)

	wepStats = attachmentSystem.ApplyStats(equipped, nil)
	vars.wepStats = wepStats

	local baseWalkSpeed = config.walkSpeed or 16
	humanoid.WalkSpeed = baseWalkSpeed * (wepStats.walkSpeedMultiplier or 1.0)
	character:SetAttribute("SprintSpeedMultiplier", wepStats.sprintSpeedMultiplier or 1.0)

	local aimFOVTarget = wepStats.aimFovDefault or wepStats.aimFov or defaultFOV
	vars.aimFOVTarget = aimFOVTarget
	aimFOVTargetRef.value = aimFOVTarget

	if not wepStats.aimFovMin then wepStats.aimFovMin = 30 end
	if not wepStats.aimFovMax then wepStats.aimFovMax = defaultFOV end

	if not wepStats.LPVOZoom then
		wepStats.LPVOZoom = {
			Enabled = true,
			leverRingName = "ADSRing",
			rotationSide = "left",
			moveCFrameLeftRight = -0.01,
			moveCFrameUpDown = -0.005,
			leverRingMaxRotation = 60,
			moveArm = true,
			armToMove = "Left Arm",
			rotationSideArm = "left",
		}
	else
		if not wepStats.LPVOZoom.rotationSide then
			wepStats.LPVOZoom.rotationSide = "Forward"
		end
	end

	recoilSpring.Damping = wepStats.recoil.damping
	recoilSpring.Speed = wepStats.recoil.speed
	gunRecoilSpring.Damping = wepStats.gunRecoil.damping
	gunRecoilSpring.Speed = wepStats.gunRecoil.speed
	vars.offset = wepStats.viewmodelOffset
	aimFOVTarget = wepStats.aimFovDefault or defaultFOV
	vars.aimFOVTarget = aimFOVTarget
	vars.freeLookOffset = CFrame.new()

	local proneAnim = wepStats.proneMoveAnim and playAnimation(wepStats.proneMoveAnim, {looped = true, priority = Enum.AnimationPriority.Movement, transSpeed = 1}, "ProneMove", true)
	vars.proneMoveAnim = proneAnim

	if not wepStats.operationType then wepStats.operationType = 1 end

	if type(wepStats.operationType) == "string" then
		wepStats.operationType = 1
	end
	if not wepStats.magType then
		wepStats.magType = 1
	end

	local oldGun = rig.Weapon:FindFirstChildWhichIsA("Model")
	if oldGun then oldGun:Destroy() end

	local gunTemplate = assets.WeaponModels:FindFirstChild(newChild.Name)
	if not gunTemplate then
		warn(warnPrefix .. "Could not find a gun model with the name: '" .. newChild.Name .. "'!")
		return
	end

	local gun = assetPreloader.CloneIfCached(newChild.Name)
	if not gun then
		gun = gunTemplate:Clone()
		if not wepStats.disableAutoRigging then
			weldMod.WeldModel(gun, gun.Grip, false)
			for _, partName in ipairs(wepStats.rigParts) do
				if gun:FindFirstChild(partName) then
					gun.Grip["Grip_" .. partName]:Destroy()
					local newMotor    = weldMod.M6D(gun.Grip, gun[partName])
					newMotor.Name     = partName
					newMotor.Parent   = gun.Grip
				end
			end
			for _, desc in gun:GetDescendants() do
				if desc:IsA("BasePart") then
					desc.CanCollide = false
					desc.CastShadow = false
				end
			end
		end

		task.spawn(function()
			local template = gun:Clone()
			for _, part in ipairs(template:GetDescendants()) do
				if part:IsA("BasePart") then
					part.Anchored = true
					part.CFrame   = storageCFrame
				end
			end

			if wepStats.projectile then
				for _, desc in ipairs(template:GetDescendants()) do
					if desc.Name == wepStats.projectile and desc:IsA("BasePart") then
						desc.Transparency = 1
						for _, child in ipairs(desc:GetDescendants()) do
							if child:IsA("BasePart") then
								child.Transparency = 1
							elseif child:IsA("Decal") or child:IsA("Texture") then
								child.Transparency = 1
							end
						end
						break
					end
				end
			end

			template.Parent = camera
			assetPreloader.SetCached(newChild.Name, template)
		end)
	end

	gun.Parent = rig.Weapon
	vars.gunModel = gun

	for _, part in ipairs(gun:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "" then
			part.Transparency = 1
		end
	end

	attachmentSystem.ClearAll(gun)
	attachmentSystem.PrepareForEquip(gun)
	collectAndManageSights(gun)

	weldMod.BlankM6D(rig.AnimBase, gun.Grip)

	equipped = vars.equipped
	if equipped:FindFirstChild("SavedAttachments") then
		applySavedAttachmentsToViewmodel(gun, equipped)

		local baseStats = require(equipped.SPH_Weapon.WeaponStats)
		attachmentSystem.StoreBaseStats(equipped, baseStats)
		wepStats = attachmentSystem.ApplyStats(equipped, gun)
		vars.wepStats = wepStats

		local baseWalkSpeed2 = config.walkSpeed or 16
		humanoid.WalkSpeed = baseWalkSpeed2 * (wepStats.walkSpeedMultiplier or 1.0)
		character:SetAttribute("SprintSpeedMultiplier", wepStats.sprintSpeedMultiplier or 1.0)

		aimFOVTarget = wepStats.aimFovDefault or wepStats.aimFov or defaultFOV
		vars.aimFOVTarget = aimFOVTarget
		aimFOVTargetRef.value = aimFOVTarget
		if not wepStats.aimFovMin then wepStats.aimFovMin = 30 end
		if not wepStats.aimFovMax then wepStats.aimFovMax = defaultFOV end
	end
	
	if aimingSystemMod and vars.wepStats then
		aimingSystemMod.UpdateADSVisual(gun, vars.wepStats, vars.sightIndex, vars.aiming == true, attachmentSystem)
	end

	attachmentSystem.DescribeMuzzle(gun)

	-- Capability questions now go through the attachment system rather than
	-- reading each fitted attachment's config table here.
	local autoLaser      = attachmentSystem.HasLaser(gun)
	local autoFlashlight = attachmentSystem.HasFlashlight(gun)
	local silencerVolumeMult = attachmentSystem.GetSilencerVolumeMultiplier(gun)
	if silencerVolumeMult < 1 then
		equipped:SetAttribute("FireVolumeMultiplier", silencerVolumeMult)
	else
		equipped:SetAttribute("FireVolumeMultiplier", nil)
	end

	lArm.Color = character["Left Arm"].Color
	rArm.Color = character["Right Arm"].Color
	for _, part in ipairs(rig:GetDescendants()) do
		if part.Name == "Skin" then
			if part.Parent.Name == "Left Arm" then
				part.Color = character["Left Arm"].Color
			elseif part.Parent.Name == "Right Arm" then
				part.Color = character["Right Arm"].Color
			end
		end
	end

	task.spawn(function()
		local plrShirt = character:FindFirstChildWhichIsA("Shirt")
		local shirtTemplate = plrShirt and plrShirt.ShirtTemplate or ""
		if shirtTemplate ~= "" then
			if vars.cachedShirtTemplate ~= shirtTemplate then
				pcall(function()
					ContentProvider:PreloadAsync({ shirtTemplate })
				end)
				vars.cachedShirtTemplate = shirtTemplate
			end
			pcall(function() vmShirt.ShirtTemplate = vars.cachedShirtTemplate end)
		else
			vmShirt.ShirtTemplate = ""
			vars.cachedShirtTemplate = ""
		end
	end)

	if vars.firstPerson then
		refreshViewmodel()
	end

	local capturedEquipGen2 = vars.equipGeneration

	local gunAmmo = newChild:WaitForChild("Ammo")
	gunAmmo:WaitForChild("MagAmmo")
	vars.gunAmmo = gunAmmo
	newChild:WaitForChild("BoltReady")
	newChild:WaitForChild("FireMode")
	if not wepStats.openBolt then
		newChild:WaitForChild("Chambered")
	end

	if vars.equipGeneration ~= capturedEquipGen2 or vars.equipped ~= newChild then
		return
	end

	bindGunInputs()
	mobileSupport.UpdateMobileButtonVisibility()

	equipAnim()
	idleAnim()

	local liveEquipped = vars.equipped
	local liveWepStats = vars.wepStats
	if not liveEquipped.BoltReady.Value then
		moveBoltAction(liveWepStats.boltDist, true)
	end

	local liveGunAmmo = vars.gunAmmo
	if liveGunAmmo then
		local function updateProjectileVisibility()
			if vars.equipped then
				syncThirdPersonProjectile()
			end
		end

		local magAmmoValue = liveGunAmmo:FindFirstChild("MagAmmo")
		if magAmmoValue then
			equipConnections:Add(magAmmoValue.Changed:Connect(updateProjectileVisibility))
		end

		local chambered = liveEquipped:FindFirstChild("Chambered")
		if chambered then
			equipConnections:Add(chambered.Changed:Connect(updateProjectileVisibility))
		end

		updateProjectileVisibility()
	end

	do
		local _capturedEquipped = vars.equipped
		local _capturedWepStats = vars.wepStats
		local _capturedGunAmmo = vars.gunAmmo
		local _boltReady = _capturedEquipped:FindFirstChild("BoltReady")
		local _chambered = _capturedEquipped:FindFirstChild("Chambered")
		local _shouldLock = (_boltReady and not _boltReady.Value)
			or (config.lockBoltOnEmpty
				and _boltReady and _boltReady.Value
				and _chambered and not _chambered.Value
				and _capturedGunAmmo.MagAmmo.Value <= 0)

		local currentGunModel = vars.gunModel

		if _shouldLock and _capturedWepStats.boltDist then
			pcall(bulletHandler.MoveBolt, currentGunModel, _capturedWepStats, _capturedWepStats.boltDist, _capturedGunAmmo.MagAmmo.Value, true)

			local tpGun = getThirdPersonGunModel()
			if tpGun then
				pcall(bulletHandler.MoveBolt, tpGun, _capturedWepStats, _capturedWepStats.boltDist, _capturedGunAmmo.MagAmmo.Value, true)
			else
				local _conn
				local weaponRig = vars.weaponRig
				_conn = weaponRig.Weapon.ChildAdded:Connect(function(child)
					if child:IsA("Model") then
						_conn:Disconnect()
						if vars.equipped == _capturedEquipped then
							pcall(bulletHandler.MoveBolt, child, _capturedWepStats, _capturedWepStats.boltDist, _capturedGunAmmo.MagAmmo.Value, true)
						end
					end
				end)
			end
		else
			pcall(bulletHandler.MoveBolt, currentGunModel, _capturedWepStats, CFrame.new(), _capturedGunAmmo.MagAmmo.Value, true)
		end
	end

	if animCache[newChild.Name] then
		local cached = animCache[newChild.Name]
		animCache[newChild.Name] = nil
		local allValid = true
		for _, track in pairs(cached) do
			if typeof(track) == "Instance" then
				local ok = pcall(function() return track.IsPlaying end)
				if not ok then allValid = false; break end
			end
		end
		if allValid then
			vars.loadedAnims = cached
		else
			for _, track in pairs(cached) do
				pcall(function()
					if typeof(track) == "Instance" and track:IsA("AnimationTrack") then
						track:Destroy()
					end
				end)
			end
		end
	end

	local finalWepStats = vars.wepStats

	if finalWepStats.emptyReloadAnim then
		playAnimation(finalWepStats.emptyReloadAnim, {speed = finalWepStats.reloadSpeedModifier or 1, priority = Enum.AnimationPriority.Action2, transSpeed = 0.17}, "Reload", true)
	end

	if config.lockFirstPerson then
		player.CameraMode = Enum.CameraMode.LockFirstPerson
	end

	local finalEquipped = vars.equipped
	vars.curFireMode = finalEquipped.FireMode.Value

	equipConnections:Add(finalEquipped.FireMode.Changed:Connect(function(newValue)
		vars.curFireMode = newValue
	end))

	local finalGunAmmo = vars.gunAmmo

	if finalWepStats.magType == 1 then
		playAnimation(finalWepStats.reloadAnim,{speed = finalWepStats.reloadSpeedModifier,priority = Enum.AnimationPriority.Action2,transSpeed = 0.17},"Reload",true)
	else
		playAnimation(finalWepStats.reloadAnim,{speed = finalWepStats.reloadSpeedModifier,priority = Enum.AnimationPriority.Action2,transSpeed = 0, looped = finalWepStats.magType ~= 4 and finalGunAmmo.MagAmmo.MaxValue > 1},"Reload",true)
		if finalWepStats.magType == 3 then
			playAnimation(finalWepStats.clipReloadAnim,{speed = finalWepStats.reloadSpeedModifier,priority = Enum.AnimationPriority.Action2,transSpeed = 0.17, looped = false},"Reload",true)
		end
	end

	playAnimation(finalWepStats.equipAnim,{priority = Enum.AnimationPriority.Action2, looped = false},"Equip", true)

	playAnimation(finalWepStats.boltChamber,{priority = Enum.AnimationPriority.Action2, transSpeed = 0.05, looped = false},"Chamber", true)

	if finalWepStats.operationType == 2 or finalWepStats.operationType == 3 then
		playAnimation(finalWepStats.boltOpen,{priority = Enum.AnimationPriority.Action2, transSpeed = 0, looped = false},"BoltOpen", true)
		playAnimation(finalWepStats.boltClose,{priority = Enum.AnimationPriority.Action2, looped = false},"BoltClose", true)
	end

	if finalWepStats.aimAnim then
		playAnimation(finalWepStats.aimAnim, {looped = true, priority = Enum.AnimationPriority.Action, transSpeed = finalWepStats.aimTime / 6}, "AimAnim", true)
	end

	if vars.isUnequippingForArmHiding then
		vars.isUnequippingForArmHiding = false
		character:SetAttribute("IsUnequippingForArmHiding", false)
	end

	vars.switchingWeapons = false
	character:SetAttribute("SwitchingWeapons", false)
end

return WeaponEquipMod