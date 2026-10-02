--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local assets = ReplicatedStorage:WaitForChild("SPH_Assets") :: Folder
local modules = assets:WaitForChild("Modules") :: Folder
local Config = require(assets:WaitForChild("GameConfig")) :: any

local Network = require(modules.Core.Networking.SPH_Network) :: any
local grenadeHandler = require(modules.Misc.Grenades.GrenadeHandler) :: any
local RagdollServerMod = require(modules.Systems.RagdollServerMod) :: any

local killFeedRemote = assets.Events.DeathEvents.KillFeed :: RemoteEvent

local dropCFrame = CFrame.new(0, 1, -3)

local PlayerDeathMod = {}

local function Killfeed(killer: Player?, humanoid: Humanoid?)
	if not killer or not humanoid then return end
	local targetModel = humanoid.Parent
	if not targetModel then return end
	if not targetModel:FindFirstChild("Dead") then
		local deadVal = Instance.new("BoolValue")
		deadVal.Name = "Dead"
		deadVal.Parent = targetModel
		killFeedRemote:FireClient(killer, targetModel)
	end
end

export type DeathContext = {
	Player: Player,
	Character: Model,
	Humanoid: Humanoid,
	Rig: Instance?,
	DeathsValue: IntValue?,
	PendingThrow: any?,
	Shells: Instance,
	SpawnGun: (Tool, CFrame, Player?) -> any,
	MakePickUpAble: (any, any, any) -> any,
}

function PlayerDeathMod.HandleDeath(context: DeathContext): ()
	local newPlayer = context.Player
	local newChar = context.Character
	local humanoid = context.Humanoid
	local newRig = context.Rig
	local deaths = context.DeathsValue
	local pendingThrow = context.PendingThrow
	local shells = context.Shells
	local SpawnGun = context.SpawnGun

	if not newChar:FindFirstChild("HumanoidRootPart") then return end

	if pendingThrow then
		local hrp = newChar.HumanoidRootPart :: BasePart
		local direction = hrp.CFrame.LookVector
		local origin = hrp.Position + Vector3.new(0, 1, 0)
		grenadeHandler.Throw(newPlayer, pendingThrow.wepStats, origin, direction, true)
	end

	newChar.Humanoid:UnequipTools()

	for _, item in ipairs(newChar:GetChildren()) do
		if item:IsA("Tool") then
			item:Destroy()
		end
	end
	for _, item in ipairs(newPlayer.Backpack:GetChildren()) do
		if item:IsA("Tool") then
			item:Destroy()
		end
	end

	local deathRig = newChar:FindFirstChild("WeaponRig")
	if deathRig then
		local deathWeaponModel = deathRig:FindFirstChild("Weapon")
		if deathWeaponModel then
			local deathGun = deathWeaponModel:FindFirstChildWhichIsA("Model")
			if deathGun then
				if pendingThrow and pendingThrow.wepStats and pendingThrow.wepStats.grenade then
					grenadeHandler.DetachAllGrenadeCosmetics(deathGun, pendingThrow.wepStats.grenade, shells)
					if pendingThrow.wepStats.grenade.lowThrow then
						grenadeHandler.DetachAllGrenadeCosmetics(deathGun, pendingThrow.wepStats.grenade.lowThrow, shells)
					end
				end
				deathGun:Destroy()
			end
		end
	end

	task.spawn(function()
		if newRig then
			for _, child in ipairs(newRig:GetChildren()) do
				child:Destroy()
			end
			newRig:Destroy()
		end
	end)

	if Config.leaderboard and deaths then
		deaths.Value += 1
	end

	if Config.dropOnDeath then
		task.spawn(function()
			local equippedTool = newChar:FindFirstChildWhichIsA("Tool")
			if equippedTool and equippedTool:FindFirstChild("SPH_Weapon") then
				SpawnGun(equippedTool, newChar.HumanoidRootPart.CFrame * dropCFrame, newPlayer)
			end
			for _, tool in ipairs(newPlayer.Backpack:GetChildren()) do
				if tool:FindFirstChild("SPH_Weapon") then
					SpawnGun(tool, newChar.HumanoidRootPart.CFrame * dropCFrame, newPlayer)
				end
			end
		end)
	end

	task.spawn(function()
		local deathSounds = assets.Sounds.Death:GetChildren()
		if #deathSounds == 0 then return end
		local newSound = deathSounds[math.random(#deathSounds)]:Clone()
		newSound.Parent = newChar.HumanoidRootPart
		newSound:Play()
		Debris:AddItem(newSound, newSound.TimeLength)
	end)

	task.defer(function()
		if Config.ragdolls then
			RagdollServerMod.HandleDeath(newChar, newPlayer)
		end
		for _, part in ipairs(newChar:GetDescendants()) do
			if part:IsA("BasePart") then
				part.Transparency = 1
				part.CanCollide = false
				part.CanQuery = false
				part.Anchored = true
			elseif part:IsA("Decal") then
				part.Transparency = 1
			elseif part:IsA("SurfaceGui") then
				part:Destroy()
			end
		end
	end)
end

return PlayerDeathMod