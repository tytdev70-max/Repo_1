--!nonstrict
-- GunsmithTest
-- Test Loadout: a player tries a build in a test area without applying it.
--
--   start  the player gets a temporary copy of the equipped gun with the build (the real
--          gun stays in the Backpack, unchanged), is moved to the test area, and the copy
--          is equipped.
--   stop   the copy is removed, the player goes back to where they were and the real gun
--          is equipped again (the client then reopens the menu with the same picks).
--
-- A test also ends when the player dies, leaves, loses the copy, or the time limit
-- (GunsmithTestSettings.maxDuration) runs out.
--
-- Remote: GunEvents.GunsmithTest (RemoteFunction)
--   ("start", tool, loadout) -> { ok = true } | { ok = false, error = code }
--   ("stop")                 -> { ok = true } | { ok = false, error = code }
--   error codes: disabled, no_zone, busy, no_weapon, dead, rate_limited, bad_request, not_testing
-- Player attributes (read by the client):
--   GunsmithTesting  true while testing
--   GunsmithTestEnd  why the last test ended: returned, timeout, died, left, lost
-- The temporary gun carries the attribute GunsmithTestGun: it can't be dropped (it is
-- destroyed instead), can't be customized, and is ignored by loadout presets.

local ServiceRefs = require(script.Parent.ServiceRefs)
local AssetRefs = require(script.Parent.AssetRefs)
local GunSetupSystem = require(script.Parent.GunSetupSystem)

local players = ServiceRefs.players
local modules = AssetRefs.modules
local Attachments = AssetRefs.Attachments
local Settings = require(modules.Weapons.Gunsmith.GunsmithTestSettings)
local SPH_Events = require(modules.Core.Networking.SPH_Events)

local TEST_GUN_ATTRIBUTE = "GunsmithTestGun"
local ATTR_TESTING = "GunsmithTesting"
local ATTR_END = "GunsmithTestEnd"

local GunsmithTest = {}
GunsmithTest.TEST_GUN_ATTRIBUTE = TEST_GUN_ATTRIBUTE

type Test = {
	realTool: Tool,
	testGun: Tool,
	character: Model,
	returnCFrame: CFrame,
	connections: { RBXScriptConnection },
	finishing: boolean,
}

local tests: { [Player]: Test } = {}
local lastStart: { [Player]: number } = {}

function GunsmithTest.IsTestGun(tool: Instance?): boolean
	return tool ~= nil and tool:GetAttribute(TEST_GUN_ATTRIBUTE) == true
end

function GunsmithTest.IsTesting(player: Player): boolean
	return tests[player] ~= nil
end

local function fail(code: string)
	return { ok = false, error = code }
end

local function aliveHumanoid(character: Model?): Humanoid?
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return humanoid
	end
	return nil
end

-- Where to put the player: on top of the zone part (or a random part of a zone model).
local function arrivalCFrame(): CFrame?
	local zone = workspace:FindFirstChild(Settings.zoneName or "GunsmithTestZone", true)
	if not zone then
		return nil
	end
	local part = nil
	if zone:IsA("BasePart") then
		part = zone
	else
		local parts = {}
		for _, descendant in ipairs(zone:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
		if #parts > 0 then
			part = parts[math.random(1, #parts)]
		end
	end
	if not part then
		return nil
	end
	local height = part.Size.Y / 2 + (Settings.arrivalHeight or 3)
	return part.CFrame * CFrame.new(0, height, 0)
end

local function finish(player: Player, reason: string)
	local test = tests[player]
	if not test or test.finishing then
		return
	end
	test.finishing = true
	for _, connection in ipairs(test.connections) do
		connection:Disconnect()
	end

	if test.testGun.Parent then
		test.testGun:Destroy()
	end
	local character = player.Character
	local humanoid = if character == test.character then aliveHumanoid(character) else nil
	if humanoid and reason ~= "left" then
		character:PivotTo(test.returnCFrame)
		task.wait() -- let the client finish unequipping the test gun
		local backpack = player:FindFirstChildOfClass("Backpack")
		if test.realTool.Parent == backpack and aliveHumanoid(character) then
			humanoid:EquipTool(test.realTool)
		end
	end

	tests[player] = nil
	if player.Parent then
		player:SetAttribute(ATTR_END, reason)
		player:SetAttribute(ATTR_TESTING, nil)
	end
end

local function start(player: Player, tool: any, rawLoadout: any)
	if not Settings.enabled then
		return fail("disabled")
	end
	if typeof(tool) ~= "Instance" or not tool:IsA("Tool") or type(rawLoadout) ~= "table" then
		return fail("bad_request")
	end
	if tests[player] then
		return fail("busy")
	end
	local now = os.clock()
	if lastStart[player] and now - lastStart[player] < (Settings.cooldown or 2) then
		return fail("rate_limited")
	end
	local character = player.Character
	local humanoid = aliveHumanoid(character)
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not root then
		return fail("dead")
	end
	-- only the gun the player is holding, and never a test gun
	if tool.Parent ~= character or not tool:FindFirstChild("SPH_Weapon") or GunsmithTest.IsTestGun(tool) then
		return fail("no_weapon")
	end
	local backpack = player:FindFirstChildOfClass("Backpack")
	if not backpack then
		return fail("dead")
	end
	local arrival = arrivalCFrame()
	if not arrival then
		return fail("no_zone")
	end
	lastStart[player] = now

	-- the same validation as ApplyWeaponAttachments
	local loadout = Attachments:SanitizeLoadout(rawLoadout, tool)

	local testGun = tool:Clone()
	testGun:SetAttribute(TEST_GUN_ATTRIBUTE, true)
	testGun:SetAttribute("AppliedPreset", nil) -- presets: not a carrier,
	testGun:SetAttribute("AppliedPresetOwner", nil)
	testGun:SetAttribute("PresetAutoChecked", true) -- and never auto-applied
	testGun.CanBeDropped = false
	if Settings.refillAmmo ~= false then
		local ammo = testGun:FindFirstChild("Ammo")
		if ammo then
			ammo:Destroy() -- SetupGun recreates it full
		end
	end
	local statsModule = testGun.SPH_Weapon:FindFirstChild("WeaponStats")
	if statsModule then
		local ok, stats = pcall(require, statsModule)
		if ok and type(stats) == "table" then
			GunSetupSystem.SetupGun(testGun, stats)
		end
	end
	Attachments:SetLoadout(testGun, loadout) -- mounted by EquipGun / the client on equip

	local test: Test = {
		realTool = tool,
		testGun = testGun,
		character = character,
		returnCFrame = root.CFrame,
		connections = {},
		finishing = false,
	}
	tests[player] = test
	player:SetAttribute(ATTR_END, nil)
	player:SetAttribute(ATTR_TESTING, true)

	humanoid:UnequipTools()
	testGun.Parent = backpack
	humanoid:EquipTool(testGun)
	character:PivotTo(arrival)

	local function track(connection)
		table.insert(test.connections, connection)
	end
	track(humanoid.Died:Connect(function()
		finish(player, "died")
	end))
	track(character.AncestryChanged:Connect(function()
		if not character:IsDescendantOf(workspace) then
			finish(player, "died")
		end
	end))
	-- the copy must stay with the player (Backpack or character)
	track(testGun.AncestryChanged:Connect(function()
		local parent = testGun.Parent
		if parent ~= player.Character and parent ~= player:FindFirstChildOfClass("Backpack") then
			task.defer(function()
				if tests[player] == test then
					finish(player, "lost")
				end
			end)
		end
	end))
	if type(Settings.maxDuration) == "number" and Settings.maxDuration > 0 then
		task.delay(Settings.maxDuration, function()
			if tests[player] == test then
				finish(player, "timeout")
			end
		end)
	end
	return { ok = true }
end

function GunsmithTest.init()
	local remote = SPH_Events.GetOrCreate("GunEvents", "GunsmithTest", "RemoteFunction") :: RemoteFunction
	remote.OnServerInvoke = function(player, action, first, second)
		if action == "start" then
			local ok, result = pcall(start, player, first, second)
			if not ok then
				warn("[GunsmithTest] start failed:", result)
				if tests[player] then
					task.spawn(finish, player, "lost")
				end
				return fail("bad_request")
			end
			return result
		elseif action == "stop" then
			if not tests[player] then
				return fail("not_testing")
			end
			finish(player, "returned")
			return { ok = true }
		end
		return fail("bad_request")
	end

	players.PlayerRemoving:Connect(function(player)
		if tests[player] then
			finish(player, "left")
		end
		lastStart[player] = nil
	end)
end

return GunsmithTest
