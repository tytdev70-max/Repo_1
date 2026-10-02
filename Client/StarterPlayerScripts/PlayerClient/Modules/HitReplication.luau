--// HitReplication.lua
--// Handles Network packet ReplicateHit: resolves bullet stats from either
--// a turret table or a standard SPH_Weapon Tool, then triggers hit FX.

local HitReplication = {}

local ServiceRefs     = require(script.Parent.ServiceRefs)
local modules               = ServiceRefs.modules

local hitFX           = require(modules.Effects.Blood.HitFX)
local Network         = require(modules.Core.Networking.SPH_Network)
local MaterialCodec   = require(modules.Core.Networking.MaterialCodec)

--// Public

function HitReplication.Init(): ()
	Network.packets.ReplicateHit.listen(function(Data: any): ()
		local tool: any = Data.Tool
		if not tool then return end

		local bulletStats: any = nil

		-- Turret path
		if typeof(tool) == "table" and tool.model then
			local ok: boolean, stats: any = pcall(function(): any
				return require(tool.model.Parent.TurretModule).guns[tool.index]
			end)
			if ok then bulletStats = stats end

			-- Standard weapon path
		elseif typeof(tool) == "Instance"
			and tool:IsA("Tool")
			and tool:FindFirstChild("SPH_Weapon")
		then
			local ok: boolean, stats: any = pcall(function(): any
				return require(tool.SPH_Weapon.WeaponStats)
			end)
			if ok then bulletStats = stats end
		end

		if bulletStats
			and Data.RaycastInstance
			and bulletStats.projectile == "Bullet"
		then
			local material: any = MaterialCodec.Decode(Data.RaycastMaterial)
			hitFX.HitEffect(
				Data.RaycastPosition,
				Data.RaycastInstance,
				Data.RaycastNormal,
				material,
				Data.BloodParams
			)
		end
	end)
end

return HitReplication