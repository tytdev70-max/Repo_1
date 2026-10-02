--!strict

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local FireSelectorMod = {}

type MotorRecord = {
	active: boolean,
	ancestryConn: RBXScriptConnection?,
	fireModeConn: RBXScriptConnection?,
	baseC0: CFrame?,
	pivot: CFrame?,
	tween: Tween?,
}

local SELECTOR_NAME = "FireSelector"
local RETRY_INTERVAL = 0.05

local records: { [Motor6D]: MotorRecord } = {}
local rootConns: { RBXScriptConnection } = {}
local charConns: { [Player]: RBXScriptConnection } = {}
local playerConn: RBXScriptConnection? = nil

local function getFireSelectorConfig(tool: Instance): any
	local marker = tool:FindFirstChild("SPH_Weapon")
	if marker == nil then return nil end
	local statsModule = marker:FindFirstChild("WeaponStats")
	if statsModule == nil or not statsModule:IsA("ModuleScript") then return nil end
	local ok, wepStats = pcall(require, statsModule)
	if not ok or type(wepStats) ~= "table" then return nil end
	local cfg = (wepStats :: any).fireSelector
	if cfg == nil or not cfg.Enabled then return nil end
	return cfg
end

local function resolveOwningTool(motor: Motor6D): Instance?
	local weaponRig = motor:FindFirstAncestor("WeaponRig")
	if weaponRig ~= nil and weaponRig.Parent ~= nil then
		local rigTool = weaponRig.Parent:FindFirstChildWhichIsA("Tool")
		if rigTool ~= nil then return rigTool end
	end
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then return nil end
	local character = localPlayer.Character
	if character == nil then return nil end
	return character:FindFirstChildWhichIsA("Tool")
end

local function applyFireMode(motor: Motor6D, record: MotorRecord, cfg: any, mode: number, instant: boolean)
	local baseC0 = record.baseC0
	if baseC0 == nil then return end
	local positions = cfg.Positions
	local offset = positions ~= nil and positions[mode] or nil
	if offset == nil then return end
	local existing = record.tween
	if existing ~= nil then
		existing:Cancel()
		record.tween = nil
	end

	local pivot = record.pivot or CFrame.new()
	local targetC0 = baseC0 * pivot * offset * pivot:Inverse()

	local tweenTime = instant and 0 or (cfg.TweenTime or 0.12)
	if tweenTime <= 0 then
		motor.C0 = targetC0
		return
	end
	local style = cfg.EasingStyle or Enum.EasingStyle.Quad
	local direction = cfg.EasingDirection or Enum.EasingDirection.Out
	local tween = TweenService:Create(motor, TweenInfo.new(tweenTime, style, direction), { C0 = targetC0 })
	record.tween = tween
	tween.Completed:Connect(function()
		if record.tween == tween then
			record.tween = nil
		end
	end)
	tween:Play()
end

local function releaseMotor(motor: Motor6D)
	local record = records[motor]
	if record == nil then return end
	records[motor] = nil
	record.active = false
	local ancestryConn = record.ancestryConn
	if ancestryConn ~= nil then ancestryConn:Disconnect() end
	local fireModeConn = record.fireModeConn
	if fireModeConn ~= nil then fireModeConn:Disconnect() end
	local tween = record.tween
	if tween ~= nil then tween:Cancel() end
end

local function bindMotor(motor: Motor6D, record: MotorRecord): boolean
	local tool = resolveOwningTool(motor)
	if tool == nil then return false end
	local fireModeValue = tool:FindFirstChild("FireMode")
	if fireModeValue == nil then return false end
	local cfg = getFireSelectorConfig(tool)
	if cfg == nil then return true end
	local valueObject = fireModeValue :: any

	record.baseC0 = motor.C0

	local part1 = motor.Part1
	local part1Pivot = (part1 ~= nil) and part1.PivotOffset or CFrame.new()
	record.pivot = motor.C1:Inverse() * part1Pivot

	applyFireMode(motor, record, cfg, valueObject.Value, true)
	record.fireModeConn = valueObject.Changed:Connect(function()
		if not record.active then return end
		applyFireMode(motor, record, cfg, valueObject.Value, false)
	end)
	return true
end

local function hookMotor(motor: Motor6D)
	if records[motor] ~= nil then return end
	local record: MotorRecord = { active = true }
	records[motor] = record
	record.ancestryConn = motor.AncestryChanged:Connect(function(_, parent)
		if parent == nil then releaseMotor(motor) end
	end)
	task.spawn(function()
		while record.active and motor.Parent ~= nil do
			if bindMotor(motor, record) then return end
			task.wait(RETRY_INTERVAL)
		end
	end)
end

local function scanForMotors(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Name == SELECTOR_NAME then
			hookMotor(descendant)
		end
	end
	table.insert(rootConns, root.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("Motor6D") and descendant.Name == SELECTOR_NAME then
			hookMotor(descendant)
		end
	end))
end

local function watchCharacters(plr: Player, handler: (Model) -> ())
	local existing = charConns[plr]
	if existing ~= nil then existing:Disconnect() end
	charConns[plr] = plr.CharacterAdded:Connect(handler)
end

function FireSelectorMod.Cleanup()
	for motor in pairs(records) do
		releaseMotor(motor)
	end
	for _, conn in ipairs(rootConns) do
		conn:Disconnect()
	end
	table.clear(rootConns)
end

function FireSelectorMod.Init(props: { viewmodelRig: Instance? }?)
	FireSelectorMod.Cleanup()
	local function onCharacterAdded(character: Model)
		local weaponRig = character:FindFirstChild("WeaponRig") or character:WaitForChild("WeaponRig", 10)
		if weaponRig == nil then return end
		scanForMotors(weaponRig)
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		watchCharacters(plr, onCharacterAdded)
		local character = plr.Character
		if character ~= nil then task.spawn(onCharacterAdded, character) end
	end
	if playerConn == nil then
		playerConn = Players.PlayerAdded:Connect(function(plr)
			watchCharacters(plr, onCharacterAdded)
		end)
		Players.PlayerRemoving:Connect(function(plr)
			local conn = charConns[plr]
			if conn == nil then return end
			conn:Disconnect()
			charConns[plr] = nil
		end)
	end
	local viewmodelRig = props ~= nil and props.viewmodelRig or nil
	if viewmodelRig ~= nil then scanForMotors(viewmodelRig) end
end

return FireSelectorMod