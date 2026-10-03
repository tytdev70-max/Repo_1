--!nonstrict
-- AttachmentManager (DEPRECATED compatibility shim)
--
-- The attachment system now lives in Modules/ThirdParty/GunAttachments and is wired
-- into SPH by Weapons/Attachments/SPHAttachments. This shim keeps the old function
-- names / argument orders working for any script not yet migrated (e.g. scripts that
-- exist only in the place file). New code should use SPHAttachments directly:
--
--     local Attachments = require(Modules.Weapons.Attachments.SPHAttachments)
--
-- Old → new mapping is listed next to each function.

local Attachments = require(script.Parent.SPHAttachments)

local AttachmentManager = {}

AttachmentManager.System = Attachments

-- → Attachments:LoadConfig(slot, name)
function AttachmentManager.LoadAttachmentConfig(attachmentName, category)
	return Attachments:LoadConfig(category, attachmentName)
end

-- → Attachments:ResetModel(model)
function AttachmentManager.PrepareForEquip(weaponModel)
	Attachments:ResetModel(weaponModel)
end

-- → Attachments:Equip(model, tool, slot, name, owner)
function AttachmentManager.EquipAttachment(player, weapon, weaponModel, attachmentName, category)
	local ok = Attachments:Equip(weaponModel, weapon, category, attachmentName, player)
	return ok
end

-- → Attachments:Unequip(model, slot)
function AttachmentManager.UnequipAttachment(weaponModel, category)
	Attachments:Unequip(weaponModel, category)
end

-- → Attachments:ClearModel(model)
function AttachmentManager.ClearAllAttachments(weaponModel)
	Attachments:ClearModel(weaponModel)
end

-- → Attachments:GetActive(model)
function AttachmentManager.GetActiveAttachments(weaponModel)
	return Attachments:GetActive(weaponModel)
end

-- → Attachments:Has(model, slot)
function AttachmentManager.HasAttachment(weaponModel, category)
	return Attachments:Has(weaponModel, category)
end

-- → Attachments:GetAimPart(model, sightIndex)
function AttachmentManager.GetAttachmentAimPart(weaponModel, sightIndex)
	return Attachments:GetAimPart(weaponModel, sightIndex)
end

-- → Attachments:GetGripData(model)
function AttachmentManager.GetGripHandPosition(weaponModel, _weaponName)
	return Attachments:GetGripData(weaponModel)
end

-- → Attachments:HasHandGrip(model)
function AttachmentManager.HasGripEquipped(weaponModel)
	return Attachments:HasHandGrip(weaponModel)
end

-- → Attachments:GetActiveMuzzle(model)
function AttachmentManager.GetActiveMuzzle(weaponModel)
	return Attachments:GetActiveMuzzle(weaponModel)
end

-- → Attachments:GetSlotConfig(model, "Muzzle")
function AttachmentManager.GetMuzzleAttachmentConfig(weaponModel)
	return Attachments:GetSlotConfig(weaponModel, "Muzzle")
end

-- → Attachments:GetConfigField(model, "Muzzle", "overHeating")
function AttachmentManager.GetOverheatConfig(weaponModel)
	return Attachments:GetConfigField(weaponModel, "Muzzle", "overHeating")
end

-- → Attachments:GetConfigField(model, "Optics", "ReticleConfig")
function AttachmentManager.GetReticleConfig(weaponModel)
	return Attachments:GetConfigField(weaponModel, "Optics", "ReticleConfig")
end

-- → Attachments:GetConfigField(model, "Optics", "DepthOfField")
function AttachmentManager.GetDepthOfFieldConfig(weaponModel)
	return Attachments:GetConfigField(weaponModel, "Optics", "DepthOfField")
end

-- → Attachments:ApplyADSVisibility(model, aiming, wepStats.aimTime)
function AttachmentManager.ApplyAttachmentADSVisibility(weaponModel, aiming, wepStats)
	Attachments:ApplyADSVisibility(weaponModel, aiming, wepStats and wepStats.aimTime)
end

-- → Attachments:Has(model, "Muzzle")
function AttachmentManager.HasMuzzleOverride(weaponModel)
	return Attachments:Has(weaponModel, "Muzzle")
end

-- → Attachments:HasHandGrip(model)
function AttachmentManager.HasGripEquipped(weaponModel)
	return Attachments:HasHandGrip(weaponModel)
end

-- → Attachments:CleanupMuzzleState(model)
function AttachmentManager.CleanupMuzzleState(weaponModel)
	Attachments:CleanupMuzzleState(weaponModel)
end

-- → Attachments:PreHideOriginalMuzzle(model)
function AttachmentManager.PreHideOriginalMuzzle(weaponModel)
	Attachments:PreHideOriginalMuzzle(weaponModel)
end

-- → Attachments:SetBaseStats(tool, stats)
function AttachmentManager.StoreOriginalStats(weapon, baseStats)
	Attachments:SetBaseStats(weapon, baseStats)
end

-- → Attachments:GetBaseStats(tool)
function AttachmentManager.RestoreStatsFromTool(weapon)
	return Attachments:GetBaseStats(weapon)
end

-- → Attachments:ComputeStats(tool, model?)
function AttachmentManager.ApplyAttachmentStats(weapon, weaponModel)
	return Attachments:ComputeStats(weapon, weaponModel)
end

-- Was a no-op in the old manager; kept as a no-op (base stats are weak-keyed now).
function AttachmentManager.ClearOriginalStats(_weapon) end

-- Was a no-op in the old manager.
function AttachmentManager.DebugMuzzleState(_weaponModel) end

-- → Attachments:AnyActiveFlag(model, "EnableLaser")
function AttachmentManager.HasLaserAttachment(weaponModel)
	return Attachments:AnyActiveFlag(weaponModel, "EnableLaser")
end

-- → Attachments:AnyActiveFlag(model, "EnableFlashlight")
function AttachmentManager.HasFlashlightAttachment(weaponModel)
	return Attachments:AnyActiveFlag(weaponModel, "EnableFlashlight")
end

-- → Attachments:GetLaserSource(model)
function AttachmentManager.GetLaserSource(weaponModel)
	return Attachments:GetLaserSource(weaponModel)
end

-- → Attachments:GetFlashlightSource(model)
function AttachmentManager.GetFlashlightSource(weaponModel)
	return Attachments:GetFlashlightSource(weaponModel)
end

function AttachmentManager.GetFlashlightLights(weaponModel)
	local part = Attachments:GetFlashlightSource(weaponModel)
	if not part then
		return nil
	end
	return {
		part = part,
		inner = part:FindFirstChild("InnerSpotLight"),
		outer = part:FindFirstChild("OuterSpotLight"),
	}
end

return AttachmentManager
