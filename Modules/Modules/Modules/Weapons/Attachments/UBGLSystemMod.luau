local module = {}
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local modules = assets.Modules
local Network = require(modules.Core.Networking.SPH_Network)
local NetworkRangeUtil = require(modules.Core.Networking.NetworkRangeUtil)
local explosionMod = require(modules.Effects.Explosions.ExplosionFX)
local config = require(assets.GameConfig)

function module.SetupAmmo(tool, wepStats)
	if not wepStats.UBGL or not wepStats.UBGL.Enabled then return end
	if tool:FindFirstChild("UBGLAmmo") then return end

	local ammoFolder = Instance.new("Folder")
	ammoFolder.Name = "UBGLAmmo"

	local capacity = wepStats.UBGL.Capacity or 1
	local loaded = Instance.new("IntConstrainedValue")
	loaded.Name = "Loaded"
	loaded.MinValue = 0
	loaded.MaxValue = capacity
	loaded.Value = math.clamp(wepStats.UBGL.StartLoaded or 0, 0, capacity)
	loaded.Parent = ammoFolder

	local maxAmmoPool = wepStats.UBGL.MaxAmmoPool or 999999
	local ammoPool = Instance.new("IntConstrainedValue")
	ammoPool.Name = "AmmoPool"
	ammoPool.MinValue = 0
	ammoPool.MaxValue = maxAmmoPool
	ammoPool.Value = math.clamp(wepStats.UBGL.StartAmmoPool or 0, 0, maxAmmoPool)
	ammoPool.Parent = ammoFolder

	ammoFolder.Parent = tool
end

function module.Fire(player, firePointCFrame, direction)
	local character = player.Character
	if not character then return end

	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool or not tool:FindFirstChild("SPH_Weapon") then return end

	local ok, wepStats = pcall(require, tool.SPH_Weapon.WeaponStats)
	if not ok or not wepStats.UBGL or not wepStats.UBGL.Enabled then return end

	local ammo = tool:FindFirstChild("UBGLAmmo")
	if not ammo or ammo.Loaded.Value <= 0 then return end

	ammo.Loaded.Value -= 1

	local hrp = character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local targets = NetworkRangeUtil.GetPlayersInRange(hrp.Position, config.fireEffectDistance, player)
	Network.packets.ReplicateFireUBGL.sendToList({
		Player = player,
		FirePointCFrame = firePointCFrame,
		Direction = direction,
	}, targets)
end

function module.Reload(player)
	local character = player.Character
	if not character then return end
	local tool = character:FindFirstChildWhichIsA("Tool")
	if not tool or not tool:FindFirstChild("SPH_Weapon") then return end
	local ok, wepStats = pcall(require, tool.SPH_Weapon.WeaponStats)
	if not ok or not wepStats.UBGL or not wepStats.UBGL.Enabled then return end
	local ammo = tool:FindFirstChild("UBGLAmmo")
	if not ammo then return end
	local capacity = wepStats.UBGL.Capacity or 1
	if ammo.Loaded.Value >= capacity or ammo.AmmoPool.Value <= 0 then return end
	ammo.Loaded.Value += 1
	ammo.AmmoPool.Value -= 1
end

function module.Explode(hitPosition, player, tool)
	if typeof(tool) ~= "Instance" or not tool:FindFirstChild("SPH_Weapon") then return end

	local ok, wepStats = pcall(require, tool.SPH_Weapon.WeaponStats)
	if not ok or not wepStats.UBGL then return end

	explosionMod(
		hitPosition,
		wepStats.UBGL.ExplosionRadius or 10,
		wepStats.UBGL.ExplosionEffect or "HEShell",
		player
	)
end

return module