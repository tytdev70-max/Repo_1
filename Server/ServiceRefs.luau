-- ServiceRefs
-- All game:GetService() calls in one place.

local ServiceRefs = {}

-- One-time startup (not a service, but belongs here)
game.StarterPlayer.EnableMouseLockOption = false

ServiceRefs.players           = game:GetService("Players")
ServiceRefs.replicatedStorage = game:GetService("ReplicatedStorage")
ServiceRefs.debris            = game:GetService("Debris")
ServiceRefs.proxPromptService = game:GetService("ProximityPromptService")
ServiceRefs.collectionService = game:GetService("CollectionService")
ServiceRefs.HttpService       = game:GetService("HttpService")
ServiceRefs.runService        = game:GetService("RunService")
ServiceRefs.physicsService    = game:GetService("PhysicsService")
ServiceRefs.soundService      = game:GetService("SoundService")

return ServiceRefs