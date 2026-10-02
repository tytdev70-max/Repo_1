--// WeaponContext.lua
--// Shared utility: resolves a remote shooter's active weapon context
--// (tool, wepStats, rig, gunModel) so fire-replication modules can
--// share the resolution logic without duplication.

local WeaponContext = {}

--// Types

export type RemoteWeaponContext = {
	tool      : Tool,
	wepStats  : any,
	rig       : Instance,
	gunModel  : Model,
}

--// Public

--- Returns a RemoteWeaponContext for `shooter`, or nil when any required
--- piece is missing.  `requireAmmo` gates on the presence of an Ammo child.
function WeaponContext.ResolveShooterWeapon(
	shooter      : Player,
	requireAmmo  : boolean
): RemoteWeaponContext?
	local character: Model? = shooter.Character
	if not character then return nil end

	local tool: Tool? = character:FindFirstChildWhichIsA("Tool")
	if not tool or not tool:FindFirstChild("SPH_Weapon") then return nil end
	if requireAmmo and not tool:FindFirstChild("Ammo") then return nil end

	local rig: Instance? = character:FindFirstChild("WeaponRig")
	if not rig then return nil end

	local weaponFolder: Instance? = rig:FindFirstChild("Weapon")
	if not weaponFolder then return nil end

	local gunModel: Model? = weaponFolder:FindFirstChildWhichIsA("Model")
	if not (gunModel and gunModel.Parent and gunModel:FindFirstChild("Grip")) then
		return nil
	end

	local wepStats: any = require((tool :: any).SPH_Weapon.WeaponStats)

	return {
		tool     = tool     :: Tool,
		wepStats = wepStats,
		rig      = rig      :: Instance,
		gunModel = gunModel :: Model,
	}
end

return WeaponContext