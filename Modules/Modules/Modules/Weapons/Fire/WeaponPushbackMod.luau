--!strict

local Modules = script:FindFirstAncestor("Modules")
local ReplicationThrottle = require(Modules.Core.Networking.ReplicationThrottle)
local vars = require(Modules.Weapons.Core.WeaponState).get()

local SEND_INTERVAL: number = 1 / 15
local SEND_THRESHOLD: number = 0.02

local WeaponPushbackMod = {}

local throttle = ReplicationThrottle.new(SEND_INTERVAL)
local request: any = nil
local lastSent: number? = nil
local localApplied: boolean = false

local function Delta(a: number, b: number): number
	return math.abs(a - b)
end

local function ApplyLocal(amount: number)
	local rig = vars.weaponRig
	if not rig or not rig.Parent then
		localApplied = false
		return
	end

	local baseWeld = rig:FindFirstChild("BaseWeld")
	if not baseWeld or not baseWeld:IsA("JointInstance") then
		localApplied = false
		return
	end

	local restC0 = (vars.wepStats and vars.wepStats.serverOffset) or CFrame.new()

	if amount > 0 then
		baseWeld.C0 = restC0 * CFrame.new(0, 0, amount)
		localApplied = true
	elseif localApplied then
		baseWeld.C0 = restC0
		localApplied = false
	end
end

function WeaponPushbackMod.Init(dependencies: { weaponPushbackRequest: any })
	request = dependencies.weaponPushbackRequest
	WeaponPushbackMod.Reset()
end

function WeaponPushbackMod.Report(pushback: number?)
	if not request then
		return
	end

	local amount = pushback or 0
	if type(amount) ~= "number" or amount ~= amount then
		amount = 0
	end
	amount = math.max(amount, 0)

	ApplyLocal(amount)

	if amount < SEND_THRESHOLD then
		amount = 0
	end

	if lastSent == amount then
		return
	end

	if not throttle:ShouldSend(amount, SEND_THRESHOLD, Delta) then
		return
	end

	lastSent = amount
	request.send(amount)
end

function WeaponPushbackMod.Reset()
	ApplyLocal(0)
	throttle:Reset()
	if request and lastSent ~= nil and lastSent ~= 0 then
		request.send(0)
	end
	lastSent = nil
end

return WeaponPushbackMod