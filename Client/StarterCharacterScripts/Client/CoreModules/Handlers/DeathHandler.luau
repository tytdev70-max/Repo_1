-- Handlers/DeathHandler
-- humanoid.Died: cleanup anim, connections, effects, rig, camera.

local AssetRefs       = require(script.Parent.Parent.Boot.AssetRefs)
local CharacterRefs   = require(script.Parent.Parent.Boot.CharacterRefs)
local CameraSetup     = require(script.Parent.Parent.Boot.CameraSetup)
local StateInit       = require(script.Parent.Parent.Boot.StateInit)
local SpringsAndThrottles = require(script.Parent.Parent.Boot.SpringsAndThrottles)
local ViewmodelSetup  = require(script.Parent.Parent.Boot.ViewmodelSetup)
local ServiceRefs     = require(script.Parent.Parent.Boot.ServiceRefs)
local SystemInits     = require(script.Parent.Parent.ModuleInits.SystemModuleInits)

local humanoid         = CharacterRefs.humanoid
local character        = CharacterRefs.character
local camera           = CameraSetup.camera
local aimDoF           = CameraSetup.aimDoF
local inspectDoF       = CameraSetup.inspectDoF
local animBase         = ViewmodelSetup.animBase
local vars             = StateInit.vars
local config           = StateInit.config
local storageCFrame    = StateInit.storageCFrame
local respawnCameraMaxZoom = StateInit.respawnCameraMaxZoom
local respawnCameraMinZoom = StateInit.respawnCameraMinZoom

local equipConnections   = SpringsAndThrottles.equipConnections
local overheatThrottle   = SpringsAndThrottles.overheatThrottle
local lpvoThrottle       = SpringsAndThrottles.lpvoThrottle
local lpvoArmThrottle    = SpringsAndThrottles.lpvoArmThrottle

local userInputService   = ServiceRefs.userInputService
local players            = ServiceRefs.players
local player             = players.LocalPlayer

local modules            = AssetRefs.modules
local clientBridge       = SystemInits.clientBridge
local PacketRefs         = SystemInits.PacketRefs
local WeaponBindings     = SystemInits.WeaponBindings

local armPositionMod       = SystemInits.armPositionMod
local ubglSystem           = SystemInits.ubglSystem
local laserSightMod        = SystemInits.laserSightMod
local glareMod             = SystemInits.glareMod
local fireSelectorMod      = SystemInits.fireSelectorMod
local aimingSystemMod      = SystemInits.aimingSystemMod
local weaponPushbackMod    = SystemInits.weaponPushbackMod
local grenadeClient        = SystemInits.grenadeClient
local flashbangEffectMod   = SystemInits.flashbangEffectMod
local headPoseReplicationMod = SystemInits.headPoseReplicationMod

local DeathHandler = {}

local deathCleanupRoutines: { () -> () } = {
	function() armPositionMod.Cleanup() end,
	function()
		if ubglSystem then ubglSystem.Cleanup() end
	end,
	function()
		if laserSightMod then laserSightMod.Destroy() end
	end,
	function()
		if glareMod then glareMod.Cleanup() end
	end,
	function()
		if fireSelectorMod then fireSelectorMod.Cleanup() end
	end,
	function() aimingSystemMod.ResetAiming() end,
	function() weaponPushbackMod.Reset() end,
	function() vars.flashFX.endFP:Destroy() end,
	function() vars.flashFX.endTP:Destroy() end,
	function() vars.flashFX.beamFP:Destroy() end,
	function() vars.flashFX.beamTP:Destroy() end,
}

-- Camera follow own ragdoll corpse
local function setupRagdollCameraFollow()
	local CameraManager = require(modules.Systems.RagdollServerMod.CameraManager)
	local localUserId   = player.UserId

	local function TryFollowOwnCorpse()
		if not config.ragdollCameraFollowOwnDeath then return end
		task.spawn(function()
			local deadline = os.clock() + (config.ragdollCameraTorsoWaitTimeout or 5) + 1

			local function isOwnCorpse(obj)
				return obj:IsA("Model")
					and obj.Name == "DeadBody"
					and obj:GetAttribute("OwnerUserId") == localUserId
			end

			local staleBodies = {}
			for _, obj in ipairs(workspace:GetChildren()) do
				if isOwnCorpse(obj) then staleBodies[obj] = true end
			end

			while os.clock() < deadline do
				for _, obj in ipairs(workspace:GetChildren()) do
					if isOwnCorpse(obj) and not staleBodies[obj] then
						CameraManager.FollowDeadBody(obj)
						return
					end
				end
				task.wait(0.1)
			end
		end)
	end

	humanoid.Died:Connect(TryFollowOwnCorpse)
end

function DeathHandler.init()
	setupRagdollCameraFollow()

	humanoid.Died:Connect(function()
		clientBridge.unbindAll()
		vars.animCache = {}

		if equipConnections and typeof(equipConnections.DisconnectAll) == "function" then
			equipConnections:DisconnectAll()
		end
		if overheatThrottle  then overheatThrottle:Reset() end
		if lpvoThrottle      then lpvoThrottle:Reset() end
		if lpvoArmThrottle   then lpvoArmThrottle:Reset() end
		headPoseReplicationMod.ResetLocalThrottle()

		if vars.throwingGrenade
			and vars.wepStats
			and vars.wepStats.weaponType == "Grenade"
			and vars.wepStats.grenade then
			pcall(function() grenadeClient.ForceGrenadeCosmeticDrop() end)
		end
		pcall(function() grenadeClient.CleanupGrenadeCosmeticParts() end)
		pcall(function() flashbangEffectMod.Clear() end)

		vars.viewmodelVisible = false
		animBase.CFrame = storageCFrame
		if vars.gunModel then
			local oldGunOnDeath = vars.gunModel
			vars.gunModel = nil
			task.defer(function()
				if oldGunOnDeath and oldGunOnDeath.Parent then
					oldGunOnDeath:Destroy()
				end
			end)
		end

		vars.dead        = true
		vars.firstPerson = false
		vars.aiming      = false
		player.CameraMaxZoomDistance = respawnCameraMaxZoom
		player.CameraMinZoomDistance = respawnCameraMinZoom
		if config.lockFirstPerson then
			player.CameraMode = Enum.CameraMode.Classic
		end
		StateInit.vmArmAccessories = {}

		PacketRefs.switchWeapon.send(nil)

		if aimDoF and vars.isAimDoFActive then
			vars.isAimDoFActive = false
			aimDoF.Enabled = false
			pcall(function() WeaponBindings.ChangeDoF(0, 0, 0, 0, true) end)
		end
		if vars.inspectDoFActive and inspectDoF then
			vars.inspectDoFActive = false
			inspectDoF.Enabled    = false
		end

		vars.laserEnabled      = false
		vars.flashlightEnabled = false

		for _, cleanup in ipairs(deathCleanupRoutines) do
			pcall(cleanup)
		end

		vars.equipped    = nil
		vars.wepStats    = nil
		userInputService.MouseIconEnabled = true
		userInputService.MouseBehavior    = Enum.MouseBehavior.Default
		vars.viewmodelVisible = false
		animBase.CFrame = storageCFrame

		pcall(function() WeaponBindings.UnbindGunInputs() end)
		if vars.rig then
			local oldRig = vars.rig
			vars.rig = nil
			task.defer(function()
				if oldRig and oldRig.Parent then oldRig:Destroy() end
			end)
		end

		if not config.ragdollCameraFollowOwnDeath then
			camera.CameraType    = Enum.CameraType.Custom
			camera.CameraSubject = nil
		end
	end)
end

return DeathHandler