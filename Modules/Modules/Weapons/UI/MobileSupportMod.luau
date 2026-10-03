local MobileSupportMod = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local sphAssets = ReplicatedStorage:WaitForChild("SPH_Assets")
local Modules = script:FindFirstAncestor("Modules")
local ubglSystem = require(sphAssets.Modules.Weapons.Attachments.UBGLHandlerMod)

local mobileButtonsGui  = nil
local mobilePickupGui   = nil
local mobileMovementGui = nil

local _vars
local Attachments = require(Modules.Weapons.Attachments.SPHAttachments)
local _playerGui, _HandleInput
local _character, _humanoid, _player, _Network, _assets
local _proxPromptService, _defaultFOV

function MobileSupportMod.Init(deps)
	_vars = require(Modules.Weapons.Core.WeaponState).get()
	_playerGui         = deps.playerGui
	_HandleInput       = deps.HandleInput
	_character         = deps.character
	_humanoid          = deps.humanoid
	_player            = deps.player
	_Network           = deps.Network
	_assets            = deps.assets
	_proxPromptService = deps.proxPromptService
	_defaultFOV        = deps.defaultFOV
end

local DEFAULT_ICON_SCALE = 0.62

local function MakeBtn(parent, name, label, px, py, diameter, r, g, b, iconId, iconScale, iconRotation)
	local btn = Instance.new("ImageButton")
	btn.Name                  = name
	btn.Size                  = UDim2.new(0, diameter, 0, diameter)
	btn.Position              = UDim2.fromScale(px, py)
	btn.AnchorPoint           = Vector2.new(0.5, 0.5)
	btn.BackgroundColor3      = Color3.fromRGB(r, g, b)
	btn.BackgroundTransparency = 0.30
	btn.AutoButtonColor       = false
	btn.Parent                = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = btn

	local stroke = Instance.new("UIStroke")
	stroke.Thickness    = 1.5
	stroke.Color        = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.55
	stroke.Parent = btn

	local hasIcon = iconId ~= nil and iconId ~= ""

	if hasIcon then
		local scale = iconScale or DEFAULT_ICON_SCALE

		local icon = Instance.new("ImageLabel")
		icon.Name                  = "Icon"
		icon.Size                  = UDim2.fromScale(scale, scale)
		icon.Position              = UDim2.fromScale(0.5, 0.5)
		icon.AnchorPoint           = Vector2.new(0.5, 0.5)
		icon.BackgroundTransparency = 1
		icon.Image                 = iconId
		icon.ScaleType             = Enum.ScaleType.Fit
		icon.Rotation              = iconRotation or 0
		icon.Parent                = btn
	end

	local lbl = Instance.new("TextLabel")
	lbl.Name                  = "Label"
	lbl.Size                  = UDim2.fromScale(1, 1)
	lbl.BackgroundTransparency = 1
	lbl.Text                  = label
	lbl.TextColor3            = Color3.new(1, 1, 1)
	lbl.TextScaled            = true
	lbl.Font                  = Enum.Font.GothamBold
	lbl.TextStrokeTransparency = 0.4
	lbl.TextStrokeColor3      = Color3.new(0, 0, 0)
	lbl.Visible               = not hasIcon
	lbl.Parent = btn

	local pad = Instance.new("UIPadding")
	pad.PaddingTop    = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft   = UDim.new(0.12, 0)
	pad.PaddingRight  = UDim.new(0.12, 0)
	pad.Parent = lbl

	btn.MouseButton1Down:Connect(function() btn.BackgroundTransparency = 0.05 end)
	btn.MouseButton1Up:Connect(function()   btn.BackgroundTransparency = 0.30 end)

	return btn
end

local function HasLaserAttachment()
	local gm = _vars.gunModel
	if not gm then return false end
	return (gm.Grip:FindFirstChild("Laser") ~= nil)
		or Attachments:AnyActiveFlag(gm, "EnableLaser")
end

local function HasFlashlightAttachment()
	local gm = _vars.gunModel
	if not gm then return false end
	return Attachments:GetFlashlightSource(gm) ~= nil
end

function MobileSupportMod.UpdateMobileButtonVisibility()
	if not mobileButtonsGui then return end

	local ws = _vars.wepStats
	local isGrenade = ws and ws.weaponType == "Grenade"
	local hasUBGL = ws and ws.UBGL and ws.UBGL.Enabled and not isGrenade
	local ubglActive = ubglSystem.IsActive()

	local laserBtn     = mobileButtonsGui:FindFirstChild("LaserButton")
	local lightBtn     = mobileButtonsGui:FindFirstChild("FlashlightButton")
	local reloadBtn    = mobileButtonsGui:FindFirstChild("ReloadButton")
	local chamberBtn   = mobileButtonsGui:FindFirstChild("ChamberButton")
	local modeBtn      = mobileButtonsGui:FindFirstChild("FireModeButton")
	local inspectBtn   = mobileButtonsGui:FindFirstChild("InspectButton")
	local dropBtn      = mobileButtonsGui:FindFirstChild("DropButton")
	local aimBtn       = mobileButtonsGui:FindFirstChild("AimButton")
	local ubglBtn      = mobileButtonsGui:FindFirstChild("UBGLButton")
	local holdUpBtn    = mobileButtonsGui:FindFirstChild("HoldUpButton")
	local patrolBtn    = mobileButtonsGui:FindFirstChild("PatrolButton")
	local holdDownBtn  = mobileButtonsGui:FindFirstChild("HoldDownButton")

	local hasInspectAnim  = (ws ~= nil) and (ws.InspectAnim ~= nil or ws.emptyInspect ~= nil)
	local hasChamberAnim  = (ws ~= nil) and (ws.boltChamber ~= nil or ws.boltClose ~= nil)
	local hasReloadAnim   = (ws ~= nil) and (ws.reloadAnim ~= nil or ws.emptyReloadAnim ~= nil)
	local hasHoldUpAnim   = (ws ~= nil) and ws.holdUpAnim ~= nil
	local hasPatrolAnim   = (ws ~= nil) and ws.patrolAnim ~= nil
	local hasHoldDownAnim = (ws ~= nil) and ws.holdDownAnim ~= nil

	if laserBtn   then laserBtn.Visible   = HasLaserAttachment() and not ubglActive end
	if lightBtn   then lightBtn.Visible   = HasFlashlightAttachment() and not ubglActive end
	if chamberBtn then chamberBtn.Visible = hasChamberAnim and not isGrenade and not ubglActive end
	if modeBtn    then modeBtn.Visible    = not isGrenade and not ubglActive end
	if inspectBtn then inspectBtn.Visible = hasInspectAnim and not ubglActive end

	if reloadBtn  then reloadBtn.Visible  = hasReloadAnim and not isGrenade end
	if dropBtn    then dropBtn.Visible    = not isGrenade end

	if holdUpBtn   then holdUpBtn.Visible   = hasHoldUpAnim and not isGrenade and not ubglActive end
	if patrolBtn   then patrolBtn.Visible   = hasPatrolAnim and not isGrenade and not ubglActive end
	if holdDownBtn then holdDownBtn.Visible = hasHoldDownAnim and not isGrenade and not ubglActive end

	if ubglBtn then
		ubglBtn.Visible = hasUBGL == true
		local ubglLbl = ubglBtn:FindFirstChildWhichIsA("TextLabel")
		if ubglLbl then
			ubglLbl.Text = ubglActive and "RIFLE" or "UBGL"
		end
	end

	if aimBtn then
		aimBtn.Visible = not ubglActive
		local aimLbl = aimBtn:FindFirstChildWhichIsA("TextLabel")
		if aimLbl then
			aimLbl.Text = isGrenade and "LOW" or "AIM"
		end
	end
end

function MobileSupportMod.UpdateLPVOButtonVisibility()
	if not mobileButtonsGui then return end
	local uis     = game:GetService("UserInputService")
	local zoomIn  = mobileButtonsGui:FindFirstChild("ZoomInButton")
	local zoomOut = mobileButtonsGui:FindFirstChild("ZoomOutButton")
	local ws       = _vars.wepStats
	local hasRange = ws and ws.aimFovMin and ws.aimFovMax and ws.aimFovMin < ws.aimFovMax
	local show     = (_vars.aiming) and hasRange and uis.TouchEnabled and not ubglSystem.IsActive()
	if zoomIn  then zoomIn.Visible  = show == true end
	if zoomOut then zoomOut.Visible = show == true end
end

function MobileSupportMod.SetupMovementButtons(playerGui, character, assets, Network)
	local uis = game:GetService("UserInputService")
	if not uis.TouchEnabled then return end
	local config = require(assets.GameConfig)
	if not config.mobileButtons then return end

	if mobileMovementGui then mobileMovementGui:Destroy(); mobileMovementGui = nil end

	local gui = Instance.new("ScreenGui")
	gui.Name           = "SPH_MobileMovement"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent         = playerGui
	mobileMovementGui  = gui

	local raiseBtn  = MakeBtn(gui, "RaiseStance",     "▲ STAND",  0.15, 0.3,  64,  90, 130, 200, "rbxassetid://147441244", 0.6)
	local leanLeft  = MakeBtn(gui, "LeanLeftButton",  "◀ LEAN",   0.05, 0.5,  64,  90, 130, 200, "rbxassetid://6821119862", 0.6, -90)
	local leanRight = MakeBtn(gui, "LeanRightButton", "LEAN ▶",   0.25, 0.5,  64,  90, 130, 200, "rbxassetid://6821119862", 0.6,  90)
	local lowerBtn  = MakeBtn(gui, "LowerStance",     "▼ CROUCH", 0.15, 0.5,  64,  90, 130, 200, "rbxassetid://147441790", 0.6)
	local sprint    = MakeBtn(gui, "SprintButton",    "SPRINT",   0.25, 0.82,  76,  50, 190,  80, "rbxassetid://89190879948216", 1)

	local tvms = assets.Events.GunEvents:FindFirstChild("ToggleViewmodelSprint")
	local sprintActive = false

	sprint.MouseButton1Down:Connect(function()
		sprintActive = not sprintActive
		sprint.BackgroundTransparency = sprintActive and 0.05 or 0.30
		character:SetAttribute("HoldingSprint", sprintActive)
		character:SetAttribute("Sprinting",     sprintActive)
		if tvms then tvms:Fire(sprintActive) end
	end)

	character:GetAttributeChangedSignal("Sprinting"):Connect(function()
		sprintActive = character:GetAttribute("Sprinting") == true
		sprint.BackgroundTransparency = sprintActive and 0.05 or 0.30
	end)

	local movementEvents = assets.Events:WaitForChild("MovementEvents")

	local function getOrMakeEvent(name)
		local e = movementEvents:FindFirstChild(name)
		if not e then
			e = Instance.new("BindableEvent")
			e.Name   = name
			e.Parent = movementEvents
		end
		return e
	end

	lowerBtn.MouseButton1Down:Connect(function() getOrMakeEvent("StanceLower"):Fire() end)
	raiseBtn.MouseButton1Down:Connect(function() getOrMakeEvent("StanceRaise"):Fire() end)

	local leanState  = 0

	local function applyLean()
		character:SetAttribute("LeanDirection", leanState)
		Network.packets.PlayerLeanRequest.send(leanState)
		leanLeft.BackgroundTransparency  = leanState == -1 and 0.05 or 0.30
		leanRight.BackgroundTransparency = leanState ==  1 and 0.05 or 0.30
	end

	leanLeft.MouseButton1Down:Connect(function()
		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		leanState = leanState == -1 and 0 or -1
		applyLean()
	end)
	leanRight.MouseButton1Down:Connect(function()
		local humanoid = character:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then return end
		leanState = leanState ==  1 and 0 or  1
		applyLean()
	end)
end

function MobileSupportMod.SetupMobileButtons(aimFOVTargetRef)
	local uis = game:GetService("UserInputService")
	if not uis.TouchEnabled then return end
	local config = require(_assets.GameConfig)
	if not config.mobileButtons then return end

	if mobileButtonsGui then mobileButtonsGui:Destroy(); mobileButtonsGui = nil end

	local gui = Instance.new("ScreenGui")
	gui.Name           = "SPH_MobileButtons"
	gui.ResetOnSpawn   = false
	gui.IgnoreGuiInset = true
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent         = _playerGui
	mobileButtonsGui   = gui

	local fire    = MakeBtn(gui, "FireButton",        "FIRE",   0.88, 0.60,  70, 220,  50,  50, "rbxassetid://98208902277642", 0.85)
	local aim     = MakeBtn(gui, "AimButton",         "AIM",    0.79, 0.84,  58,  50, 100, 220, "rbxassetid://3575766791", 0.6)
	local reload  = MakeBtn(gui, "ReloadButton",      "RELOAD", 0.88, 0.35,  54,  40, 170,  60, "rbxassetid://6723921202", 0.70)
	local chamber = MakeBtn(gui, "ChamberButton",     "BOLT",   0.76, 0.60,  48, 160, 110,  40, nil)
	local mode    = MakeBtn(gui, "FireModeButton",    "MODE",   0.67, 0.77,  48, 130,  60, 180, nil)
	local inspect = MakeBtn(gui, "InspectButton",     "INSP",   0.67, 0.525, 46,  80,  80, 100, nil)
	local drop    = MakeBtn(gui, "DropButton",        "DROP",   0.76, 0.40,  44, 180,  60,  60, nil)
	local ubglBtn = MakeBtn(gui, "UBGLButton",        "UBGL",   0.60, 0.35,  48, 230, 150,  20, nil)

	local holdUp   = MakeBtn(gui, "HoldUpButton",   "UP",   0.43, 0.13, 44, 200,  30,  30, nil)
	local patrol   = MakeBtn(gui, "PatrolButton",   "PTRL", 0.50, 0.13, 44, 200,  30,  30, nil)
	local holdDown = MakeBtn(gui, "HoldDownButton", "DOWN", 0.57, 0.13, 44, 200,  30,  30, nil)

	local laser   = MakeBtn(gui, "LaserButton",       "LZR",    0.84, 0.13,  44, 200,  30,  30, nil)
	local light   = MakeBtn(gui, "FlashlightButton",  "LGHT",   0.91, 0.13,  44, 200, 170,  30, nil)
	local zoomIn  = MakeBtn(gui, "ZoomInButton",      "+",      0.67, 0.13,  44,  60, 120, 200, nil)
	local zoomOut = MakeBtn(gui, "ZoomOutButton",     "−",      0.74, 0.13,  44,  60, 120, 200, nil)

	local IS = Enum.UserInputState

	fire.MouseButton1Down:Connect(function() _HandleInput("SPH_Trigger", IS.Begin, nil) end)
	fire.MouseButton1Up:Connect(function()   _HandleInput("SPH_Trigger", IS.End,   nil) end)

	aim.MouseButton1Down:Connect(function()
		_HandleInput("SPH_HoldAim", IS.Begin, nil)
		task.defer(function()
			aim.BackgroundTransparency = (_vars.aiming) and 0.05 or 0.30
		end)
	end)

	reload.MouseButton1Down:Connect(function() _HandleInput("SPH_Reload", IS.Begin, nil) end)
	reload.MouseButton1Up:Connect(function()   _HandleInput("SPH_Reload", IS.End,   nil) end)

	chamber.MouseButton1Down:Connect(function() _HandleInput("SPH_Chamber", IS.Begin, nil) end)

	mode.MouseButton1Down:Connect(function() _HandleInput("SPH_SwitchFireMode", IS.Begin, nil) end)
	mode.MouseButton1Up:Connect(function()   _HandleInput("SPH_SwitchFireMode", IS.End,   nil) end)

	inspect.MouseButton1Down:Connect(function() _HandleInput("SPH_Inspect", IS.Begin, nil) end)

	drop.MouseButton1Down:Connect(function() _HandleInput("SPH_DropGun", IS.Begin, nil) end)

	ubglBtn.MouseButton1Down:Connect(function() _HandleInput("SPH_ToggleUBGL", IS.Begin, nil) end)
	
	holdUp.MouseButton1Down:Connect(function()   _HandleInput("SPH_HoldUp",     IS.Begin, nil) end)
	patrol.MouseButton1Down:Connect(function()   _HandleInput("SPH_HoldPatrol", IS.Begin, nil) end)
	holdDown.MouseButton1Down:Connect(function() _HandleInput("SPH_HoldDown",   IS.Begin, nil) end)

	laser.MouseButton1Down:Connect(function() _HandleInput("SPH_ToggleLaser",      IS.Begin, nil) end)
	light.MouseButton1Down:Connect(function() _HandleInput("SPH_ToggleFlashlight", IS.Begin, nil) end)

	local zoomInActive, zoomOutActive = false, false

	zoomIn.MouseButton1Down:Connect(function()
		zoomInActive = true
		task.spawn(function()
			while zoomInActive and mobileButtonsGui and mobileButtonsGui.Parent do
				local ws = _vars.wepStats
				if _vars.aiming and ws and ws.aimFovMin and ws.aimFovMax then
					_vars.lastZoomChangeTime = tick()
					_vars.isArmReverting     = false
					aimFOVTargetRef.value = math.clamp(
						aimFOVTargetRef.value - 4, ws.aimFovMin, ws.aimFovMax)
				end
				task.wait(0.05)
			end
		end)
	end)
	zoomIn.MouseButton1Up:Connect(function()  zoomInActive  = false end)

	zoomOut.MouseButton1Down:Connect(function()
		zoomOutActive = true
		task.spawn(function()
			while zoomOutActive and mobileButtonsGui and mobileButtonsGui.Parent do
				local ws = _vars.wepStats
				if _vars.aiming and ws and ws.aimFovMin and ws.aimFovMax then
					_vars.lastZoomChangeTime = tick()
					_vars.isArmReverting     = false
					aimFOVTargetRef.value = math.clamp(
						aimFOVTargetRef.value + 4, ws.aimFovMin, ws.aimFovMax)
				end
				task.wait(0.05)
			end
		end)
	end)
	zoomOut.MouseButton1Up:Connect(function() zoomOutActive = false end)

	laser.Visible   = false
	light.Visible   = false
	zoomIn.Visible  = false
	zoomOut.Visible = false
	ubglBtn.Visible = false
	holdUp.Visible    = false
	patrol.Visible    = false
	holdDown.Visible  = false

	MobileSupportMod.UpdateMobileButtonVisibility()
	MobileSupportMod.UpdateLPVOButtonVisibility()
end

function MobileSupportMod.DestroyMobileButtons()
	if mobileButtonsGui  then mobileButtonsGui:Destroy();  mobileButtonsGui  = nil end
end

function MobileSupportMod.DestroyMovementButtons()
	if mobileMovementGui then mobileMovementGui:Destroy(); mobileMovementGui = nil end
end

return MobileSupportMod