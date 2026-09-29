-- Bootstrap/ServiceRefs
-- All game:GetService() calls collected in one place.
-- Returns a flat table of every service used by the system.

local ServiceRefs = {}

ServiceRefs.replicatedStorage   = game:GetService("ReplicatedStorage")
ServiceRefs.runService          = game:GetService("RunService")
ServiceRefs.userInputService    = game:GetService("UserInputService")
ServiceRefs.players             = game:GetService("Players")
ServiceRefs.tweenService        = game:GetService("TweenService")
ServiceRefs.collectionService   = game:GetService("CollectionService")
ServiceRefs.ContentProvider     = game:GetService("ContentProvider")
ServiceRefs.proxPromptService   = game:GetService("ProximityPromptService")
ServiceRefs.debris              = game:GetService("Debris")
ServiceRefs.testService         = game:GetService("TestService")
ServiceRefs.contextActionService= game:GetService("ContextActionService")
ServiceRefs.starterGui          = game:GetService("StarterGui")

return ServiceRefs