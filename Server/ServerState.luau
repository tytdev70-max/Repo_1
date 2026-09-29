-- ServerState
-- All mutable server-side state tables shared across modules.

local ServerState = {}

ServerState.playerLeanStates      = {}
ServerState.playerAimStates       = {}
ServerState.shellEjectCooldowns   = {}
ServerState.pendingGrenadeThrows  = {}
ServerState.playerADSVisualStates = {}
ServerState.serverGripTargets     = {}
ServerState.lpvoLockedArms        = setmetatable({}, { __mode = "k" })
ServerState.lpvoArmTargets        = {}
ServerState.lpvoPreGripTarget     = setmetatable({}, { __mode = "k" })
ServerState.playerLPVOArmMotor    = {} :: { [Player]: Motor6D }
ServerState.playerArmIgnoreUntil  = {} :: { [Player]: number }
ServerState.activeDoors           = {}
ServerState.dropTable             = {}
ServerState.dropCFrame            = CFrame.new(0, 1, -3)
ServerState.pendingHolsterShows   = {}

-- Workspace folder refs (populated by WorkspaceSetup)
ServerState.workspaceFolders = {} :: { [string]: Folder }
ServerState.projectiles      = nil :: Folder?
ServerState.cache            = nil :: Folder?
ServerState.smokeCache       = nil :: Folder?
ServerState.shells           = nil :: Folder?
ServerState.drops            = nil :: Folder?

return ServerState