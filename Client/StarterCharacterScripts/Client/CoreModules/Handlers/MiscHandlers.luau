-- Handlers/MiscHandlers
-- Mouse icon toggle, camera type guard, customize GUI setup.

local AssetRefs     = require(script.Parent.Parent.Boot.AssetRefs)
local CharacterRefs = require(script.Parent.Parent.Boot.CharacterRefs)
local CameraSetup   = require(script.Parent.Parent.Boot.CameraSetup)
local StateInit     = require(script.Parent.Parent.Boot.StateInit)
local ViewmodelSetup= require(script.Parent.Parent.Boot.ViewmodelSetup)
local ServiceRefs   = require(script.Parent.Parent.Boot.ServiceRefs)
local SystemInits   = require(script.Parent.Parent.ModuleInits.SystemModuleInits)

local character        = CharacterRefs.character
local humanoid         = CharacterRefs.humanoid
local camera           = CameraSetup.camera
local animBase         = ViewmodelSetup.animBase
local storageCFrame    = StateInit.storageCFrame
local vars             = StateInit.vars
local runService       = ServiceRefs.runService
local userInputService = ServiceRefs.userInputService
local players          = ServiceRefs.players
local player           = players.LocalPlayer
local playerGui        = AssetRefs.playerGui
local assets           = AssetRefs.assets

local WeaponBindings = SystemInits.WeaponBindings
local SPH_Events     = SystemInits.SPH_Events
local Network        = SystemInits.Network
local mobileSupport  = SystemInits.mobileSupport

local MiscHandlers = {}

function MiscHandlers.init()
	-- Mouse icon toggle
	runService.RenderStepped:Connect(function()
		if not vars.dead then
			if vars.equipped then
				userInputService.MouseIconEnabled = false
			else
				userInputService.MouseIconEnabled = true
			end
		end
	end)

	-- Camera type guard
	camera:GetPropertyChangedSignal("CameraType"):Connect(function()
		if camera.CameraType ~= Enum.CameraType.Custom then
			vars.viewmodelVisible = false
			animBase.CFrame = storageCFrame
			vars.holdingM1  = false
			vars.canFire    = false
			if vars.equipped then
				humanoid:UnequipTools()
			end
		end
	end)

	-- Customize GUI deferred setup
	task.spawn(function()
		if vars.equipped then
			local setupEvent = SPH_Events.Find("GunEvents", "SetupCustomizeGUI")
			if setupEvent and setupEvent:IsA("BindableEvent") then
				setupEvent:Fire(vars.equipped)
			end
		end
	end)

	-- Character added
	if player.Character then
		WeaponBindings.onCharacterAdded(player.Character)
	end
	player.CharacterAdded:Connect(WeaponBindings.onCharacterAdded)
end

return MiscHandlers