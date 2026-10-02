local AttachmentManager = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local WeaponLighting = require(script.Parent.WeaponLighting)

local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local attachmentsFolder = assets:WaitForChild("GunAttachments")

local configCache = {}
local activeAttachments = {}
local originalStatsCache = {}
local activeGripStates = {}
local weaponOwnership = {}
local processedTools = {}

local activeUpdaters = {}
local updaterCount = 0
local heartbeatConn: RBXScriptConnection? = nil

local destroyHooked: {[Instance]: RBXScriptConnection} = {}

local function PurgeWeaponModel(weaponModel)
	local attachments = activeAttachments[weaponModel]
	if attachments then
		local categories = activeUpdaters[weaponModel]
		if categories then
			for category in pairs(attachments) do
				if categories[category] then
					categories[category] = nil
					updaterCount = math.max(0, updaterCount - 1)
				end
			end
		end
	end

	activeUpdaters[weaponModel] = nil
	activeAttachments[weaponModel] = nil
	activeGripStates[weaponModel] = nil
	weaponOwnership[weaponModel] = nil

	local hook = destroyHooked[weaponModel]
	if hook then
		hook:Disconnect()
		destroyHooked[weaponModel] = nil
	end

	if updaterCount <= 0 and heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

local function HookWeaponModelDestroying(weaponModel)
	if destroyHooked[weaponModel] then return end
	destroyHooked[weaponModel] = weaponModel.Destroying:Connect(function()
		PurgeWeaponModel(weaponModel)
	end)
end

local function RunActiveUpdaters(deltaTime)
	for weaponModel, categories in pairs(activeUpdaters) do
		if not weaponModel.Parent then
			PurgeWeaponModel(weaponModel)
		else
			local attachments = activeAttachments[weaponModel]
			if attachments then
				for category in pairs(categories) do
					local attachmentData = attachments[category]
					if attachmentData and attachmentData.config and attachmentData.config.OnUpdate then
						pcall(attachmentData.config.OnUpdate, nil, nil, deltaTime)
					end
				end
			end
		end
	end
end

local function RegisterUpdater(weaponModel, category)
	local categories = activeUpdaters[weaponModel]
	if not categories then
		categories = {}
		activeUpdaters[weaponModel] = categories
	end

	if not categories[category] then
		categories[category] = true
		updaterCount += 1

		if not heartbeatConn then
			heartbeatConn = RunService.Heartbeat:Connect(RunActiveUpdaters)
		end
	end
end

local function UnregisterUpdater(weaponModel, category)
	local categories = activeUpdaters[weaponModel]
	if not categories or not categories[category] then return end

	categories[category] = nil
	updaterCount = math.max(0, updaterCount - 1)

	if not next(categories) then
		activeUpdaters[weaponModel] = nil
	end

	if updaterCount <= 0 and heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

function AttachmentManager.LoadAttachmentConfig(attachmentName, category)
	local cacheKey = category .. "/" .. attachmentName

	if configCache[cacheKey] then
		return configCache[cacheKey]
	end

	if not attachmentsFolder then
		return nil
	end

	local categoryFolder = attachmentsFolder:FindFirstChild(category)
	if not categoryFolder then
		return nil
	end

	local attachmentFolder = categoryFolder:FindFirstChild(attachmentName)
	if not attachmentFolder then
		return nil
	end

	local customizationModule = attachmentFolder:FindFirstChild("Customization")
	if not customizationModule then
		return nil
	end

	local success, config = pcall(function()
		return require(customizationModule)
	end)

	if not success then
		return nil
	end

	configCache[cacheKey] = config

	return config
end

function AttachmentManager.PrepareForEquip(weaponModel)
	if not weaponModel then return end

	if activeAttachments[weaponModel] then
		for category, _ in pairs(activeAttachments[weaponModel]) do
			AttachmentManager.UnequipAttachment(weaponModel, category)
		end
	end

	for _, part in ipairs(weaponModel:GetDescendants()) do
		if part:IsA("Folder") and string.match(part.Name, "_Equipped$") then
			part:Destroy()
		end
	end

	activeAttachments[weaponModel] = {}
end

function AttachmentManager.EquipAttachment(player, weapon, weaponModel, attachmentName, category)
	if activeAttachments[weaponModel] and activeAttachments[weaponModel][category] then
		local currentAttachment = activeAttachments[weaponModel][category].attachmentName
		if currentAttachment == attachmentName then
			return true
		end
	end

	if not weapon or not weaponModel then
		return false
	end

	if weaponOwnership[weaponModel] and weaponOwnership[weaponModel] ~= weapon then
		AttachmentManager.PrepareForEquip(weaponModel)
	end
	weaponOwnership[weaponModel] = weapon
	HookWeaponModelDestroying(weaponModel)

	local config = AttachmentManager.LoadAttachmentConfig(attachmentName, category)
	if not config then
		return false
	end

	if not config.IsCompatible(weapon.Name) then
		return false
	end

	if activeAttachments[weaponModel] and activeAttachments[weaponModel][category] then
		local currentAttachment = activeAttachments[weaponModel][category].attachmentName
		if currentAttachment == attachmentName then
			return true
		else
			AttachmentManager.UnequipAttachment(weaponModel, category)
		end
	end

	local categoryPartName = category .. "Part"
	if category == "Underbarrel" then
		categoryPartName = "GripPart"
	elseif category == "Optics" then
		categoryPartName = "OpticPart"
	elseif category == "Muzzle" then
		categoryPartName = "MuzzlePart"
	elseif category == "Stock" then
		categoryPartName = "StockPart"
	end

	local categoryPart = weaponModel:FindFirstChild(categoryPartName, true)

	if not categoryPart then
		return false
	end

	local mountPoint = categoryPart:FindFirstChild(attachmentName)

	if not mountPoint or not mountPoint:IsA("Attachment") then
		return false
	end

	local existingNode = categoryPart:FindFirstChild(attachmentName .. "_Equipped")
	if existingNode then
		existingNode:Destroy()
		task.wait(0.05)
	end

	local attachmentNode = Instance.new("Folder")
	attachmentNode.Name = attachmentName .. "_Equipped"
	attachmentNode.Parent = categoryPart

	local categoryFolder = attachmentsFolder:FindFirstChild(category)
	if not categoryFolder then
		return false
	end

	local attachmentFolder = categoryFolder:FindFirstChild(attachmentName)

	if not attachmentFolder then
		return false
	end

	local rootName = config.RootPart
	if not rootName then
		local firstPart = attachmentFolder:FindFirstChildOfClass("BasePart") or attachmentFolder:FindFirstChildOfClass("MeshPart")
		if firstPart then
			rootName = firstPart.Name
		else
			return false
		end
	end

	local originalRoot = attachmentFolder:FindFirstChild(rootName)
	if not originalRoot then
		return false
	end

	local cloneParts = {}
	for _, child in ipairs(attachmentFolder:GetChildren()) do
		if child:IsA("BasePart") or child:IsA("MeshPart") then
			local clone = child:Clone()
			clone.Parent = attachmentNode
			clone.CanCollide = false
			clone.Anchored = false
			cloneParts[child.Name] = clone
		end
	end

	local cloneRoot = cloneParts[rootName]
	if not cloneRoot then
		return false
	end

	local mountOffset = config.MountOffset or CFrame.new()

	local rootMotor = Instance.new("Motor6D")
	rootMotor.Name = "AttachmentMotor_Root_" .. attachmentName
	rootMotor.Part0 = mountPoint.Parent
	rootMotor.Part1 = cloneRoot
	rootMotor.C0 = mountPoint.CFrame * mountOffset
	rootMotor.C1 = CFrame.new()
	rootMotor.Parent = cloneRoot

	for originalName, clonePart in pairs(cloneParts) do
		if originalName ~= rootName then
			local originalPart = attachmentFolder:FindFirstChild(originalName)
			if originalPart then
				local relativeCF = originalRoot.CFrame:Inverse() * originalPart.CFrame

				local childMotor = Instance.new("Motor6D")
				childMotor.Name = "AttachmentMotor_" .. originalName
				childMotor.Part0 = cloneRoot
				childMotor.Part1 = clonePart
				childMotor.C0 = relativeCF
				childMotor.C1 = CFrame.new()
				childMotor.Parent = clonePart
			end
		end
	end

	for _, clonePart in pairs(cloneParts) do
		clonePart.CanCollide = false
		clonePart.Massless = true
	end

	for _, partName in ipairs(config.VisibleParts or {}) do
		local part = attachmentNode:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			part.Transparency = 0
		end
	end

	for _, partName in ipairs(config.HideGunParts or {}) do
		local part = weaponModel:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			part.Transparency = config.HideTransparency or 1
		end
	end

	if category == "Muzzle" then
		local base = weaponModel:FindFirstChild("Grip") or weaponModel:FindFirstChild("Base")
		if base then
			local originalMuzzle = base:FindFirstChild("Muzzle", true)
			if originalMuzzle then
				local hideTarget
				if originalMuzzle:IsA("Attachment") then
					hideTarget = originalMuzzle.Parent
				elseif originalMuzzle:IsA("BasePart") then
					hideTarget = originalMuzzle
				end

				if hideTarget and hideTarget:IsA("BasePart") then
					if not hideTarget:GetAttribute("OriginalTransparency_Muzzle") then
						hideTarget:SetAttribute("OriginalTransparency_Muzzle", hideTarget.Transparency)
					end
					hideTarget.Transparency = 1
					hideTarget.CastShadow = false

					for _, child in ipairs(hideTarget:GetDescendants()) do
						if child:IsA("BasePart") then
							if not child:GetAttribute("OriginalTransparency_Muzzle") then
								child:SetAttribute("OriginalTransparency_Muzzle", child.Transparency)
							end
							child.Transparency = 1
							child.CastShadow = false
						elseif child:IsA("ParticleEmitter") or child:IsA("Light") then
							if not child:GetAttribute("OriginalEnabled_Muzzle") then
								child:SetAttribute("OriginalEnabled_Muzzle", child.Enabled)
							end
							child.Enabled = false
						end
					end

					if originalMuzzle:IsA("Attachment") then
						originalMuzzle.Visible = false
						originalMuzzle:SetAttribute("OverriddenByAttachment", true)
					end
				end
			end

			local customMuzzle = attachmentNode:FindFirstChild("Muzzle", true)
			if customMuzzle then
				weaponModel:SetAttribute("ActiveCustomMuzzle", attachmentName)
			end
		end
	end

	if config.EnableLaser then
		for _, child in ipairs(attachmentNode:GetDescendants()) do
			if child:IsA("Beam") then
				child.Enabled = false
			end
		end
	end

	if not activeAttachments[weaponModel] then
		activeAttachments[weaponModel] = {}
	end

	activeAttachments[weaponModel][category] = {
		config = config,
		model = attachmentNode,
		attachmentName = attachmentName
	}

	if type(config.OnUpdate) == "function" then
		RegisterUpdater(weaponModel, category)
	end

	if config.OnEquip then
		pcall(function()
			config.OnEquip(player, weapon, attachmentNode)
		end)
	end

	return true
end

function AttachmentManager.GetAttachmentAimPart(weaponModel, sightIndex)
	if not activeAttachments[weaponModel] then
		return nil
	end

	local opticsAttachment = activeAttachments[weaponModel]["Optics"]
	if opticsAttachment then
		local attachmentNode = opticsAttachment.model

		if sightIndex > 1 then
			local indexedAimPart = attachmentNode:FindFirstChild("AimPart" .. sightIndex, true)
			if indexedAimPart then
				return indexedAimPart
			end
		end

		local aimPart = attachmentNode:FindFirstChild("AimPart", true)
		if aimPart then
			return aimPart
		end
	end

	return nil
end

function AttachmentManager.GetGripHandPosition(weaponModel, weaponName)
	if not activeAttachments[weaponModel] then
		return nil
	end

	local gripAttachment = activeAttachments[weaponModel]["Underbarrel"]
	if gripAttachment and gripAttachment.config.EnableHandPositioning then
		local config = gripAttachment.config

		local attachmentModel = gripAttachment.model
		local gripPart = attachmentModel:FindFirstChild(config.HandGripPart, true)

		if gripPart then
			activeGripStates[weaponModel] = true

			local gripWorldCFrame
			if gripPart:IsA("Attachment") then
				gripWorldCFrame = gripPart.WorldCFrame
			elseif gripPart:IsA("BasePart") then
				gripWorldCFrame = gripPart.CFrame
			end

			return {
				gripWorldCFrame = gripWorldCFrame,
				handToPosition = config.HandToPosition or "Left Arm",
				transitionSpeed = config.HandTransitionSpeed or 15,
				matchRotation = config.HandMatchRotation ~= false,
			}
		end
	end

	return nil
end

function AttachmentManager.GetActiveMuzzle(weaponModel)
	if not weaponModel then return nil end

	if activeAttachments[weaponModel] and activeAttachments[weaponModel]["Muzzle"] then
		local muzzleAttachment = activeAttachments[weaponModel]["Muzzle"]
		local attachmentNode = muzzleAttachment.model

		local attachmentMuzzle = attachmentNode:FindFirstChild("Muzzle", true)
		if attachmentMuzzle then
			return attachmentMuzzle
		end
	end

	local customMuzzleName = weaponModel:GetAttribute("ActiveCustomMuzzle")
	if customMuzzleName then
		for _, part in ipairs(weaponModel:GetDescendants()) do
			if part:IsA("Folder") and part.Name == customMuzzleName .. "_Equipped" then
				local customMuzzle = part:FindFirstChild("Muzzle", true)
				if customMuzzle then
					return customMuzzle
				end
			end
		end
	end

	local grip = weaponModel:FindFirstChild("Grip")
	local originalMuzzle = grip and grip:FindFirstChild("Muzzle")
	return originalMuzzle
end

function AttachmentManager.GetMuzzleAttachmentConfig(weaponModel)
	if not activeAttachments[weaponModel] then
		return nil
	end

	local muzzleAttachment = activeAttachments[weaponModel]["Muzzle"]
	if muzzleAttachment then
		return muzzleAttachment.config
	end

	return nil
end

function AttachmentManager.GetOverheatConfig(weaponModel)
	if not activeAttachments[weaponModel] then
		return nil
	end

	local muzzleAttachment = activeAttachments[weaponModel]["Muzzle"]
	if muzzleAttachment and muzzleAttachment.config.overHeating then
		return muzzleAttachment.config.overHeating
	end

	return nil
end

function AttachmentManager.GetReticleConfig(weaponModel)
	if not activeAttachments[weaponModel] then
		return nil
	end

	local opticsAttachment = activeAttachments[weaponModel]["Optics"]
	if opticsAttachment and opticsAttachment.config.ReticleConfig then
		return opticsAttachment.config.ReticleConfig
	end

	return nil
end

function AttachmentManager.GetDepthOfFieldConfig(weaponModel)
	if not activeAttachments[weaponModel] then
		return nil
	end

	local opticsAttachment = activeAttachments[weaponModel]["Optics"]
	if opticsAttachment and opticsAttachment.config.DepthOfField then
		return opticsAttachment.config.DepthOfField
	end

	return nil
end

function AttachmentManager.ApplyAttachmentADSVisibility(weaponModel, aiming, wepStats)
	if not weaponModel or not activeAttachments[weaponModel] then
		return
	end

	local tweenTime = 0.2
	if wepStats and wepStats.aimTime then
		tweenTime = wepStats.aimTime / 20
	end
	local adsTween = TweenInfo.new(tweenTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, tweenTime)

	local function setPartTransparency(attachmentNode, partName, transparency)
		local part = attachmentNode:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			TweenService:Create(part, adsTween, {Transparency = transparency}):Play()
		end
	end

	for _, attachmentData in pairs(activeAttachments[weaponModel]) do
		local config = attachmentData.config
		local attachmentNode = attachmentData.model
		if not config or not attachmentNode then
			continue
		end

		if config.TransparentOnADS then
			for _, partName in ipairs(config.TransparentOnADS) do
				setPartTransparency(attachmentNode, partName, aiming and 1 or 0)
			end
		end

		if config.VisibleOnADS then
			for _, partName in ipairs(config.VisibleOnADS) do
				setPartTransparency(attachmentNode, partName, aiming and 0 or 1)
			end
		end

		if config.LPVOZoom and config.LPVOZoom.Enabled and config.LPVOZoom.leverRingName then
			setPartTransparency(attachmentNode, config.LPVOZoom.leverRingName, aiming and 0 or 1)
		end
	end
end

function AttachmentManager.HasMuzzleOverride(weaponModel)
	return activeAttachments[weaponModel] and activeAttachments[weaponModel]["Muzzle"] ~= nil
end

function AttachmentManager.HasGripEquipped(weaponModel)
	if not activeAttachments[weaponModel] then
		return false
	end

	local gripAttachment = activeAttachments[weaponModel]["Underbarrel"]
	return gripAttachment and gripAttachment.config.EnableHandPositioning == true
end

function AttachmentManager.UnequipAttachment(weaponModel, category)
	if not activeAttachments[weaponModel] or not activeAttachments[weaponModel][category] then
		return
	end

	local attachmentData = activeAttachments[weaponModel][category]
	local config = attachmentData.config
	local attachmentNode = attachmentData.model

	if config.OnUnequip then
		pcall(function()
			config.OnUnequip(nil, nil, attachmentNode)
		end)
	end

	for _, partName in ipairs(config.HideGunParts or {}) do
		local part = weaponModel:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			part.Transparency = 0
		end
	end

	if category == "Muzzle" then
		local base = weaponModel:FindFirstChild("Grip") or weaponModel:FindFirstChild("Base")
		if base then
			local originalMuzzle = base:FindFirstChild("Muzzle", true)
			if originalMuzzle then
				local restoreTarget
				if originalMuzzle:IsA("Attachment") then
					restoreTarget = originalMuzzle.Parent
				elseif originalMuzzle:IsA("BasePart") then
					restoreTarget = originalMuzzle
				end

				if restoreTarget and restoreTarget:IsA("BasePart") and not restoreTarget:GetAttribute("MuzzlePreHidden") then
					local origTrans = restoreTarget:GetAttribute("OriginalTransparency_Muzzle")
					if origTrans ~= nil then
						restoreTarget.Transparency = origTrans
						restoreTarget.CastShadow = true
						restoreTarget:SetAttribute("OriginalTransparency_Muzzle", nil)
					end

					for _, child in ipairs(restoreTarget:GetDescendants()) do
						if child:IsA("BasePart") then
							local childOrigTrans = child:GetAttribute("OriginalTransparency_Muzzle")
							if childOrigTrans ~= nil then
								child.Transparency = childOrigTrans
								child.CastShadow = true
								child:SetAttribute("OriginalTransparency_Muzzle", nil)
							end
						elseif child:IsA("ParticleEmitter") or child:IsA("Light") then
							local origEnabled = child:GetAttribute("OriginalEnabled_Muzzle")
							if origEnabled ~= nil then
								child.Enabled = origEnabled
								child:SetAttribute("OriginalEnabled_Muzzle", nil)
							end
						end
					end
				end
			end
		end

		weaponModel:SetAttribute("ActiveCustomMuzzle", nil)
	end

	if attachmentNode and attachmentNode.Parent then
		attachmentNode:Destroy()
	end

	UnregisterUpdater(weaponModel, category)

	activeAttachments[weaponModel][category] = nil
end

function AttachmentManager.CleanupMuzzleState(weaponModel)
	local base = weaponModel:FindFirstChild("Grip") or weaponModel:FindFirstChild("Base")
	if not base then return end

	local originalMuzzle = base:FindFirstChild("Muzzle", true)
	if not originalMuzzle then return end

	local target
	if originalMuzzle:IsA("Attachment") then
		target = originalMuzzle.Parent
	elseif originalMuzzle:IsA("BasePart") then
		target = originalMuzzle
	end

	if target and target:IsA("BasePart") then
		target:SetAttribute("MuzzlePreHidden", nil)
	end

	weaponModel:SetAttribute("ActiveCustomMuzzle", nil)
end

function AttachmentManager.PreHideOriginalMuzzle(weaponModel)
	local base = weaponModel:FindFirstChild("Grip") or weaponModel:FindFirstChild("Base")
	if not base then return end

	local originalMuzzle = base:FindFirstChild("Muzzle", true)
	if not originalMuzzle then return end

	local hideTarget
	if originalMuzzle:IsA("Attachment") then
		hideTarget = originalMuzzle.Parent
	elseif originalMuzzle:IsA("BasePart") then
		hideTarget = originalMuzzle
	end

	if hideTarget and hideTarget:IsA("BasePart") then
		hideTarget:SetAttribute("MuzzlePreHidden", true)

		if not hideTarget:GetAttribute("OriginalTransparency_Muzzle") then
			hideTarget:SetAttribute("OriginalTransparency_Muzzle", hideTarget.Transparency)
		end

		hideTarget.Transparency = 1
		hideTarget.CastShadow = false

		for _, child in ipairs(hideTarget:GetDescendants()) do
			if child:IsA("BasePart") then
				if not child:GetAttribute("OriginalTransparency_Muzzle") then
					child:SetAttribute("OriginalTransparency_Muzzle", child.Transparency)
				end
				child.Transparency = 1
				child.CastShadow = false
			elseif child:IsA("ParticleEmitter") then
				if not child:GetAttribute("OriginalEnabled_Muzzle") then
					child:SetAttribute("OriginalEnabled_Muzzle", child.Enabled)
				end
				child.Enabled = false
			elseif child:IsA("Light") then
				if not child:GetAttribute("OriginalEnabled_Muzzle") then
					child:SetAttribute("OriginalEnabled_Muzzle", child.Enabled)
				end
				child.Enabled = false
			end
		end

		if originalMuzzle:IsA("Attachment") then
			originalMuzzle.Visible = false
			originalMuzzle:SetAttribute("OverriddenByAttachment", true)
		end
	end
end

-- Color3/UDim2 and callable WeaponStats fields are not a JSON round-trip.
-- Keep live stats authoritative; optional JSON snapshots must never abort equip.
local function WriteStatsSnapshot(weapon, attribute, stats)
	local ok, json = pcall(function() return HttpService:JSONEncode(stats) end)
	weapon:SetAttribute(attribute, if ok then json else nil)
end

function AttachmentManager.StoreOriginalStats(weapon, baseStats)
	if not weapon or not baseStats then return end

	local function deepCopy(original)
		local copy = {}
		for k, v in pairs(original) do
			if type(v) == "table" then
				copy[k] = deepCopy(v)
			else
				copy[k] = v
			end
		end
		return copy
	end

	originalStatsCache[weapon] = deepCopy(baseStats)

	WriteStatsSnapshot(weapon, "OriginalStats", baseStats)
end

function AttachmentManager.RestoreStatsFromTool(weapon)
	if not weapon then return nil end

	if originalStatsCache[weapon] then
		return originalStatsCache[weapon]
	end

	local statsJSON = weapon:GetAttribute("OriginalStats")
	if statsJSON then
		local success, baseStats = pcall(function()
			return HttpService:JSONDecode(statsJSON)
		end)

		if success and type(baseStats) == "table" then
			local authored = WeaponLighting.GetStatsForSource(weapon)
			if authored then
				baseStats.Flashlight = authored.Flashlight
				baseStats.Laser = authored.Laser
			end
			originalStatsCache[weapon] = baseStats
			return baseStats
		end
	end

	return nil
end

function AttachmentManager.ApplyAttachmentStats(weapon, weaponModel)
	if not weapon then
		return nil
	end

	local baseStats = AttachmentManager.RestoreStatsFromTool(weapon)
	if not baseStats then
		return nil
	end

	local function deepCopy(original)
		local copy = {}
		for k, v in pairs(original) do
			if type(v) == "table" then
				copy[k] = deepCopy(v)
			else
				copy[k] = v
			end
		end
		return copy
	end

	local modifiedStats = deepCopy(baseStats)

	if not weaponModel then
		local camera = workspace.CurrentCamera
		local viewRig = camera:FindFirstChildWhichIsA("Model")
		if viewRig then
			local weaponFolder = viewRig:FindFirstChild("Weapon")
			if weaponFolder then
				weaponModel = weaponFolder:FindFirstChildWhichIsA("Model")
			end
		end
	end

	if not weaponModel then
		return modifiedStats
	end

	if weaponOwnership[weaponModel] and weaponOwnership[weaponModel] ~= weapon then
		return modifiedStats
	end

	if activeAttachments[weaponModel] then
		local attachmentCount = 0
		for category, attachmentData in pairs(activeAttachments[weaponModel]) do
			local config = attachmentData.config
			if config and config.ApplyStats then
				modifiedStats = config.ApplyStats(modifiedStats)
				attachmentCount = attachmentCount + 1
			end
		end

		WriteStatsSnapshot(weapon, "ModifiedStats", modifiedStats)
	end

	return modifiedStats
end

function AttachmentManager.ClearOriginalStats(weapon)
end

function AttachmentManager.ClearAllAttachments(weaponModel)
	if not weaponModel then return end

	if activeAttachments[weaponModel] then
		for category, _ in pairs(activeAttachments[weaponModel]) do
			AttachmentManager.UnequipAttachment(weaponModel, category)
		end
	end

	for _, part in ipairs(weaponModel:GetDescendants()) do
		if part:IsA("Folder") and string.match(part.Name, "_Equipped$") then
			part:Destroy()
		end
	end

	activeAttachments[weaponModel] = nil
	activeGripStates[weaponModel] = nil
	weaponOwnership[weaponModel] = nil

	weaponModel:SetAttribute("ActiveCustomMuzzle", nil)
end

function AttachmentManager.GetActiveAttachments(weaponModel)
	return activeAttachments[weaponModel] or {}
end

function AttachmentManager.HasAttachment(weaponModel, category)
	return activeAttachments[weaponModel] and activeAttachments[weaponModel][category] ~= nil
end

function AttachmentManager.DebugMuzzleState(weaponModel)
	local base = weaponModel:FindFirstChild("Grip") or weaponModel:FindFirstChild("Base")
	if not base then
		return
	end

	local originalMuzzle = base:FindFirstChild("Muzzle", true)
	local hasMuzzleAttachment = AttachmentManager.HasAttachment(weaponModel, "Muzzle")
	local customMuzzleName = weaponModel:GetAttribute("ActiveCustomMuzzle")
	local activeMuzzle = AttachmentManager.GetActiveMuzzle(weaponModel)
end

function AttachmentManager.HasLaserAttachment(weaponModel)
	if not activeAttachments[weaponModel] then return false end
	for _, data in pairs(activeAttachments[weaponModel]) do
		if data.config.EnableLaser then return true end
	end
	return false
end

function AttachmentManager.HasFlashlightAttachment(weaponModel)
	if not activeAttachments[weaponModel] then return false end
	for _, data in pairs(activeAttachments[weaponModel]) do
		if data.config.EnableFlashlight then return true end
	end
	return false
end

local function FindLaserAttachment(root)
	local direct = root:FindFirstChild("Laser")
	if direct and direct:IsA("Attachment") then
		return direct
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant.Name == "Laser" then
			return descendant
		end
	end
	return nil
end

function AttachmentManager.GetLaserSource(weaponModel)
	if not weaponModel then return nil end

	if activeAttachments[weaponModel] then
		for _, data in pairs(activeAttachments[weaponModel]) do
			if data.config.EnableLaser then
				local part = FindLaserAttachment(data.model)
				if part then
					return part
				end
			end
		end
	end

	local grip = weaponModel:FindFirstChild("Grip")
	if grip then
		local gripLaser = grip:FindFirstChild("Laser")
		if gripLaser and gripLaser:IsA("Attachment") then
			return gripLaser
		end
	end

	return FindLaserAttachment(weaponModel)
end

function AttachmentManager.GetFlashlightSource(weaponModel)
	if not weaponModel then return nil end
	local grip = weaponModel:FindFirstChild("Grip")
	if grip and grip:FindFirstChild("Flashlight") then
		return grip.Flashlight
	end
	if activeAttachments[weaponModel] then
		for _, data in pairs(activeAttachments[weaponModel]) do
			if data.config.EnableFlashlight then
				local part = data.model:FindFirstChild("Flashlight", true)
				if part then
					return part
				end
			end
		end
	end
	return weaponModel:FindFirstChild("Flashlight", true)
end

function AttachmentManager.GetFlashlightLights(weaponModel)
	local part = AttachmentManager.GetFlashlightSource(weaponModel)
	if not part then return nil end
	return {
		part  = part,
		inner = part:FindFirstChild("InnerSpotLight"),
		outer = part:FindFirstChild("OuterSpotLight"),
	}
end

return AttachmentManager