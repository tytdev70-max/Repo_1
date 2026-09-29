-- Handlers/ClientBridgeBindings
-- All clientBridge.bind(...) calls except repLean (which is in RemoteLeanHandler).

local AssetRefs     = require(script.Parent.Parent.Boot.AssetRefs)
local CharacterRefs = require(script.Parent.Parent.Boot.CharacterRefs)
local StateInit     = require(script.Parent.Parent.Boot.StateInit)
local ServiceRefs   = require(script.Parent.Parent.Boot.ServiceRefs)
local SystemInits   = require(script.Parent.Parent.ModuleInits.SystemModuleInits)

local modules        = AssetRefs.modules
local character      = CharacterRefs.character
local vars           = StateInit.vars
local players        = ServiceRefs.players
local player         = players.LocalPlayer

local clientBridge   = SystemInits.clientBridge
local PacketRefs     = SystemInits.PacketRefs
local Network        = SystemInits.Network
local WeaponBindings = SystemInits.WeaponBindings
local laserSightMod  = SystemInits.laserSightMod
local aimingSystemMod= SystemInits.aimingSystemMod
local shellEjection  = SystemInits.shellEjection

-- getOtherPlayerGunModel is also defined in ChildHandler; re-defined here locally
-- to avoid circular requires (identical logic, same behavior).
local function getOtherPlayerGunModel(otherCharacter: Model?): Model?
	if not otherCharacter then return nil end
	local rig = otherCharacter:FindFirstChild("WeaponRig")
	if not rig then return nil end
	local weaponFolder = rig:FindFirstChild("Weapon")
	if not weaponFolder then return nil end
	return weaponFolder:FindFirstChildWhichIsA("Model")
end

local ClientBridgeBindings = {}

function ClientBridgeBindings.init()
	-- repMagGrab
	clientBridge.bind("repMagGrab", PacketRefs.repMagGrab, function(Data: any)
		local targetPlayer: Player? = Data.TargetPlayer
		if targetPlayer == player then return end

		local tpGunModel = WeaponBindings.GetThirdPersonGunModel()
		if not tpGunModel then return end

		local tpMag = tpGunModel:FindFirstChild("Mag")
			or (vars.wepStats and vars.wepStats.projectile ~= "Bullet"
				and tpGunModel:FindFirstChild(vars.wepStats.projectile))
			or tpGunModel:FindFirstChild("")

		if tpMag then
			tpMag.Transparency = 0
			for _, child in ipairs(tpMag:GetDescendants()) do
				if child:IsA("BasePart") then
					child.Transparency = 0
				elseif child:IsA("Decal") or child:IsA("Texture") then
					child.Transparency = 0
				end
			end

			local bulletHolder = vars.wepStats.bulletHolder
				and tpGunModel:FindFirstChild(vars.wepStats.bulletHolder)
			if bulletHolder then
				WeaponBindings.UpdateAllBulletTransparency(bulletHolder, 0)
			end
		end
	end)

	-- repBolt
	clientBridge.bind("PacketRefs.repBolt", PacketRefs.repBolt, function(Data: any)
		local otherPlayer: Player? = Data.Player
		local direction: Vector3?  = Data.Direction
		local magAmmo: number?     = Data.MagAmmo
		local instant: boolean?    = Data.Instant
		if otherPlayer == players.LocalPlayer then return end

		local otherCharacter = otherPlayer and otherPlayer.Character
		local weaponModel    = getOtherPlayerGunModel(otherCharacter)
		if not weaponModel then return end

		local tool = otherCharacter and otherCharacter:FindFirstChildWhichIsA("Tool")
		if not tool or not tool:FindFirstChild("SPH_Weapon") then return end

		local wepStats     = require(tool.SPH_Weapon.WeaponStats)
		local bh           = require(modules.Weapons.Fire.BulletHandler)
		bh.MoveBolt(weaponModel, wepStats, direction, magAmmo, instant)
	end)

	-- repPartVisibility
	clientBridge.bind("repPartVisibility", PacketRefs.repPartVisibilityReplicate, function(Data: any)
		local targetCharacter: Model? = Data.TargetCharacter
		local partName: string?       = Data.PartName
		local visible: boolean?       = Data.Visible
		if not targetCharacter or targetCharacter == character then return end

		local weaponModel = getOtherPlayerGunModel(targetCharacter)
		if not weaponModel then return end

		local part = partName and weaponModel:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			part.Transparency = if visible then 0 else 1
			for _, child in ipairs(part:GetDescendants()) do
				if child:IsA("BasePart") then
					child.Transparency = if visible then 0 else 1
				end
			end
		end
	end)

	-- repToggleAttachment
	clientBridge.bind(
		"PacketRefs.repToggleAttachment",
		PacketRefs.repToggleAttachment,
		laserSightMod.HandleToggleAttachmentReplicate)

	-- repAimState
	clientBridge.bind(
		"repAimState",
		PacketRefs.repAimStateReplicate,
		aimingSystemMod.HandleAimStateReplicate)

	-- repWeaponPushback
	clientBridge.bind(
		"repWeaponPushback",
		Network.packets.WeaponPushbackReplicate,
		aimingSystemMod.HandleWeaponPushbackReplicate)

	-- repShellEject
	clientBridge.bind("repShellEject", PacketRefs.repShellEjectReplicate, function(otherPlayer: Player)
		if otherPlayer == player then return end
		local otherChar = otherPlayer.Character
		if not otherChar then return end

		local otherGun = getOtherPlayerGunModel(otherChar)
		if not otherGun then return end

		local otherTool = otherChar:FindFirstChildWhichIsA("Tool")
		if not otherTool then return end
		shellEjection.ejectShell(otherPlayer, otherTool, otherGun)
	end)
end

return ClientBridgeBindings