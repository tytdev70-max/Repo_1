--!strict

local Modules = script:FindFirstAncestor("Modules")

local WeaponClient = {}

WeaponClient.State = require(Modules.Weapons.Core.WeaponState)
WeaponClient.Context = require(Modules.Weapons.Core.WeaponContext)

WeaponClient.Math = require(Modules.Weapons.Math.WeaponMath)

WeaponClient.Actions    = require(script.Parent.Actions.WeaponActions)
WeaponClient.Animation  = require(script.Parent.Animation.WeaponAnimation)
WeaponClient.Sequences  = require(script.Parent.Actions.WeaponSequences)
WeaponClient.Viewmodel  = require(script.Parent.Viewmodel.WeaponViewmodel)
WeaponClient.Aiming     = require(script.Parent.Aiming.WeaponAiming)
WeaponClient.Frame      = require(script.Parent.Viewmodel.WeaponFrame)
WeaponClient.Input      = require(script.Parent.Input.WeaponInput)
WeaponClient.Lifecycle  = require(script.Parent.Lifecycle.WeaponLifecycle)

function WeaponClient.init()
	WeaponClient.Actions.init()
	WeaponClient.Animation.init()
	WeaponClient.Sequences.init()
	WeaponClient.Viewmodel.init()
	WeaponClient.Aiming.init()
	WeaponClient.Frame.init()
	WeaponClient.Input.init()
	WeaponClient.Lifecycle.init()
end

return WeaponClient