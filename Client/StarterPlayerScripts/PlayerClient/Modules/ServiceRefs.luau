--// ServiceRefs.lua
--// Centralizes all Roblox service handles, asset references, player/camera
--// pointers, and remote event instances so every other module imports
--// from a single authoritative source rather than calling GetService
--// repeatedly across files.

local ServiceRefs = {}

--// Roblox Services

ServiceRefs.Players       = game:GetService("Players")
ServiceRefs.ReplicatedStorage = game:GetService("ReplicatedStorage")
ServiceRefs.TweenService  = game:GetService("TweenService")
ServiceRefs.RunService    = game:GetService("RunService")
ServiceRefs.Debris        = game:GetService("Debris")
ServiceRefs.HttpService   = game:GetService("HttpService")
ServiceRefs.SoundService  = game:GetService("SoundService")
ServiceRefs.PhysicsService = game:GetService("PhysicsService")

--// Player & Camera

ServiceRefs.player    = ServiceRefs.Players.LocalPlayer :: Player
ServiceRefs.camera    = workspace.CurrentCamera :: Camera
ServiceRefs.PlayerGui = ServiceRefs.player:WaitForChild("PlayerGui") :: PlayerGui

--// Assets

local assets: any                 = ServiceRefs.ReplicatedStorage:WaitForChild("SPH_Assets")
ServiceRefs.assets                = assets
ServiceRefs.animations            = assets.Animations
ServiceRefs.modules               = assets.Modules
ServiceRefs.events                = assets:WaitForChild("Events")
ServiceRefs.Config                = require(assets.GameConfig)

--// Remote Events (resolved once at startup)

ServiceRefs.doorCameraShakeEvent  = ServiceRefs.events
	:WaitForChild("DoorEvents")
	:WaitForChild("DoorCameraShakeEvent")

ServiceRefs.explosionRemote       = ServiceRefs.events
	:WaitForChild("ExplosionEvents")
	:WaitForChild("ExplosionFXRemote")

ServiceRefs.killFeedRemote        = assets.Events.DeathEvents.KillFeed

return ServiceRefs