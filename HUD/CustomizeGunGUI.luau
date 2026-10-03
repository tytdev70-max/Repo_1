local Players              = game:GetService("Players")
local ReplicatedStorage    = game:GetService("ReplicatedStorage")
local UserInputService     = game:GetService("UserInputService")
local TweenService         = game:GetService("TweenService")
local Lighting             = game:GetService("Lighting")
local RunService           = game:GetService("RunService")
local StarterGui           = game:GetService("StarterGui")
local ContextActionService = game:GetService("ContextActionService")

local player     = Players.LocalPlayer
local playerGui  = player:WaitForChild("PlayerGui")
local assets     = ReplicatedStorage:WaitForChild("SPH_Assets")
local SPH_Events = require(assets.Modules.Core.Networking.SPH_Events)

local CustomizeGunHandler = require(assets.Modules.Weapons.UI.CustomizeGunHandler)

local customizeGUI = playerGui:FindFirstChild("CustomizeGunGUI")
if not customizeGUI then
	local hud = assets:WaitForChild("HUD")
	local gunGUIs = hud:WaitForChild("GunGUIs")
	local customizeGUITemplate = gunGUIs:FindFirstChild("CustomizeGunGUI")
	if not customizeGUITemplate then
		warn("[Customize] CustomizeGunGUI not found in ReplicatedStorage.SPH_Assets.HUD.GunGUIs")
		return
	end
	customizeGUI = customizeGUITemplate:Clone()
	customizeGUI.Parent = playerGui
	customizeGUI.ResetOnSpawn = false
end

local attachmentsFrame  = customizeGUI:WaitForChild("AttachmentsFrame")
local mainDisplayFrame  = customizeGUI:WaitForChild("MainDisplayFrame", 5)
if not mainDisplayFrame then return end

local gunNameLabel  = mainDisplayFrame.content.BlankFrame:WaitForChild("GunName")
local confirmButton = mainDisplayFrame.content:WaitForChild("ConfirmButton")

local paddingFrame       = attachmentsFrame:WaitForChild("Padding")
local attachmentsColumn  = paddingFrame:WaitForChild("AttachmentsColumn")

local hoverSound    = customizeGUI:FindFirstChild("Hover")
local selectSound   = customizeGUI:FindFirstChild("Select")
local deselectSound = customizeGUI:FindFirstChild("Deselect")

local isMenuOpen = false

local setupEvent   = SPH_Events.GetOrCreate("GunEvents", "SetupCustomizeGUI",   "BindableEvent")
local cleanupEvent = SPH_Events.GetOrCreate("GunEvents", "CleanupCustomizeGUI", "BindableEvent")

local currentWeapon              = nil
local mouseBehaviorOverrideConn  = nil
local selectedAttachments        = {}
local activeButtons              = {}
local selectedButtonsByCategory  = {}
local columnButtons              = {}
local originalWalkSpeed          = 9
local weaponCheckConnection      = nil
local humanoidDiedConnection     = nil

local COLUMN_CATEGORIES     = { "Optics", "Underbarrel", "Muzzle", "Stock" }
local ATTACHMENT_CATEGORIES = { Optics = "OpticPart", Underbarrel = "GripPart", Muzzle = "MuzzlePart", Stock = "StockPart" }

local BUTTON_TWEEN_INFO = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_TWEEN_INFO  = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local modules           = assets.Modules
local Attachments = require(modules.Weapons.Attachments.SPHAttachments)
local attachmentsFolder = assets:WaitForChild("GunAttachments")

local previousMouseBehavior    = UserInputService.MouseBehavior
local previousMouseIconEnabled = UserInputService.MouseIconEnabled

local inventoryConnections     = {}
local inventoryWatchConnection = nil
local inventoryEnforceConnection = nil
local guiBlur = Lighting:FindFirstChild("GUIBlur")

local viewportFrame3D = nil
do
	local v3dContainer = mainDisplayFrame:FindFirstChild("3DView")
	if v3dContainer then
		viewportFrame3D = v3dContainer:FindFirstChild("3DVPF")
	end
end

local vp3DGunModel   = nil
local vp3DWorldModel = nil
local vp3DCamera     = nil
local vp3DOrigTrans  = {}
local vp3DCenter     = Vector3.zero
local vp3DRadius     = 5
local vp3DMaxDim     = 2
local vp3DYaw        = -30
local vp3DPitch      = 15
local vp3DIsDragging = false
local vp3DLastInput  = nil
local vp3DInputConns = {}
local vp3DPartCache  = {}
local vp3DMinRadius  = 0
local vp3DMaxRadius  = 0

local function RebuildPartCache()
	vp3DPartCache = {}
	if not vp3DWorldModel then return end
	for _, part in ipairs(vp3DWorldModel:GetDescendants()) do
		if part:IsA("BasePart") and part.Transparency < 1 then
			table.insert(vp3DPartCache, part)
		end
	end
end

local function ComputeDynamicMinRadius()
	if not vp3DWorldModel then return vp3DMinRadius end
	local yaw      = math.rad(vp3DYaw)
	local pitch    = math.rad(math.clamp(vp3DPitch, -80, 80))
	local cosPitch = math.cos(pitch)
	local dx = math.sin(yaw) * cosPitch
	local dy = math.sin(pitch)
	local dz = math.cos(yaw) * cosPitch
	local safeRadius = vp3DMinRadius
	local NEAR_EXPAND = 0.28
	local BUFFER      = 0.04
	for _, part in ipairs(vp3DPartCache) do
		local cf = part.CFrame
		local hs = part.Size * 0.5
		local lo = cf:PointToObjectSpace(Vector3.zero)
		local ld = cf:VectorToObjectSpace(Vector3.new(dx, dy, dz))
		local hx = hs.X + NEAR_EXPAND
		local hy = hs.Y + NEAR_EXPAND
		local hz = hs.Z + NEAR_EXPAND
		local tMin = -math.huge
		local tMax =  math.huge
		local hit  = true
		local ax = ld.X
		if math.abs(ax) < 1e-8 then
			if lo.X < -hx or lo.X > hx then hit = false end
		else
			local inv = 1 / ax
			local t1 = (-hx - lo.X) * inv
			local t2 = ( hx - lo.X) * inv
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tMin then tMin = t1 end
			if t2 < tMax then tMax = t2 end
			if tMin > tMax then hit = false end
		end
		if hit then
			local ay = ld.Y
			if math.abs(ay) < 1e-8 then
				if lo.Y < -hy or lo.Y > hy then hit = false end
			else
				local inv = 1 / ay
				local t1 = (-hy - lo.Y) * inv
				local t2 = ( hy - lo.Y) * inv
				if t1 > t2 then t1, t2 = t2, t1 end
				if t1 > tMin then tMin = t1 end
				if t2 < tMax then tMax = t2 end
				if tMin > tMax then hit = false end
			end
		end
		if hit then
			local az = ld.Z
			if math.abs(az) < 1e-8 then
				if lo.Z < -hz or lo.Z > hz then hit = false end
			else
				local inv = 1 / az
				local t1 = (-hz - lo.Z) * inv
				local t2 = ( hz - lo.Z) * inv
				if t1 > t2 then t1, t2 = t2, t1 end
				if t1 > tMin then tMin = t1 end
				if t2 < tMax then tMax = t2 end
				if tMin > tMax then hit = false end
			end
		end
		if hit and tMax > 0 then
			local needed = tMax + BUFFER
			if needed > safeRadius then safeRadius = needed end
		end
	end
	return safeRadius
end

local function UpdateVP3DCamera()
	if not vp3DCamera or not vp3DCamera.Parent then return end
	local yaw   = math.rad(vp3DYaw)
	local pitch = math.rad(math.clamp(vp3DPitch, -80, 80))
	local dynamicMin      = ComputeDynamicMinRadius()
	local effectiveRadius = math.max(vp3DRadius, dynamicMin)
	local camPos = vp3DCenter + Vector3.new(
		math.sin(yaw) * math.cos(pitch) * effectiveRadius,
		math.sin(pitch) * effectiveRadius,
		math.cos(yaw) * math.cos(pitch) * effectiveRadius
	)
	vp3DCamera.CFrame = CFrame.new(camPos, vp3DCenter)
end

local function Clear3DView()
	for _, conn in ipairs(vp3DInputConns) do conn:Disconnect() end
	vp3DInputConns = {}
	vp3DIsDragging = false
	vp3DLastInput  = nil
	if viewportFrame3D then
		for _, child in ipairs(viewportFrame3D:GetChildren()) do
			if child.Name ~= "title" then
				child:Destroy()
			end
		end
	end
	vp3DGunModel   = nil
	vp3DWorldModel = nil
	vp3DCamera     = nil
	vp3DOrigTrans  = {}
	vp3DPartCache  = {}
end

local function ConnectVP3DInput()
	for _, conn in ipairs(vp3DInputConns) do conn:Disconnect() end
	vp3DInputConns = {}
	if not viewportFrame3D then return end
	table.insert(vp3DInputConns, viewportFrame3D.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			vp3DIsDragging = true
			vp3DLastInput  = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	table.insert(vp3DInputConns, UserInputService.InputChanged:Connect(function(input)
		if not vp3DIsDragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch then
			local pos = Vector2.new(input.Position.X, input.Position.Y)
			if vp3DLastInput then
				local delta = pos - vp3DLastInput
				vp3DYaw   = vp3DYaw - delta.X * 0.5
				vp3DPitch = math.clamp(vp3DPitch + delta.Y * 0.5, -80, 80)
				UpdateVP3DCamera()
			end
			vp3DLastInput = pos
		end
	end))
	table.insert(vp3DInputConns, UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			vp3DIsDragging = false
			vp3DLastInput  = nil
		end
	end))
	table.insert(vp3DInputConns, viewportFrame3D.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			vp3DRadius = math.clamp(
				vp3DRadius - input.Position.Z * (vp3DMaxDim * 0.15),
				vp3DMinRadius,
				vp3DMaxRadius
			)
			UpdateVP3DCamera()
		end
	end))
end

local function Apply3DViewAttachments()
	if not vp3DGunModel or not vp3DWorldModel then return end
	for _, child in ipairs(vp3DWorldModel:GetChildren()) do
		if child ~= vp3DGunModel then child:Destroy() end
	end
	for part, origTrans in pairs(vp3DOrigTrans) do
		if part and part.Parent then
			part.Transparency = origTrans
		end
	end
	if not attachmentsFolder then return end
	for category, attachmentName in pairs(selectedAttachments) do
		if not attachmentName or attachmentName == "" then continue end
		local config = Attachments:LoadConfig(category, attachmentName)
		if not config then continue end
		local categoryPartName = Attachments:GetSlotPartName(category)
		if not categoryPartName then continue end
		local categoryPart = vp3DGunModel:FindFirstChild(categoryPartName, true)
		if not categoryPart then continue end
		local mountPoint = categoryPart:FindFirstChild(attachmentName)
		if not mountPoint or not mountPoint:IsA("Attachment") then continue end
		local attachmentFolder = Attachments:GetContentFolder(category, attachmentName)
		if not attachmentFolder then continue end
		local rootName = config.RootPart
		if not rootName then
			local fp = attachmentFolder:FindFirstChildOfClass("BasePart")
				or attachmentFolder:FindFirstChildOfClass("MeshPart")
			if fp then rootName = fp.Name end
		end
		if not rootName then continue end
		local originalRoot = attachmentFolder:FindFirstChild(rootName)
		if not originalRoot then continue end
		local mountOffset = config.MountOffset or CFrame.new()
		local rootCFrame  = mountPoint.WorldCFrame * mountOffset
		local container = Instance.new("Model")
		container.Name   = attachmentName .. "_VP"
		container.Parent = vp3DWorldModel
		for _, child in ipairs(attachmentFolder:GetChildren()) do
			if child:IsA("BasePart") or child:IsA("MeshPart") then
				local clone = child:Clone()
				clone.Anchored   = true
				clone.CanCollide = false
				clone.CastShadow = false
				clone.Parent     = container
				if child.Name == rootName then
					clone.CFrame = rootCFrame
				else
					local rel = originalRoot.CFrame:Inverse() * child.CFrame
					clone.CFrame = rootCFrame * rel
				end
			end
		end
		for _, partName in ipairs(config.HideGunParts or {}) do
			local part = vp3DGunModel:FindFirstChild(partName, true)
			if part and part:IsA("BasePart") then
				part.Transparency = config.HideTransparency or 1
			end
		end
	end
	RebuildPartCache()
end

local function Setup3DView(tool)
	Clear3DView()
	if not viewportFrame3D or not tool then return end
	local weaponModels = assets:FindFirstChild("WeaponModels")
	local sourceModel  = weaponModels and weaponModels:FindFirstChild(tool.Name)
	if not sourceModel then return end
	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewportFrame3D
	vp3DWorldModel = worldModel
	local gunClone = sourceModel:Clone()
	gunClone.Parent = worldModel
	local parts = {}
	for _, part in ipairs(gunClone:GetDescendants()) do
		if part:IsA("BasePart") then
			vp3DOrigTrans[part] = part.Transparency
			part.Anchored   = true
			part.CanCollide = false
			part.CastShadow = false
			table.insert(parts, part)
		end
	end
	if #parts == 0 then return end
	local minB = Vector3.new( math.huge,  math.huge,  math.huge)
	local maxB = Vector3.new(-math.huge, -math.huge, -math.huge)
	for _, part in ipairs(parts) do
		local cf = part.CFrame
		local s  = part.Size * 0.5
		for dx = -1, 1, 2 do
			for dy = -1, 1, 2 do
				for dz = -1, 1, 2 do
					local corner = cf * Vector3.new(s.X * dx, s.Y * dy, s.Z * dz)
					minB = Vector3.new(math.min(minB.X, corner.X), math.min(minB.Y, corner.Y), math.min(minB.Z, corner.Z))
					maxB = Vector3.new(math.max(maxB.X, corner.X), math.max(maxB.Y, corner.Y), math.max(maxB.Z, corner.Z))
				end
			end
		end
	end
	local center  = (minB + maxB) / 2
	local extents = maxB - minB
	for _, part in ipairs(parts) do
		local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = part.CFrame:GetComponents()
		part.CFrame = CFrame.new(x - center.X, y - center.Y, z - center.Z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
	end
	vp3DGunModel = gunClone
	vp3DCenter   = Vector3.zero
	vp3DMaxDim   = math.max(extents.X, extents.Y, extents.Z)
	local fov    = 45
	local boundingRadius = extents.Magnitude * 0.5
	vp3DRadius   = boundingRadius / math.tan(math.rad(fov * 0.5))
	vp3DMinRadius = vp3DMaxDim * 0.4
	vp3DMaxRadius = vp3DRadius * 2.5
	vp3DYaw      = -30
	vp3DPitch    = 15
	local cam    = Instance.new("Camera")
	cam.FieldOfView = fov
	viewportFrame3D.CurrentCamera = cam
	cam.Parent  = viewportFrame3D
	vp3DCamera  = cam
	RebuildPartCache()
	UpdateVP3DCamera()
	ConnectVP3DInput()
	Apply3DViewAttachments()
	UpdateVP3DCamera()
end

function hasWeaponEquipped()
	local character = player.Character
	if not character then return false end
	local equippedTool = character:FindFirstChildWhichIsA("Tool")
	return equippedTool and equippedTool:FindFirstChild("SPH_Weapon") ~= nil
end

local function getEquippedWeapon()
	local character = player.Character
	if not character then return nil end
	local equippedTool = character:FindFirstChildWhichIsA("Tool")
	if equippedTool and equippedTool:FindFirstChild("SPH_Weapon") then
		return equippedTool
	end
	return nil
end

local function disablePrompt()
	CustomizeGunHandler.SetPromptsEnabled(false)
end

local function enablePrompt()
	CustomizeGunHandler.SetPromptsEnabled(true)
end

local BLOCKED_MOVEMENT_KEYS = {
	Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
	Enum.KeyCode.Space, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift,
	Enum.KeyCode.LeftControl, Enum.KeyCode.RightControl,
	Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four,
	Enum.KeyCode.Five, Enum.KeyCode.Six, Enum.KeyCode.Seven, Enum.KeyCode.Eight,
	Enum.KeyCode.Nine, Enum.KeyCode.Zero,
	Enum.KeyCode.ButtonL2, Enum.KeyCode.ButtonR2, Enum.KeyCode.ButtonX,
	Enum.KeyCode.ButtonY, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown,
	Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight, Enum.KeyCode.Thumbstick1,
}

local function blockInputs()
	local ok, err = pcall(function()
		ContextActionService:BindAction(
			"BlockAllInputs",
			function() return Enum.ContextActionResult.Sink end,
			false,
			unpack(BLOCKED_MOVEMENT_KEYS)
		)
	end)
	if not ok then
		warn("[CustomizeGunGUI] Failed to bind BlockAllInputs:", err)
	end

	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			originalWalkSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = 0
		end
	end
end

local function unblockInputs()
	pcall(function()
		ContextActionService:UnbindAction("BlockAllInputs")
	end)
	local character = player.Character
	if character then
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = originalWalkSpeed
		end
	end
end

local function findInventoryGuis()
	local found = {}
	for _, child in ipairs(playerGui:GetChildren()) do
		if child:IsA("ScreenGui") and string.find(child.Name:lower(), "inventory") then
			table.insert(found, child)
		end
	end
	return found
end

local function enforceGuiDisabled(gui)
	if not gui or not gui:IsA("ScreenGui") then return end
	pcall(function() gui.Enabled = false end)
	if inventoryConnections[gui] then
		pcall(function() inventoryConnections[gui]:Disconnect() end)
	end
	inventoryConnections[gui] = gui.Changed:Connect(function(prop)
		if prop == "Enabled" and gui.Enabled then
			pcall(function() gui.Enabled = false end)
		end
	end)
end

local function startInventoryEnforce()
	for gui, conn in pairs(inventoryConnections) do
		pcall(function() conn:Disconnect() end)
	end
	inventoryConnections = {}
	for _, gui in ipairs(findInventoryGuis()) do
		enforceGuiDisabled(gui)
	end
	if inventoryWatchConnection then
		pcall(function() inventoryWatchConnection:Disconnect() end)
	end
	inventoryWatchConnection = playerGui.ChildAdded:Connect(function(child)
		if child:IsA("ScreenGui") and string.find(child.Name:lower(), "inventory") then
			enforceGuiDisabled(child)
		end
	end)
	if inventoryEnforceConnection then
		pcall(function() inventoryEnforceConnection:Disconnect() end)
	end
	inventoryEnforceConnection = RunService.Heartbeat:Connect(function()
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false) end)
		for _, gui in ipairs(playerGui:GetChildren()) do
			if gui:IsA("ScreenGui") and (gui.Name:lower():find("inventory") or gui.Name:lower():find("hotbar")) then
				if gui.Enabled then gui.Enabled = false end
			end
		end
		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.WalkSpeed ~= 0 then
				humanoid.WalkSpeed = 0
			end
		end
	end)
end

local function stopInventoryEnforce()
	for gui, conn in pairs(inventoryConnections) do
		pcall(function() conn:Disconnect() end)
	end
	inventoryConnections = {}
	if inventoryWatchConnection then
		pcall(function() inventoryWatchConnection:Disconnect() end)
		inventoryWatchConnection = nil
	end
	if inventoryEnforceConnection then
		pcall(function() inventoryEnforceConnection:Disconnect() end)
		inventoryEnforceConnection = nil
	end
	task.wait(0.1)
	local character = player.Character
	if character then
		local backpackDisabled     = character:GetAttribute("BackpackDisabled")
		local isUnequippingForArms = character:GetAttribute("IsUnequippingForArmHiding")
		if not backpackDisabled and not isUnequippingForArms then
			pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true) end)
			for _, gui in ipairs(findInventoryGuis()) do
				pcall(function() gui.Enabled = true end)
			end
		end
	else
		pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true) end)
		for _, gui in ipairs(findInventoryGuis()) do
			pcall(function() gui.Enabled = true end)
		end
	end
end

local function applyAttachment(attachmentName, category)
	selectedAttachments[category] = attachmentName
end

local function removeAttachment(category)
	selectedAttachments[category] = nil
end

local function scaleFromCenter(originalSize, scaleFactor)
	return UDim2.new(
		originalSize.X.Scale * scaleFactor,
		originalSize.X.Offset * scaleFactor,
		originalSize.Y.Scale * scaleFactor,
		originalSize.Y.Offset * scaleFactor
	)
end

local function deselectVisual(button, playSound)
	local data = activeButtons[button]
	if not data then return end
	if data.tween then pcall(function() data.tween:Cancel() end) data.tween = nil end
	local target = data.buttonFrame
	if not target then return end
	local restoreSize = data.originalSize or target.Size
	local restorePos  = data.originalPosition or target.Position
	local tween = TweenService:Create(target, BUTTON_TWEEN_INFO, {
		BackgroundColor3 = Color3.fromRGB(50, 50, 50),
		BackgroundTransparency = 0.3,
		Size = restoreSize,
		Position = restorePos,
		AnchorPoint = Vector2.new(0, 0),
	})
	data.tween = tween
	tween:Play()
	tween.Completed:Connect(function()
		if data.tween == tween then data.tween = nil end
	end)
	if playSound ~= false and deselectSound then
		deselectSound:Play()
	end
end

local function selectVisual(button, playSound)
	local data = activeButtons[button]
	if not data then return end
	if data.tween then pcall(function() data.tween:Cancel() end) data.tween = nil end
	local target = data.buttonFrame
	if not target then return end
	if not data.originalSize then data.originalSize = target.Size end
	if not data.originalPosition then data.originalPosition = target.Position end
	local scaleFactor = 1.03
	local scaled = scaleFromCenter(data.originalSize, scaleFactor)
	local centerX = data.originalPosition.X.Scale + data.originalSize.X.Scale / 2
	local centerXOffset = data.originalPosition.X.Offset + data.originalSize.X.Offset / 2
	local centerY = data.originalPosition.Y.Scale + data.originalSize.Y.Scale / 2
	local centerYOffset = data.originalPosition.Y.Offset + data.originalSize.Y.Offset / 2
	target.AnchorPoint = Vector2.new(0.5, 0.5)
	target.Position = UDim2.new(centerX, centerXOffset, centerY, centerYOffset)
	local tween = TweenService:Create(target, BUTTON_TWEEN_INFO, { BackgroundColor3 = Color3.fromRGB(100, 200, 100), BackgroundTransparency = 0, Size = scaled })
	data.tween = tween
	tween:Play()
	tween.Completed:Connect(function()
		if data.tween == tween then data.tween = nil end
	end)
	if playSound ~= false and selectSound then
		selectSound:Play()
	end
end

local function playHoverEffect(button)
	local data = activeButtons[button]
	if not data or not data.buttonFrame then return end
	if hoverSound then hoverSound:Play() end
	local isSelected = false
	for _, selectedButton in pairs(selectedButtonsByCategory) do
		if selectedButton == button then
			isSelected = true
			break
		end
	end
	if isSelected then return end
	local target = data.buttonFrame
	local currentSize = target.Size
	local hoverScale = 1.01
	local scaledSize = scaleFromCenter(data.originalSize or currentSize, hoverScale)
	local tween = TweenService:Create(target, HOVER_TWEEN_INFO, { Size = scaledSize })
	tween:Play()
	tween.Completed:Connect(function()
		if activeButtons[button] then
			local returnTween = TweenService:Create(target, HOVER_TWEEN_INFO, { Size = data.originalSize or currentSize })
			returnTween:Play()
		end
	end)
end

local function disableActiveRecursive(obj)
	if obj:IsA("GuiObject") then
		pcall(function()
			obj.Active = false
			if obj:IsA("Frame") or obj:IsA("ScrollingFrame") then
				obj.ClipsDescendants = false
			end
		end)
	end
	local parent = obj.Parent
	if parent and parent ~= customizeGUI and parent:IsA("GuiObject") then
		disableActiveRecursive(parent)
	end
end

local function connectExistingButton(buttonFrame, category, attachmentName)
	disableActiveRecursive(buttonFrame)
	buttonFrame.Active = false
	buttonFrame.ClipsDescendants = false
	local padding = buttonFrame:FindFirstChild("padding")
	if padding then
		padding.Active = false
		if padding:IsA("Frame") then
			padding.ClipsDescendants = false
		end
	end
	local existingClickButton = buttonFrame:FindFirstChild("ClickButton")
	if existingClickButton then
		existingClickButton:Destroy()
	end
	local clickButton = Instance.new("TextButton")
	clickButton.Name = "ClickButton"
	clickButton.Size = UDim2.new(1, 0, 1, 0)
	clickButton.Position = UDim2.new(0, 0, 0, 0)
	clickButton.AnchorPoint = Vector2.new(0, 0)
	clickButton.BackgroundTransparency = 1
	clickButton.Text = ""
	clickButton.TextTransparency = 1
	clickButton.ZIndex = 10000
	clickButton.Active = true
	clickButton.AutoButtonColor = false
	clickButton.Modal = false
	clickButton.Parent = buttonFrame
	activeButtons[clickButton] = {
		category = category,
		attachmentName = attachmentName,
		tween = nil,
		buttonFrame = buttonFrame,
		originalSize = buttonFrame.Size,
		originalPosition = buttonFrame.Position,
	}
	clickButton.MouseEnter:Connect(function()
		playHoverEffect(clickButton)
	end)
	clickButton.MouseButton1Click:Connect(function()
		local buttonCategory = activeButtons[clickButton].category
		if selectedAttachments[buttonCategory] == attachmentName and selectedButtonsByCategory[buttonCategory] == clickButton then
			deselectVisual(clickButton, true)
			removeAttachment(buttonCategory)
			selectedButtonsByCategory[buttonCategory] = nil
		else
			local prevButton = selectedButtonsByCategory[buttonCategory]
			if prevButton and prevButton ~= clickButton and activeButtons[prevButton] then
				deselectVisual(prevButton, false)
			end
			selectVisual(clickButton, true)
			applyAttachment(attachmentName, buttonCategory)
			selectedButtonsByCategory[buttonCategory] = clickButton
		end
		Apply3DViewAttachments()
		UpdateVP3DCamera()
	end)
	return clickButton
end

local function setupColumnWithExistingButtons(column, category, columnIndex)
	column.Active = false
	if column:IsA("Frame") then
		column.ClipsDescendants = false
	end
	local columnHeading = column:FindFirstChild("columnheading")
	local display = column:FindFirstChild("display")
	if not display then
		return
	end
	display.Active = false
	if display:IsA("Frame") then
		display.ClipsDescendants = false
	end
	local itemsScrollingFrame = display:FindFirstChild("items")
	if not itemsScrollingFrame then
		return
	end
	itemsScrollingFrame.Active = false
	itemsScrollingFrame.ScrollingEnabled = true
	itemsScrollingFrame.ClipsDescendants = false
	if columnHeading then
		local title = columnHeading:FindFirstChild("title")
		if title then title.Text = category end
	end
	columnButtons[columnIndex] = {}
	local buttonCount = 0
	local attachmentPartName = ATTACHMENT_CATEGORIES[category]
	local categoryPart = nil
	if currentWeapon and attachmentPartName then
		local camera = workspace.CurrentCamera
		local weaponRig = camera:FindFirstChild("WeaponRig")
		if weaponRig then
			local weaponFolder = weaponRig:FindFirstChild("Weapon")
			if weaponFolder then
				local gunModel = weaponFolder:FindFirstChildWhichIsA("Model")
				if gunModel then
					categoryPart = gunModel:FindFirstChild(attachmentPartName, true)
				end
			end
		end
	end
	for _, child in ipairs(itemsScrollingFrame:GetChildren()) do
		if child:IsA("Frame") and child.Name ~= "UIListLayout" then
			local padding = child:FindFirstChild("padding")
			if padding then
				local itemName = padding:FindFirstChild("itemname")
				local attachmentName = nil
				if itemName then
					if itemName.Text ~= "" then
						attachmentName = itemName.Text
					end
				else
					for _, paddingChild in ipairs(padding:GetChildren()) do
						if paddingChild:IsA("TextLabel") and paddingChild.Name ~= "UIAspectRatioConstraint" then
							attachmentName = paddingChild.Name
							break
						end
					end
				end
				if attachmentName and attachmentName ~= "" then
					local hasAttachmentPoint = false
					if categoryPart then
						local attachmentPoint = categoryPart:FindFirstChild(attachmentName)
						if attachmentPoint and attachmentPoint:IsA("Attachment") then
							hasAttachmentPoint = true
						end
					end
					if hasAttachmentPoint then
						child.Visible = true
						local button = connectExistingButton(child, category, attachmentName)
						if button then
							table.insert(columnButtons[columnIndex], button)
							buttonCount = buttonCount + 1
						end
					else
						child.Visible = false
					end
				end
			end
		end
	end
end

local function setupAllColumns()
	local columns = {}
	for _, child in ipairs(attachmentsColumn:GetChildren()) do
		if child:IsA("Frame") and child.Name == "column" then
			table.insert(columns, child)
		end
	end
	for i, column in ipairs(columns) do
		local category = COLUMN_CATEGORIES[i]
		if category then
			setupColumnWithExistingButtons(column, category, i)
		end
	end
end

local function cleanupActiveButtons()
	for button, data in pairs(activeButtons) do
		if data.tween then pcall(function() data.tween:Cancel() end) data.tween = nil end
		pcall(function()
			if data.buttonFrame then
				data.buttonFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
				data.buttonFrame.BackgroundTransparency = 0.3
				data.buttonFrame.Size = data.originalSize or data.buttonFrame.Size
				data.buttonFrame.Position = data.originalPosition or data.buttonFrame.Position
				data.buttonFrame.AnchorPoint = Vector2.new(0, 0)
			end
		end)
	end
	activeButtons = {}
	selectedButtonsByCategory = {}
	columnButtons = {}
end

local function forceCloseAndReset()
	customizeGUI.Enabled = false
	customizeGUI.DisplayOrder = 0
	isMenuOpen = false
	unblockInputs()
	enablePrompt()
	stopInventoryEnforce()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
	cleanupEvent:Fire()
	pcall(function()
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		UserInputService.MouseIconEnabled = true
	end)
end

function openCustomizeGUI()
	local equippedTool = getEquippedWeapon()
	if not equippedTool then return end

	if isMenuOpen then
		forceCloseAndReset()
		task.wait(0.2)
	end

	isMenuOpen = true
	customizeGUI.Enabled = true
	customizeGUI.DisplayOrder = 1000
	disablePrompt()

	local ok, err = pcall(function()
		task.wait()

		local stillEquipped  = getEquippedWeapon()
		local sameTool       = stillEquipped ~= nil and stillEquipped == equippedTool
		local compatibleTool = stillEquipped ~= nil and stillEquipped:FindFirstChild("SPH_Weapon") ~= nil

		if not stillEquipped or (not sameTool and not compatibleTool) then
			customizeGUI.Enabled = false
			customizeGUI.DisplayOrder = 0
			isMenuOpen = false
			enablePrompt()
			return
		end

		blockInputs()
		setupEvent:Fire(stillEquipped)
	end)

	if not ok then
		warn("[CustomizeGunGUI] openCustomizeGUI failed, resetting state:", err)
		customizeGUI.Enabled = false
		customizeGUI.DisplayOrder = 0
		isMenuOpen = false
		pcall(unblockInputs)
		enablePrompt()
	end
end

local function closeCustomizeGUI()
	customizeGUI.Enabled = false
	customizeGUI.DisplayOrder = 0
	isMenuOpen = false
	unblockInputs()
	enablePrompt()
	local character = player.Character
	local shouldRestoreInventory = true
	if character then
		local backpackDisabled     = character:GetAttribute("BackpackDisabled")
		local isUnequippingForArms = character:GetAttribute("IsUnequippingForArmHiding")
		if backpackDisabled or isUnequippingForArms then
			shouldRestoreInventory = false
		end
	end
	if shouldRestoreInventory then
		stopInventoryEnforce()
	else
		for gui, conn in pairs(inventoryConnections) do
			pcall(function() conn:Disconnect() end)
		end
		inventoryConnections = {}
		if inventoryWatchConnection then
			pcall(function() inventoryWatchConnection:Disconnect() end)
			inventoryWatchConnection = nil
		end
		if inventoryEnforceConnection then
			pcall(function() inventoryEnforceConnection:Disconnect() end)
			inventoryEnforceConnection = nil
		end
	end
	cleanupEvent:Fire()
end

CustomizeGunHandler.BindCallbacks(
	function() openCustomizeGUI() end,
	function() return isMenuOpen end
)

setupEvent.Event:Connect(function(tool)
	if not tool or not tool:IsA("Tool") then return end
	cleanupActiveButtons()
	currentWeapon = tool
	selectedAttachments = {}
	gunNameLabel.Text = tool.Name
	setupAllColumns()
	for category, attachmentName in pairs(Attachments:GetLoadout(tool)) do
		applyAttachment(attachmentName, category)
		for button, data in pairs(activeButtons) do
			if data.attachmentName == attachmentName and data.category == category then
				selectedButtonsByCategory[category] = button
				selectVisual(button, false)
			end
		end
	end
	Setup3DView(tool)
end)

cleanupEvent.Event:Connect(function()
	if isMenuOpen then
		customizeGUI.Enabled = false
		customizeGUI.DisplayOrder = 0
		isMenuOpen = false
		unblockInputs()
		enablePrompt()
	end
	Clear3DView()
	currentWeapon = nil
	selectedAttachments = {}
	cleanupActiveButtons()
	stopInventoryEnforce()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, true)
	end)
	if guiBlur then pcall(function() guiBlur.Enabled = false end) end
end)

local getSelectedFunction = SPH_Events.GetOrCreate("GunEvents", "GetSelectedAttachments", "BindableFunction")
getSelectedFunction.OnInvoke = function() return selectedAttachments end

local events = assets:WaitForChild("Events")
local gunEvents = events:WaitForChild("GunEvents")
local applyEvent = gunEvents:WaitForChild("ApplyWeaponAttachments")

confirmButton.MouseButton1Click:Connect(function()
	if not currentWeapon then return end
	local attachments = {}
	for category, attachmentName in pairs(selectedAttachments) do
		if attachmentName and attachmentName ~= "" then attachments[category] = attachmentName end
	end
	local previewFolder = currentWeapon:FindFirstChild("PreviewAttachments")
	if previewFolder then previewFolder:Destroy() end
	-- Optimistic local copy (the server rebuilds and replicates the authoritative one).
	Attachments:SetLoadout(currentWeapon, Attachments:SanitizeLoadout(attachments, currentWeapon))
	applyEvent:FireServer(currentWeapon, attachments)
	local character = player.Character
	local shouldRestoreInventory = true
	if character then
		local backpackDisabled     = character:GetAttribute("BackpackDisabled")
		local isUnequippingForArms = character:GetAttribute("IsUnequippingForArmHiding")
		if backpackDisabled or isUnequippingForArms then
			shouldRestoreInventory = false
		end
	end
	if shouldRestoreInventory then
		stopInventoryEnforce()
		pcall(function()
			UserInputService.MouseIconEnabled = previousMouseIconEnabled
		end)
	else
		for gui, conn in pairs(inventoryConnections) do
			pcall(function() conn:Disconnect() end)
		end
		inventoryConnections = {}
		if inventoryWatchConnection then
			pcall(function() inventoryWatchConnection:Disconnect() end)
			inventoryWatchConnection = nil
		end
		if inventoryEnforceConnection then
			pcall(function() inventoryEnforceConnection:Disconnect() end)
			inventoryEnforceConnection = nil
		end
		pcall(function()
			UserInputService.MouseIconEnabled = false
		end)
	end
	task.wait(0.15)
	customizeGUI.Enabled = false
	customizeGUI.DisplayOrder = 0
end)

local function onGuiEnabledChanged()
	if customizeGUI.Enabled then
		previousMouseBehavior    = UserInputService.MouseBehavior
		previousMouseIconEnabled = UserInputService.MouseIconEnabled
		pcall(function()
			UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)
		if mouseBehaviorOverrideConn then pcall(function() mouseBehaviorOverrideConn:Disconnect() end) mouseBehaviorOverrideConn = nil end
		mouseBehaviorOverrideConn = RunService.PreRender:Connect(function()
			pcall(function()
				UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end)
		end)
		startInventoryEnforce()
		if guiBlur then pcall(function() guiBlur.Enabled = true end) end
	else
		if mouseBehaviorOverrideConn then pcall(function() mouseBehaviorOverrideConn:Disconnect() end) mouseBehaviorOverrideConn = nil end
		local character = player.Character
		local shouldRestore = true
		if character then
			local backpackDisabled     = character:GetAttribute("BackpackDisabled")
			local isUnequippingForArms = character:GetAttribute("IsUnequippingForArmHiding")
			if backpackDisabled or isUnequippingForArms then
				shouldRestore = false
			end
		end
		if shouldRestore then
			stopInventoryEnforce()
			pcall(function()
				UserInputService.MouseBehavior    = previousMouseBehavior
				UserInputService.MouseIconEnabled = previousMouseIconEnabled
			end)
		else
			for gui, conn in pairs(inventoryConnections) do
				pcall(function() conn:Disconnect() end)
			end
			inventoryConnections = {}
			if inventoryWatchConnection then
				pcall(function() inventoryWatchConnection:Disconnect() end)
				inventoryWatchConnection = nil
			end
			if inventoryEnforceConnection then
				pcall(function() inventoryEnforceConnection:Disconnect() end)
				inventoryEnforceConnection = nil
			end
			pcall(function()
				UserInputService.MouseIconEnabled = false
			end)
		end
		enablePrompt()
		if guiBlur then pcall(function() guiBlur.Enabled = false end) end
	end
end

customizeGUI:GetPropertyChangedSignal("Enabled"):Connect(onGuiEnabledChanged)

local guiStateWatcher = customizeGUI:GetPropertyChangedSignal("Enabled"):Connect(function()
	if not customizeGUI.Enabled and isMenuOpen then
		closeCustomizeGUI()
	end
end)

local function onCharacterRemoving(character)
	if humanoidDiedConnection then
		humanoidDiedConnection:Disconnect()
		humanoidDiedConnection = nil
	end
	forceCloseAndReset()
end

local function onCharacterAdded(character)
	forceCloseAndReset()
	task.wait(0.5)
	isMenuOpen = false
	customizeGUI.Enabled = false
	customizeGUI.DisplayOrder = 0
	unblockInputs()
	CustomizeGunHandler.Refresh()
	character.ChildAdded:Connect(function(child)
		if child:IsA("Tool") then CustomizeGunHandler.Refresh() end
	end)
	character.ChildRemoved:Connect(function(child)
		if child:IsA("Tool") then CustomizeGunHandler.Refresh() end
	end)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		if humanoidDiedConnection then
			humanoidDiedConnection:Disconnect()
			humanoidDiedConnection = nil
		end
		humanoidDiedConnection = humanoid.Died:Connect(function()
			if isMenuOpen then forceCloseAndReset() end
		end)
	end
end

if player.Character then
	onCharacterAdded(player.Character)
end
player.CharacterAdded:Connect(onCharacterAdded)
player.CharacterRemoving:Connect(onCharacterRemoving)

local content = mainDisplayFrame:FindFirstChild("content")
if content then
	local closeButton = content:FindFirstChild("CloseButton")
	if closeButton and closeButton:IsA("GuiButton") then
		closeButton.MouseButton1Click:Connect(function()
			closeCustomizeGUI()
		end)
	end
end

CustomizeGunHandler.Refresh()