local DoorController = {}
DoorController.__index = DoorController

local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SPHAssets = ReplicatedStorage:WaitForChild("SPH_Assets")
local ModulesFolder = SPHAssets:WaitForChild("Modules")
local DoorSystemFolder = ModulesFolder:WaitForChild("Misc"):WaitForChild("DoorSystem")

local DoorConfig = require(DoorSystemFolder:WaitForChild("DoorConfig"))
local DoorState = require(DoorSystemFolder:WaitForChild("DoorState"))
local States = DoorState.States

local EventsFolder = SPHAssets:WaitForChild("Events")
local DoorEventsFolder = EventsFolder:WaitForChild("DoorEvents")
local CameraShakeEvent = DoorEventsFolder:WaitForChild("DoorCameraShakeEvent")

local AnimationsFolder = SPHAssets:WaitForChild("Animations")
local MovementAnimationsFolder = AnimationsFolder:FindFirstChild("Movement")
if not MovementAnimationsFolder then
	warn("[DoorController] Animations.Movement folder not found - did you forget to create ReplicatedStorage.SPH_Assets.Animations.Movement?")
end

local DoorKickAnimation = (MovementAnimationsFolder and MovementAnimationsFolder:FindFirstChild("DoorKick"))
	or AnimationsFolder:FindFirstChild("DoorKick")

if not DoorKickAnimation then
	warn("[DoorController] 'DoorKick' animation could not be found in Animations.Movement or Animations directly.")
elseif not MovementAnimationsFolder or not MovementAnimationsFolder:FindFirstChild("DoorKick") then
	warn("[DoorController] 'DoorKick' found in Animations directly, not in Animations.Movement - did you forget to move it into the folder?")
end

local function findDescendant(root, name)
	local direct = root:FindFirstChild(name)
	if direct then return direct end
	return root:FindFirstChild(name, true)
end

local function waitForDescendant(root, name, timeoutSeconds)
	local found = findDescendant(root, name)
	if found then return found end

	local start = os.clock()
	repeat
		task.wait(0.1)
		found = findDescendant(root, name)
	until found or (os.clock() - start) > timeoutSeconds

	return found
end

local function isBoolTrue(instance)
	if instance == nil then
		return true
	end
	if instance:IsA("BoolValue") then
		return instance.Value
	end
	return true
end

local function anchorDescendants(root)
	for _, inst in ipairs(root:GetDescendants()) do
		if inst:IsA("BasePart") then
			inst.Anchored = true
		end
	end
end

function DoorController.new(doorModel)
	assert(doorModel:IsA("Model"), "doorModel must be a Model")

	local timeout = DoorConfig.PartLookupTimeout

	local doorSubModel = waitForDescendant(doorModel, "DoorModel", timeout)
	assert(doorSubModel, "Expected a 'DoorModel' inside " .. doorModel:GetFullName())

	local main = waitForDescendant(doorSubModel, "Main", timeout)
	local hinge1 = waitForDescendant(doorSubModel, "Hinge1", timeout)
	local hinge2 = waitForDescendant(doorSubModel, "Hinge2", timeout)
	local health = main and waitForDescendant(main, "Health", timeout)

	assert(main and hinge1 and hinge2 and health,
		"Door hierarchy is missing an expected part under " .. doorModel:GetFullName())

	local mainDoor = findDescendant(doorSubModel, "MainDoor") or main

	local kickPrompt = waitForDescendant(doorSubModel, "Kickable", timeout)
	local peekPrompt = waitForDescendant(doorSubModel, "Peekable", timeout)
	local openPrompt = waitForDescendant(doorSubModel, "Openable", timeout)
	assert(kickPrompt and peekPrompt and openPrompt,
		"Door hierarchy is missing a Kickable/Peekable/Openable prompt holder under " .. doorModel:GetFullName())

	kickPrompt = kickPrompt:WaitForChild("ProximityPrompt")
	peekPrompt = peekPrompt:WaitForChild("ProximityPrompt")
	openPrompt = openPrompt:WaitForChild("ProximityPrompt")

	anchorDescendants(doorModel)

	local self = setmetatable({
		_model = doorModel,
		_doorSubModel = doorSubModel,
		_main = main,
		_mainDoor = mainDoor,
		_hinge1 = hinge1,
		_hinge2 = hinge2,
		_health = health,

		_kickCapable = isBoolTrue(findDescendant(main, "Kickable")),
		_peekCapable = isBoolTrue(findDescendant(main, "Peekable")),

		_kickPrompt = kickPrompt,
		_peekPrompt = peekPrompt,
		_openPrompt = openPrompt,

		_sounds = {
			CreakOpen = findDescendant(main, "CreakOpen"),
			CreakClose = findDescendant(main, "CreakClose"),
			DoorOpen = findDescendant(main, "DoorOpen"),
			DoorClose = findDescendant(main, "DoorClose"),
			DoorKick = findDescendant(main, "DoorKick"),
			KickWhoosh = findDescendant(main, "KickWhoosh"),
			DoorLocked = findDescendant(main, "DoorLocked"),
			DoorReallyKicked = findDescendant(main, "DoorReallyKicked"),
			Kicks = {
				findDescendant(main, "Kick1"),
				findDescendant(main, "Kick2"),
				findDescendant(main, "Kick3"),
			},
		},

		_closedCFrame = doorSubModel:GetPivot(),
		_state = nil,
		_busy = false,
		_kickReady = true,
		_autoCloseThread = nil,
		_connections = {},
	}, DoorController)

	self:_resolveKickedDownParts()
	self:_resolveMovingParts()
	self:_resolveWeldedParts()
	self:_applySoundConfig()
	self:_applyMassOverride()
	self:_setState(health.Value > 0 and States.Locked or States.Closed)

	table.insert(self._connections, health:GetPropertyChangedSignal("Value"):Connect(function()
		self:_onHealthChanged()
	end))
	table.insert(self._connections, self._kickPrompt.Triggered:Connect(function(player)
		self:_onKickTriggered(player)
	end))
	table.insert(self._connections, self._peekPrompt.Triggered:Connect(function(player)
		self:_onPeekOrUnpeekTriggered(player)
	end))
	table.insert(self._connections, self._openPrompt.Triggered:Connect(function(player)
		self:_onOpenOrCloseTriggered(player)
	end))

	return self
end

function DoorController:_applySoundConfig()
	local function apply(sound)
		if sound then
			sound.Volume = DoorConfig.SoundVolume
			sound.PlaybackSpeed = DoorConfig.SoundPitch
		end
	end
	apply(self._sounds.CreakOpen)
	apply(self._sounds.CreakClose)
	apply(self._sounds.DoorOpen)
	apply(self._sounds.DoorClose)
	apply(self._sounds.DoorKick)
	apply(self._sounds.KickWhoosh)
	apply(self._sounds.DoorLocked)
	apply(self._sounds.DoorReallyKicked)
	for _, s in ipairs(self._sounds.Kicks) do
		apply(s)
	end
end

function DoorController:_applyMassOverride()
	if DoorConfig.DoorMassOverride and self._mainDoor:IsA("BasePart") then
		self._mainDoor.CustomPhysicalProperties = PhysicalProperties.new(
			DoorConfig.DoorMassOverride, 0.3, 0.5, 1, 1
		)
	end
end

function DoorController:_resolvePartList(configTable)
	local list = {}
	if not configTable then return list end
	for partName, enabled in pairs(configTable) do
		if enabled then
			local part = findDescendant(self._doorSubModel, partName)
			if part and part:IsA("BasePart") then
				table.insert(list, part)
			else
				warn(("[DoorController] Part '%s' not found (or not a BasePart) under %s")
					:format(partName, self._doorSubModel:GetFullName()))
			end
		end
	end
	return list
end

function DoorController:_resolveKickedDownParts()
	self._kickedDownUnanchorParts = self:_resolvePartList(DoorConfig.KickedDownUnanchorParts)
end

function DoorController:_resolveMovingParts()
	self._movingParts = self:_resolvePartList(DoorConfig.MovingParts)
	assert(#self._movingParts > 0,
		"DoorConfig.MovingParts resolved to zero parts for " .. self._doorSubModel:GetFullName())

	local hingeCFrame = self:_getHingeWorldCFrame()
	self._partClosedOffsets = {}
	for _, part in ipairs(self._movingParts) do
		self._partClosedOffsets[part] = hingeCFrame:ToObjectSpace(part.CFrame)
	end
end

function DoorController:_resolveWeldedParts()
	local weldedParts = self:_resolvePartList(DoorConfig.WeldedParts)

	for _, part in ipairs(weldedParts) do
		for _, joint in ipairs(part:GetJoints()) do
			joint:Destroy()
		end

		part.Anchored = false

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = self._main
		weld.Part1 = part
		weld.Parent = self._main
	end
end

function DoorController:_getHingeWorldCFrame()
	local hingePos = (self._hinge1.Position + self._hinge2.Position) / 2
	local pivotPos = self._closedCFrame.Position
	return CFrame.new(hingePos.X, pivotPos.Y, hingePos.Z)
end

function DoorController:_targetPartCFrame(part, angleDegrees)
	local hingeCFrame = self:_getHingeWorldCFrame()
	return hingeCFrame * CFrame.Angles(0, math.rad(angleDegrees), 0) * self._partClosedOffsets[part]
end

function DoorController:_tweenTo(angleDegrees, duration, style, direction)
	local tweenInfo = TweenInfo.new(duration, style, direction)
	local lastTween

	for _, part in ipairs(self._movingParts) do
		local tween = TweenService:Create(part, tweenInfo, {
			CFrame = self:_targetPartCFrame(part, angleDegrees),
		})
		tween:Play()
		lastTween = tween
	end

	return lastTween
end

function DoorController:_getSideSign(player)
	local character = player and player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if not hrp then
		return 1
	end

	local doorCFrame = self._mainDoor.CFrame
	local flatOffset = hrp.Position - doorCFrame.Position
	flatOffset = Vector3.new(flatOffset.X, 0, flatOffset.Z)
	if flatOffset.Magnitude < 1e-3 then
		return 1
	end

	local dot = doorCFrame.LookVector:Dot(flatOffset.Unit)
	local sign = (dot >= 0) and -1 or 1
	return sign
end

function DoorController:_playSound(sound)
	if sound then sound:Play() end
end

function DoorController:_playKickAnimation(player)
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local track = animator:LoadAnimation(DoorKickAnimation)
	track:Play()
	track.Stopped:Once(function()
		track:Destroy()
	end)
end

function DoorController:_playRandomKickSound()
	local pool = {}
	for _, s in ipairs(self._sounds.Kicks) do
		if s then table.insert(pool, s) end
	end
	if #pool > 0 then
		self:_playSound(pool[math.random(1, #pool)])
	end
end

function DoorController:_unanchorPart(part)
	for _, joint in ipairs(part:GetJoints()) do
		joint:Destroy()
	end
	part.Anchored = false
	part.CanCollide = true
end

function DoorController:_launchKickParts(sign, stage)
	if not stage.BreakParts or #stage.BreakParts == 0 then return end

	local awayDir = self._mainDoor.CFrame.LookVector * sign

	for _, partName in ipairs(stage.BreakParts) do
		local part = findDescendant(self._doorSubModel, partName)
		if part and part:IsA("BasePart") then
			self:_unanchorPart(part)

			part.AssemblyLinearVelocity = (awayDir * stage.LinearImpulse)
				+ Vector3.new(0, stage.UpwardBias, 0)
			part.AssemblyAngularVelocity = Vector3.new(
				(math.random() * 2 - 1) * stage.AngularImpulse,
				(math.random() * 2 - 1) * stage.AngularImpulse,
				(math.random() * 2 - 1) * stage.AngularImpulse
			)

			if stage.CleanupDelay > 0 then
				Debris:AddItem(part, stage.CleanupDelay)
			end
		else
			warn(("[DoorController] BreakParts entry '%s' not found (or not a BasePart) under %s")
				:format(partName, self._doorSubModel:GetFullName()))
		end
	end
end

function DoorController:_breakDown()
	for _, part in ipairs(self._kickedDownUnanchorParts) do
		self:_unanchorPart(part)
		if DoorConfig.KickPartCleanupDelay > 0 then
			Debris:AddItem(part, DoorConfig.KickPartCleanupDelay)
		end
	end

	self:_playSound(self._sounds.DoorReallyKicked)

	for _, prompt in ipairs({ self._kickPrompt, self._peekPrompt, self._openPrompt }) do
		local holder = prompt.Parent
		if prompt.Parent then
			prompt:Destroy()
		end
		if holder and holder.Parent then
			holder:Destroy()
		end
	end

	self._state = States.Broken
end

function DoorController:_setState(newState)
	self._state = newState
	self:_refreshPrompts()
end

function DoorController:_refreshPrompts()
	local texts = DoorConfig.PromptTexts
	local state = self._state

	self._kickPrompt.Enabled = (state == States.Locked or state == States.Closed) and self._kickCapable
	self._kickPrompt.ActionText = texts.Kick

	local peekVisible = false
	if (state == States.Locked or state == States.Closed) and self._peekCapable then
		peekVisible = true
		self._peekPrompt.ActionText = texts.Peek
	elseif state == States.Peeked then
		peekVisible = true
		self._peekPrompt.ActionText = texts.Unpeek
	end
	self._peekPrompt.Enabled = peekVisible

	local openVisible = false
	if state == States.Peeked then
		openVisible = true
		self._openPrompt.ActionText = texts.Open
	elseif state == States.Opened then
		openVisible = true
		self._openPrompt.ActionText = texts.Close
	end
	self._openPrompt.Enabled = openVisible

	for _, prompt in ipairs({ self._kickPrompt, self._peekPrompt, self._openPrompt }) do
		prompt.MaxActivationDistance = DoorConfig.PromptMaxDistance
		prompt.HoldDuration = DoorConfig.PromptHoldDuration
		prompt.ObjectText = DoorConfig.PromptObjectText
	end
end

function DoorController:_onHealthChanged()
	if self._state == States.Broken then return end
	if self._state == States.Locked or self._state == States.Closed then
		self:_setState(self._health.Value > 0 and States.Locked or States.Closed)
	end
end

function DoorController:_onKickTriggered(player)
	if self._busy or not self._kickReady then return end
	if not DoorState.CanFire(self._state, "Kick") then return end

	self._busy = true
	self._kickReady = false

	local stage = DoorConfig.KickDefaults
	local willBreakDown = self._health.Value <= 1

	self:_playSound(self._sounds.KickWhoosh)
	self:_playKickAnimation(player)
	task.delay(DoorConfig.KickWhooshLeadTime, function()
		if not willBreakDown then
			self:_playSound(self._sounds[stage.Sound])
			if stage.PlayImpactVariant then
				self:_playRandomKickSound()
			end
		end
	end)

	local sign = self:_getSideSign(player)

	local baseAngle = willBreakDown and stage.BreakDownAngle or stage.Angle
	local baseDuration = willBreakDown and stage.BreakDownDuration or stage.Duration

	local kickAngle = baseAngle * sign
	local kickDuration = math.max(0.05, baseDuration - (DoorConfig.PhysicsDamping * 0.2))

	local outTween = self:_tweenTo(kickAngle, kickDuration, stage.TweenStyle, stage.TweenDirection)

	if stage.ShakeEnabled then
		CameraShakeEvent:FireClient(player, stage.ShakePreset, stage.ShakeImpulse)
	end
	self:_launchKickParts(sign, stage)

	outTween.Completed:Wait()

	self._health.Value = math.max(0, self._health.Value - 1)

	if self._health.Value <= 0 then
		self:_breakDown()
		self._busy = false
		return
	end

	self:_tweenTo(0, stage.ReturnDuration, DoorConfig.TweenStyle, DoorConfig.TweenDirection)
	self._busy = false

	task.delay(DoorConfig.KickCooldown, function()
		self._kickReady = true
	end)
end

function DoorController:_onPeekOrUnpeekTriggered(player)
	if self._busy then return end

	if self._state == States.Locked then
		self:_playSound(self._sounds.DoorLocked)
		return
	end

	if DoorState.CanFire(self._state, "Peek") then
		self:_peek(player)
	elseif DoorState.CanFire(self._state, "Unpeek") then
		self:_unpeek()
	end
end

function DoorController:_peek(player)
	self._busy = true
	local sign = self:_getSideSign(player)
	self:_playSound(self._sounds.CreakOpen)
	local tween = self:_tweenTo(DoorConfig.PeekAngle * sign, DoorConfig.PeekSpeed, DoorConfig.TweenStyle, DoorConfig.TweenDirection)
	tween.Completed:Wait()
	self:_setState(States.Peeked)
	self._busy = false
end

function DoorController:_unpeek()
	self._busy = true
	self:_playSound(self._sounds.CreakClose)
	local tween = self:_tweenTo(0, DoorConfig.CloseSpeed, DoorConfig.TweenStyle, DoorConfig.TweenDirection)
	tween.Completed:Wait()
	self:_setState(self._health.Value > 0 and States.Locked or States.Closed)
	self._busy = false
end

function DoorController:_onOpenOrCloseTriggered(player)
	if self._busy then return end

	if self._state == States.Locked then
		self:_playSound(self._sounds.DoorLocked)
		return
	end

	if DoorState.CanFire(self._state, "Open") then
		self:_open(player)
	elseif DoorState.CanFire(self._state, "Close") then
		self:_close()
	end
end

function DoorController:_open(player)
	self._busy = true
	self:_cancelAutoClose()

	local sign = self:_getSideSign(player)
	self:_playSound(self._sounds.DoorOpen or self._sounds.CreakOpen)
	local tween = self:_tweenTo(DoorConfig.OpenAngle * sign, DoorConfig.OpenSpeed, DoorConfig.TweenStyle, DoorConfig.TweenDirection)
	tween.Completed:Wait()
	self:_setState(States.Opened)
	self._busy = false

	if DoorConfig.AutoCloseDelay > 0 then
		self._autoCloseThread = task.delay(DoorConfig.AutoCloseDelay, function()
			if self._state == States.Opened and not self._busy then
				self:_close()
			end
		end)
	end
end

function DoorController:_close()
	self._busy = true
	self:_cancelAutoClose()

	self:_playSound(self._sounds.DoorClose or self._sounds.CreakClose)
	local tween = self:_tweenTo(0, DoorConfig.CloseSpeed, DoorConfig.TweenStyle, DoorConfig.TweenDirection)
	tween.Completed:Wait()
	self:_setState(self._health.Value > 0 and States.Locked or States.Closed)
	self._busy = false
end

function DoorController:_cancelAutoClose()
	if self._autoCloseThread then
		task.cancel(self._autoCloseThread)
		self._autoCloseThread = nil
	end
end

function DoorController:Destroy()
	self:_cancelAutoClose()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

return DoorController