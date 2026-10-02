-- Main LocalScript (lives where the original script lived)
-- Ties all modules together in the exact original order.

--// Replication guard
-- On respawn, Roblox clones this script (and its children) into the new character.
-- The LocalScript can start running BEFORE all of its descendant ModuleScripts have
-- replicated to the client, which caused errors like:
--   "AssetRefs is not a valid member of Folder ...CoreModules.Boot"
-- The modules below reference each other with direct indexing
-- (e.g. script.Parent.Parent.Boot.StateInit), so we wait for the whole tree up front.
-- Keep this list in sync when adding/renaming/removing modules under this script.
local REQUIRED_DESCENDANTS = {
	"CoreModules/Boot/ServiceRefs",
	"CoreModules/Boot/AssetRefs",
	"CoreModules/Boot/CharacterRefs",
	"CoreModules/Boot/CameraSetup",
	"CoreModules/Boot/StateInit",
	"CoreModules/Boot/SpringsAndThrottles",
	"CoreModules/Boot/ViewmodelSetup",
	"CoreModules/Boot/RaycastSetup",
	"CoreModules/Boot/PreloadSetup",
	"CoreModules/Boot/EffectsSetup",
	"CoreModules/Boot/FlashFXSetup",
	"CoreModules/ModuleInits/CoreModuleInits",
	"CoreModules/ModuleInits/SystemModuleInits",
	"CoreModules/ModuleInits/WeaponContextInit",
	"CoreModules/Handlers/DeathHandler",
	"CoreModules/Handlers/ChildHandler",
	"CoreModules/Handlers/InputHandler",
	"CoreModules/Handlers/JumpHandler",
	"CoreModules/Handlers/SeatedHandler",
	"CoreModules/Handlers/AttributeHandler",
	"CoreModules/Handlers/RemoteLeanHandler",
	"CoreModules/Handlers/ClientBridgeBindings",
	"CoreModules/Handlers/UpdateLoops",
	"CoreModules/Handlers/MiscHandlers",
	"FallDamage/FallDamage",
	"Movement/LandJump",
	"Movement/CharacterMovement",
	"Movement/CharacterMovement/Constants",
	"Movement/CharacterMovement/SharedState",
	"Movement/CharacterMovement/AnimationSetup",
	"Movement/CharacterMovement/MovementLean",
	"Movement/CharacterMovement/FootIK",
	"Movement/CharacterMovement/SprintSystem",
	"Movement/CharacterMovement/LeanSystem",
	"Movement/CharacterMovement/StanceSystem",
	"Movement/CharacterMovement/WalkSpeedSystem",
	"Movement/CharacterMovement/InputBindings",
	"Movement/CharacterMovement/SeatHandler",
	"Movement/CharacterMovement/BindableEventHandler",
	"Movement/CharacterMovement/RenderLoop",
	"Movement/CharacterMovement/DeathHandler",
	"Movement/CharacterMovement/Stamina",
	"ScopeSystems/ScopeParallax",
	"ScopeSystems/ScopeParallax/Main",
	"ScopeSystems/ScopeParallax/Main/Activate",
	"ScopeSystems/ScopeParallax/Main/Detect",
	"ScopeSystems/ScopeParallax/Main/ScopeConfig",
	"ScopeSystems/ScopeParallax/Main/Patcher",
	"ScopeSystems/ScopeParallax/Main/Patcher/Default",
	"ScopeSystems/ScopeParallax/Main/Patcher/7chon",
	"ScopeSystems/ScopeParallax/Main/Patcher/Spearhead",
	"Visibility/FirstPersonVisibility",
	"Visibility/RigUpdater",
	"IndoorReverb/IndoorAudioReverb",
}

-- Total time budget (seconds) shared by all waits, so a missing module
-- can't stall the character forever.
local REPLICATION_TIMEOUT = 20

local function waitForDescendants(root: Instance, paths: { string }, timeout: number)
	local deadline = os.clock() + timeout
	for _, path in ipairs(paths) do
		local current: Instance = root
		for segment in string.gmatch(path, "[^/]+") do
			local nextChild = current:FindFirstChild(segment)
			if not nextChild then
				local remaining = deadline - os.clock()
				if remaining > 0 then
					nextChild = current:WaitForChild(segment, remaining)
				end
			end
			if not nextChild then
				warn(string.format(
					"[SPH] '%s' did not replicate under %s within %ds (missing or renamed?)",
					path, root:GetFullName(), timeout
					))
				break
			end
			current = nextChild
		end
	end
end

waitForDescendants(script, REQUIRED_DESCENDANTS, REPLICATION_TIMEOUT)

--// Bootstrap Phase (order matters — each module may depend on the previous)
local ServiceRefs         = require(script:WaitForChild("CoreModules").Boot.ServiceRefs)
local AssetRefs           = require(script:WaitForChild("CoreModules").Boot.AssetRefs)
local CharacterRefs       = require(script:WaitForChild("CoreModules").Boot.CharacterRefs)
local CameraSetup         = require(script:WaitForChild("CoreModules").Boot.CameraSetup)
local StateInit           = require(script:WaitForChild("CoreModules").Boot.StateInit)
local SpringsAndThrottles = require(script:WaitForChild("CoreModules").Boot.SpringsAndThrottles)
local ViewmodelSetup      = require(script:WaitForChild("CoreModules").Boot.ViewmodelSetup)
local RaycastSetup        = require(script:WaitForChild("CoreModules").Boot.RaycastSetup)
local PreloadSetup        = require(script:WaitForChild("CoreModules").Boot.PreloadSetup)
local EffectsSetup        = require(script:WaitForChild("CoreModules").Boot.EffectsSetup)
local FlashFXSetup        = require(script:WaitForChild("CoreModules").Boot.FlashFXSetup)

--// Module Initialization Phase (order matches original exactly)
local CoreModuleInits   = require(script:WaitForChild("CoreModules").ModuleInits.CoreModuleInits)
local SystemModuleInits = require(script:WaitForChild("CoreModules").ModuleInits.SystemModuleInits)
local WeaponContextInit = require(script:WaitForChild("CoreModules").ModuleInits.WeaponContextInit)

CoreModuleInits.init()
SystemModuleInits.init()
WeaponContextInit.init()

--// Event Handlers Phase (order matches original exactly)
local DeathHandler          = require(script:WaitForChild("CoreModules").Handlers.DeathHandler)
local ChildHandler          = require(script:WaitForChild("CoreModules").Handlers.ChildHandler)
local InputHandler          = require(script:WaitForChild("CoreModules").Handlers.InputHandler)
local JumpHandler           = require(script:WaitForChild("CoreModules").Handlers.JumpHandler)
local SeatedHandler         = require(script:WaitForChild("CoreModules").Handlers.SeatedHandler)
local AttributeHandler      = require(script:WaitForChild("CoreModules").Handlers.AttributeHandler)
local RemoteLeanHandler     = require(script:WaitForChild("CoreModules").Handlers.RemoteLeanHandler)
local ClientBridgeBindings  = require(script:WaitForChild("CoreModules").Handlers.ClientBridgeBindings)
local UpdateLoops           = require(script:WaitForChild("CoreModules").Handlers.UpdateLoops)
local MiscHandlers          = require(script:WaitForChild("CoreModules").Handlers.MiscHandlers)

DeathHandler.init()
ChildHandler.init()
InputHandler.init()
JumpHandler.init()
SeatedHandler.init()
AttributeHandler.init()
RemoteLeanHandler.init()
ClientBridgeBindings.init()
UpdateLoops.init(script)
MiscHandlers.init()