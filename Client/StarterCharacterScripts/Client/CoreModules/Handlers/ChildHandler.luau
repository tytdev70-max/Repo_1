-- Handlers/ChildHandler
-- character.ChildAdded and character.ChildRemoved connections.

local AssetRefs     = require(script.Parent.Parent.Boot.AssetRefs)
local CharacterRefs = require(script.Parent.Parent.Boot.CharacterRefs)
local StateInit     = require(script.Parent.Parent.Boot.StateInit)
local ServiceRefs   = require(script.Parent.Parent.Boot.ServiceRefs)
local SystemInits   = require(script.Parent.Parent.ModuleInits.SystemModuleInits)

local character        = CharacterRefs.character
local humanoid         = CharacterRefs.humanoid
local vars             = StateInit.vars
local config           = StateInit.config
local warnPrefix       = StateInit.warnPrefix
local userInputService = ServiceRefs.userInputService
local players          = ServiceRefs.players
local player           = players.LocalPlayer

local weaponModelsFolder = AssetRefs.weaponModelsFolder
local weaponEquipMod     = SystemInits.weaponEquipMod
local WeaponBindings     = SystemInits.WeaponBindings

local ChildHandler = {}

local function getOtherPlayerGunModel(otherCharacter: Model?): Model?
	if not otherCharacter then return nil end
	local rig = otherCharacter:FindFirstChild("WeaponRig")
	if not rig then return nil end
	local weaponFolder = rig:FindFirstChild("Weapon")
	if not weaponFolder then return nil end
	return weaponFolder:FindFirstChildWhichIsA("Model")
end

ChildHandler.getOtherPlayerGunModel = getOtherPlayerGunModel

function ChildHandler.init()
	character.ChildAdded:Connect(function(newChild: Instance)
		if vars.throwingGrenade and newChild:IsA("Tool") then
			local backpack = player:FindFirstChildOfClass("Backpack")
			if backpack then newChild.Parent = backpack end
			return
		end

		if vars.equipping or vars.unequipping then
			character:SetAttribute("IsUnequippingForArmHiding", true)

			if newChild:IsA("Tool") then
				local backpack = player:FindFirstChildOfClass("Backpack")
				vars.queuedTool = newChild
				if backpack then newChild.Parent = backpack end
			end

			task.spawn(function()
				task.wait()
				if vars.queuedTool then return end
				if not character:FindFirstChildWhichIsA("Tool") then
					character:SetAttribute("IsUnequippingForArmHiding", false)
				end
			end)
			return
		end

		local hasGunModel = weaponModelsFolder and weaponModelsFolder:FindFirstChild(newChild.Name)

		if newChild:FindFirstChild("SPH_Weapon") and not hasGunModel then
			warn(warnPrefix .. "No gun model could be found for '" .. newChild.Name .. "'")
			return
		end

		if newChild:FindFirstChild("SPH_Weapon")
			and not vars.dead
			and not character:GetAttribute("IsSwimming")
			and (not humanoid.Sit or humanoid.Sit and not vars.vehicleSeated) then
			weaponEquipMod.EquipWeapon(newChild)
		elseif newChild:IsA("Tool") and not newChild:FindFirstChild("SPH_Weapon") then
			vars.isUnequippingForArmHiding = false
			character:SetAttribute("IsUnequippingForArmHiding", false)
		elseif newChild.Name == "WeaponRig" then
			vars.weaponRig = newChild
			vars.characterAnimator = newChild
				:WaitForChild("AnimationController", 20)
				:WaitForChild("Animator") :: Animator
		elseif newChild:IsA("Accessory") and vars.equipped and vars.firstPerson then
			task.wait()
			WeaponBindings.SyncArmAccessoriesToViewmodel()
		end
	end)

	character.ChildRemoved:Connect(function(oldChild: Instance)
		local hadGunModel = weaponModelsFolder and weaponModelsFolder:FindFirstChild(oldChild.Name)

		if oldChild:FindFirstChild("SPH_Weapon") and hadGunModel then
			local wasDropping = vars.dropping
			if vars.equipped and oldChild == vars.equipped then
				if vars.throwingGrenade then return end
				if vars.unequipping or wasDropping then return end
				character:SetAttribute("BackpackDisabled", true)
				userInputService.MouseIconEnabled = false
				WeaponBindings.Unequip(oldChild, false)
			end
		elseif oldChild:IsA("Accessory") and vars.equipped and vars.firstPerson then
			WeaponBindings.SyncArmAccessoriesToViewmodel()
		end
	end)
end

return ChildHandler