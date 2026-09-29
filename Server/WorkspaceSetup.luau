-- WorkspaceSetup
-- Creates SPH_Workspace and all subfolders in workspace.
-- Populates ServerState with folder references.

local Constants   = require(script.Parent.Constants)
local ServerState = require(script.Parent.ServerState)

local WorkspaceSetup = {}

function WorkspaceSetup.init()
	local mainFolder = Instance.new("Folder")
	mainFolder.Name   = "SPH_Workspace"
	mainFolder.Parent = workspace

	for _, folderName in ipairs(Constants.WORKSPACE_SUBFOLDER_NAMES) do
		local subFolder = Instance.new("Folder")
		subFolder.Name   = folderName
		subFolder.Parent = mainFolder
		ServerState.workspaceFolders[folderName] = subFolder
	end

	ServerState.projectiles = ServerState.workspaceFolders.Projectiles
	ServerState.cache       = ServerState.workspaceFolders.Cache
	ServerState.smokeCache  = ServerState.workspaceFolders.SmokeCache
	ServerState.shells      = ServerState.workspaceFolders.Shells
	ServerState.drops       = ServerState.workspaceFolders.Drops
end

return WorkspaceSetup