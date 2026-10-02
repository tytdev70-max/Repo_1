local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local modules = assets.Modules
local vars = require(modules.Weapons.Core.WeaponState).get()
local ContentProvider = game:GetService("ContentProvider")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")

local weldMod = require(modules.Weapons.Core.WeldMod)
local grenadeHandler = require(modules.Misc.Grenades.GrenadeHandler)
local Network = require(modules.Core.Networking.SPH_Network)

local module = {}

local deps = nil
local grenadeWatchdogGen = 0
local hiddenPartOriginalState = {}

function module.Init(dependencies)
	deps = dependencies
end

local FindNamedBasePart = grenadeHandler.FindNamedBasePart

local function CacheOriginalPartState(part)
	if hiddenPartOriginalState[part] then return end

	local descendants = {}
	for _, child in ipairs(part:GetDescendants()) do
		if child:IsA("BasePart") then
			descendants[child] = {
				Transparency = child.Transparency,
				LocalTransparencyModifier = child.LocalTransparencyModifier,
			}
		end
	end

	hiddenPartOriginalState[part] = {
		Transparency = part.Transparency,
		LocalTransparencyModifier = part.LocalTransparencyModifier,
		CanQuery = part.CanQuery,
		CanTouch = part.CanTouch,
		Descendants = descendants,
	}
end

local function DropGrenadeFirstPersonCosmetic(detachConfig)
	local gunModel = vars.gunModel
	if not detachConfig or not detachConfig.parts or not gunModel then return end
	for _, partName in ipairs(detachConfig.parts) do
		local part = FindNamedBasePart(gunModel, partName)
		if part and part:IsA("BasePart") then
			CacheOriginalPartState(part)
			part:SetAttribute("GrenadeCosmeticHidden", true)
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.LocalTransparencyModifier = 1
			for _, child in ipairs(part:GetDescendants()) do
				if child:IsA("BasePart") then
					child.Transparency = 1
					child.LocalTransparencyModifier = 1
				end
			end
		end
	end
end

local function DropGrenadeDetachable(detachConfig)
	if not detachConfig or not detachConfig.id then return end
	if vars.grenadeDroppedGroups[detachConfig.id] then return end
	vars.grenadeDroppedGroups[detachConfig.id] = true

	if vars.firstPerson then
		DropGrenadeFirstPersonCosmetic(detachConfig)
	end

	local wepStats = vars.wepStats
	local consumesOnThrow = wepStats and wepStats.grenade and wepStats.grenade.consumeOnThrow
	local equipped = vars.equipped
	if consumesOnThrow and equipped then
		Network.packets.RequestGrenadeCosmeticDetach.send({
			ToolName = equipped.Name,
			GroupId = detachConfig.id,
		})
	end
end

function module.RestoreGrenadeCosmeticParts()
	local wepStats = vars.wepStats
	if not wepStats or not wepStats.grenade then return end

	local gunModel = vars.gunModel
	if not gunModel then return end

	local partNames = {}
	local function CollectPartNames(grenadeConfig)
		if not grenadeConfig or not grenadeConfig.detachables then return end
		for _, detachConfig in ipairs(grenadeConfig.detachables) do
			if detachConfig.parts then
				for _, n in ipairs(detachConfig.parts) do table.insert(partNames, n) end
			end
		end
	end
	CollectPartNames(wepStats.grenade)
	CollectPartNames(wepStats.grenade.lowThrow)

	for _, partName in ipairs(partNames) do
		local part = FindNamedBasePart(gunModel, partName)
		if part and part:IsA("BasePart") and part:GetAttribute("GrenadeCosmeticHidden") then
			local original = hiddenPartOriginalState[part]
			part:SetAttribute("GrenadeCosmeticHidden", nil)
			if original then
				part.Transparency = original.Transparency
				part.LocalTransparencyModifier = original.LocalTransparencyModifier
				part.CanQuery = original.CanQuery
				part.CanTouch = original.CanTouch
				for child, state in pairs(original.Descendants) do
					if child.Parent then
						child.Transparency = state.Transparency
						child.LocalTransparencyModifier = state.LocalTransparencyModifier
					end
				end
				hiddenPartOriginalState[part] = nil
			else
				part.Transparency = 0
				part.LocalTransparencyModifier = 0
				part.CanQuery = true
				part.CanTouch = true
			end
		end
	end
end

function module.RestoreGrenadeHideables(isLowThrow)
	local wepStats = vars.wepStats
	if not wepStats or not wepStats.grenade then return end

	local activeHideables = (isLowThrow and wepStats.grenade.lowThrow and wepStats.grenade.lowThrow.hideables)
		or wepStats.grenade.hideables
	if not activeHideables then return end

	for _, hideConfig in ipairs(activeHideables) do
		if hideConfig.parts then
			deps.togglePartVisibility(hideConfig.parts, true)
		end
	end
end

function module.CleanupGrenadeCosmeticParts()
	for _, part in ipairs(vars.grenadeCosmeticParts) do
		if part and part.Parent then
			part:Destroy()
		end
	end
	vars.grenadeCosmeticParts = {}
end

function module.ForceGrenadeCosmeticDrop()
	local wepStats = vars.wepStats
	if not wepStats or not wepStats.grenade or not wepStats.grenade.detachables then return end
	for _, detachConfig in ipairs(wepStats.grenade.detachables) do
		DropGrenadeDetachable(detachConfig)
	end
end

function module.HandleThrowKeyframe(animName, keyframeName)
	local wepStats = vars.wepStats
	if not wepStats or not wepStats.grenade then return end

	local isLowThrowAnim = animName == wepStats.lowThrowAnim
	local activeDetachables = (isLowThrowAnim and wepStats.grenade.lowThrow and wepStats.grenade.lowThrow.detachables)
		or wepStats.grenade.detachables
	if activeDetachables then
		for _, detachConfig in ipairs(activeDetachables) do
			if keyframeName == detachConfig.keyframeName then
				DropGrenadeDetachable(detachConfig)
				return
			end
		end
	end

	local activeHideables = (isLowThrowAnim and wepStats.grenade.lowThrow and wepStats.grenade.lowThrow.hideables)
		or wepStats.grenade.hideables
	if activeHideables then
		for _, hideConfig in ipairs(activeHideables) do
			if keyframeName == hideConfig.keyframeName then
				deps.togglePartVisibility(hideConfig.parts, false)
				return
			end
		end
	end
end

function module.InspectGrenade()
	local equipped = vars.equipped
	local wepStats = vars.wepStats
	if not equipped or not wepStats then return end
	if vars.inspecting or vars.throwingGrenade or vars.equipping or vars.unequipping or vars.blocked then
		return
	end
	if not wepStats.InspectAnim then return end

	vars.inspecting = true
	deps.changeHoldStance(0)

	local inspectDoF = deps.inspectDoF
	if inspectDoF and not vars.isAimDoFActive then
		vars.inspectDoFActive = true
		inspectDoF.Enabled = true
	end

	local inspectTrack = deps.playAnimation(wepStats.InspectAnim, {
		priority = Enum.AnimationPriority.Action2,
		transSpeed = 0.2,
	})

	local function StopInspectDoF()
		if not vars.inspectDoFActive then return end
		vars.inspectDoFActive = false
		if inspectDoF then
			inspectDoF.Enabled = false
		end
	end

	if inspectTrack then
		inspectTrack.Stopped:Once(function()
			vars.inspecting = false
			StopInspectDoF()
		end)
	else
		vars.inspecting = false
		StopInspectDoF()
	end
end

function module.ThrowGrenade(isLowThrow)
	local equipped = vars.equipped
	local wepStats = vars.wepStats
	local gunModel = vars.gunModel
	if not equipped or not wepStats or not gunModel then return end
	if vars.throwingGrenade or vars.equipping or vars.unequipping or vars.dropping or vars.inspecting then return end
	if vars.switchingWeapons then return end
	if tick() < (vars.grenadeThrowUnlockTime or 0) then return end
	if not wepStats.grenade then
		warn("[GrenadeClient] '" .. equipped.Name .. "' is missing its wepStats.grenade config table.")
		return
	end

	if isLowThrow and not wepStats.lowThrowAnim then
		isLowThrow = false
	end

	vars.throwingGrenade = true
	vars.grenadeDroppedGroups = {}
	Network.packets.PlayerBeginGrenadeThrow.send(nil)

	local character = deps.character
	character:SetAttribute("BackpackDisabled", true)

	vars.isUnequippingForArmHiding = true
	character:SetAttribute("IsUnequippingForArmHiding", true)

	local capturedEquipGen = vars.equipGeneration
	local capturedTool = equipped
	local consumesOnThrow = wepStats.grenade and wepStats.grenade.consumeOnThrow

	local lowThrowConfig = wepStats.grenade.lowThrow
	local releaseKeyframeName = (isLowThrow and lowThrowConfig and lowThrowConfig.releaseKeyframeName)
		or wepStats.grenade.releaseKeyframeName

	grenadeWatchdogGen += 1
	local myWatchdogGen = grenadeWatchdogGen
	local finished = false
	local hasThrown = false

	local function FinishThrow()
		if finished then return end
		finished = true
		vars.throwingGrenade = false
		if consumesOnThrow then
			if vars.equipped == capturedTool and vars.equipGeneration == capturedEquipGen then
				deps.unequip(capturedTool, true, false)
			end
			vars.isUnequippingForArmHiding = false
			character:SetAttribute("IsUnequippingForArmHiding", false)
		else
			character:SetAttribute("BackpackDisabled", false)
			vars.isUnequippingForArmHiding = false
			character:SetAttribute("IsUnequippingForArmHiding", false)
			module.RestoreGrenadeCosmeticParts()
			module.RestoreGrenadeHideables(isLowThrow)
		end
	end

	local function DoThrow()
		if vars.equipGeneration ~= capturedEquipGen or not vars.equipped or not vars.wepStats then return end

		local throwDirection
		if vars.firstPerson then
			throwDirection = deps.camera.CFrame.LookVector
		else
			throwDirection = deps.humanoidRootPart.CFrame.LookVector
		end

		local tpGunModel = deps.getThirdPersonGunModel()
		local throwOrigin = tpGunModel
			and tpGunModel:FindFirstChild("Grip")
			and tpGunModel.Grip.Position

		Network.packets.PlayerThrowGrenade.send({
			Direction = throwDirection,
			ClientOrigin = throwOrigin,
			IsLowThrow = isLowThrow,
		})
	end

	local function DoThrowOnce()
		if hasThrown then return end
		hasThrown = true
		DoThrow()
	end

	local animToPlay = isLowThrow and wepStats.lowThrowAnim or wepStats.throwAnim

	local throwTrack = deps.playAnimation(animToPlay, {
		priority = Enum.AnimationPriority.Action2,
		looped = false,
	})

	local watchdogSeconds = (wepStats.grenade and wepStats.grenade.throwWatchdogTimeout) or 4
	task.delay(watchdogSeconds, function()
		if myWatchdogGen ~= grenadeWatchdogGen or finished then return end
		DoThrowOnce()
		FinishThrow()
	end)

	if throwTrack then
		if releaseKeyframeName then
			local releaseConn
			releaseConn = throwTrack.KeyframeReached:Connect(function(keyframeName)
				if keyframeName == releaseKeyframeName then
					DoThrowOnce()
					if releaseConn then
						releaseConn:Disconnect()
						releaseConn = nil
					end
				end
			end)

			throwTrack.Stopped:Once(function()
				if releaseConn then
					releaseConn:Disconnect()
					releaseConn = nil
				end
				DoThrowOnce()
				FinishThrow()
			end)
		else
			throwTrack.Stopped:Once(function()
				DoThrowOnce()
				FinishThrow()
			end)
		end
	else
		DoThrowOnce()
		FinishThrow()
	end
end

function module.HandleGrenadeInput(actionName, inputState, inputObject)
	if actionName == "SPH_Trigger" and inputState == Enum.UserInputState.Begin then
		module.ThrowGrenade(false)
	elseif actionName == "SPH_HoldAim" and inputState == Enum.UserInputState.Begin then
		module.ThrowGrenade(true)
	elseif actionName == "SPH_Inspect" and inputState == Enum.UserInputState.Begin then
		module.InspectGrenade()
	end
end

function module.BindGrenadeInputs()
	local config = deps.config
	ContextActionService:BindActionAtPriority("SPH_Trigger", deps.handleInput, false, config.gunInputPriority, unpack(config.fireGun))
	ContextActionService:BindActionAtPriority("SPH_Inspect", deps.handleInput, false, config.gunInputPriority, unpack(config.keyInspect))
	ContextActionService:BindActionAtPriority("SPH_HoldAim", deps.handleInput, false, config.gunInputPriority, unpack(config.aimGun))

	if deps.mobileSupport then
		deps.mobileSupport.SetupMobileButtons(deps.aimFOVTargetRef)
	end
end

local function SyncArmColors()
	deps.lArm.Color = deps.character["Left Arm"].Color
	deps.rArm.Color = deps.character["Right Arm"].Color
	for _, part in ipairs(deps.rig:GetDescendants()) do
		if part.Name == "Skin" then
			if part.Parent.Name == "Left Arm" then
				part.Color = deps.character["Left Arm"].Color
			elseif part.Parent.Name == "Right Arm" then
				part.Color = deps.character["Right Arm"].Color
			end
		end
	end
end

local function RefreshViewmodelShirt()
	local plrShirt = deps.character:FindFirstChildWhichIsA("Shirt")
	local shirtTemplate = plrShirt and plrShirt.ShirtTemplate or ""
	if shirtTemplate ~= "" then
		if vars.cachedShirtTemplate ~= shirtTemplate then
			pcall(function()
				ContentProvider:PreloadAsync({ shirtTemplate })
			end)
			vars.cachedShirtTemplate = shirtTemplate
		end
		pcall(function() deps.vmShirt.ShirtTemplate = vars.cachedShirtTemplate end)
	else
		deps.vmShirt.ShirtTemplate = ""
		vars.cachedShirtTemplate = ""
	end
end

function module.EquipGrenadeTool(newChild)
	local wepStats = vars.wepStats
	local character = deps.character
	local humanoid = deps.humanoid
	local rig = deps.rig
	local config = deps.config

	deps.resetSightCaches()
	vars.gunAmmo = nil
	vars.throwingGrenade = false
	vars.grenadeDroppedGroups = {}
	hiddenPartOriginalState = {}
	vars.inspecting = false
	vars.blocked = false

	local baseWalkSpeed = config.walkSpeed or 16
	humanoid.WalkSpeed = baseWalkSpeed * (wepStats.walkSpeedMultiplier or 1.0)
	character:SetAttribute("SprintSpeedMultiplier", wepStats.sprintSpeedMultiplier or 1.0)

	local oldGun = rig.Weapon:FindFirstChildWhichIsA("Model")
	if oldGun then oldGun:Destroy() end

	local gunTemplate = assets.WeaponModels:FindFirstChild(newChild.Name)
	if not gunTemplate then
		warn("[GrenadeClient] Could not find a gun model with the name: '" .. newChild.Name .. "'!")
		return
	end

	local gun = gunTemplate:Clone()
	if not wepStats.disableAutoRigging then
		weldMod.WeldModel(gun, gun.Grip, false)
		for _, partName in ipairs(wepStats.rigParts or {}) do
			if gun:FindFirstChild(partName) then
				local existingWeld = gun.Grip:FindFirstChild("Grip_" .. partName)
				if existingWeld then existingWeld:Destroy() end
				local newMotor = weldMod.M6D(gun.Grip, gun[partName])
				newMotor.Name = partName
				newMotor.Parent = gun.Grip
			end
		end
		for _, desc in ipairs(gun:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
				desc.CastShadow = false
			end
		end
	end

	gun.Parent = rig.Weapon
	vars.gunModel = gun

	weldMod.BlankM6D(rig.AnimBase, gun.Grip)

	SyncArmColors()

	task.spawn(RefreshViewmodelShirt)

	if deps.animCache[newChild.Name] then
		local cached = deps.animCache[newChild.Name]
		deps.animCache[newChild.Name] = nil
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
			vars.loadedAnims = {}
		end
	else
		vars.loadedAnims = {}
	end

	vars.offset = wepStats.viewmodelOffset or CFrame.new()
	vars.freeLookOffset = CFrame.new()
	vars.viewmodelVisible = false

	local capturedEquipGen = vars.equipGeneration

	character:SetAttribute("BackpackDisabled", true)
	vars.equipping = true

	local animTrack = deps.playAnimation(wepStats.equipAnim, {
		priority = Enum.AnimationPriority.Action2,
		looped = false,
	}, "Equip")

	if vars.firstPerson then
		task.spawn(function()
			task.wait()
			if vars.equipGeneration ~= capturedEquipGen then return end
			vars.viewmodelVisible = true
			deps.refreshViewmodel()
		end)
	end

	local function FinishEquip()
		if vars.equipGeneration ~= capturedEquipGen then return end
		vars.equipping = false
		vars.grenadeThrowUnlockTime = tick() + 0.25
		module.BindGrenadeInputs()
		local currentSprint = character:GetAttribute("Sprinting")
		vars.sprinting = currentSprint
		deps.toggleSprint(currentSprint)
		UserInputService.MouseIconEnabled = false
		if vars.switchingWeapons then
			character:SetAttribute("BackpackDisabled", true)
		elseif not character:GetAttribute("IsSwimming") then
			character:SetAttribute("BackpackDisabled", false)
		end
		deps.idleAnim()
	end

	if animTrack then
		animTrack.Stopped:Once(FinishEquip)
	else
		FinishEquip()
	end

	vars.switchingWeapons = false
	character:SetAttribute("SwitchingWeapons", false)
end

return module