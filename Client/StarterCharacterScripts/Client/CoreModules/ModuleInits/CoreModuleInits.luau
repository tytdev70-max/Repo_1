-- ModuleInits/CoreModuleInits
-- Initializes core modules that need early setup:
-- bulletHandler, flashbangEffectMod, child sub-modules (spawned).
-- Also wires the glass restore remote event.

local AssetRefs   = require(script.Parent.Parent.Boot.AssetRefs)
local StateInit   = require(script.Parent.Parent.Boot.StateInit)
local ServiceRefs = require(script.Parent.Parent.Boot.ServiceRefs)

local modules       = AssetRefs.modules
local players       = ServiceRefs.players

local bulletHandler       = require(modules.Weapons.Fire.BulletHandler)
local flashbangEffectMod  = require(modules.Effects.Explosions.FlashbangEffectMod)
local SPH_Events          = require(modules.Core.Networking.SPH_Events)

local CoreModuleInits = {}

function CoreModuleInits.init()
	local player = players.LocalPlayer

	bulletHandler.Initialize(player)
	flashbangEffectMod.Init()

	-- Child sub-modules (spawned to avoid blocking)
	task.spawn(function()
		require(script.Parent.Parent.Parent.Movement.CharacterMovement)
	end)
	task.spawn(function()
		require(script.Parent.Parent.Parent.Movement.LandJump)
	end)
	task.spawn(function()
		require(script.Parent.Parent.Parent.FallDamage.FallDamage)
	end)
	task.spawn(function()
		require(script.Parent.Parent.Parent.Visibility.FirstPersonVisibility)
	end)
	task.spawn(function()
		require(script.Parent.Parent.Parent.Visibility.RigUpdater)
	end)

	task.spawn(function()
		local character = require(script.Parent.Parent.Boot.CharacterRefs).character
		require(script.Parent.Parent.Parent.ScopeSystems.ScopeParallax).init(character)
	end)
	
	-- Indoor reverb (SoundService.AmbientReverb while under a ceiling)
	task.spawn(function()
		local character = require(script.Parent.Parent.Boot.CharacterRefs).character
		require(script.Parent.Parent.Parent.IndoorReverb.IndoorAudioReverb).init(character)
	end)

	-- Glass restore
	local glassRestoredEvent = SPH_Events.Find("EnvironmentEvents", "SPH_GlassRestored")
	if glassRestoredEvent and glassRestoredEvent:IsA("RemoteEvent") then
		glassRestoredEvent.OnClientEvent:Connect(function(glassPart: BasePart?, origTransparency: number?)
			if not glassPart or not glassPart.Parent then return end
			glassPart.LocalTransparencyModifier = 0
			glassPart.Transparency = origTransparency or 0
		end)
	end

	-- Touch tracking for pinch zoom
	local userInputService = ServiceRefs.userInputService
	local vars = StateInit.vars

	userInputService.TouchStarted:Connect(function(touch: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		vars.activeTouches[touch] = touch
	end)

	userInputService.TouchEnded:Connect(function(touch: InputObject, gameProcessed: boolean)
		if gameProcessed then return end
		vars.activeTouches[touch] = nil
	end)
end

CoreModuleInits.bulletHandler      = bulletHandler
CoreModuleInits.flashbangEffectMod = flashbangEffectMod

return CoreModuleInits