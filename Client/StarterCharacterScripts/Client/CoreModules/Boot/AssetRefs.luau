-- Bootstrap/AssetRefs
-- All asset/folder lookups from ReplicatedStorage.
-- Returns a table of every asset reference used by the system.

local ServiceRefs = require(script.Parent.ServiceRefs)
local replicatedStorage = ServiceRefs.replicatedStorage
local players           = ServiceRefs.players

local AssetRefs = {}

AssetRefs.player    = players.LocalPlayer
AssetRefs.playerGui = AssetRefs.player:WaitForChild("PlayerGui") :: PlayerGui

local assets: Folder = replicatedStorage:WaitForChild("SPH_Assets") :: Folder
AssetRefs.assets     = assets
AssetRefs.modules    = assets:WaitForChild("Modules")    :: Folder
AssetRefs.animations = assets:WaitForChild("Animations") :: Folder

local eventsFolder: Folder = assets:WaitForChild("Events") :: Folder
AssetRefs.eventsFolder = eventsFolder
AssetRefs.toggleViewmodelSprint = eventsFolder
	:WaitForChild("GunEvents")
	:WaitForChild("ToggleViewmodelSprint") :: BindableEvent

AssetRefs.weaponModelsFolder = assets:FindFirstChild("WeaponModels") :: Folder?

return AssetRefs