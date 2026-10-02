-- Bootstrap/EffectsSetup
-- Creates/finds DOF and blur effect instances in Lighting.

local StateInit = require(script.Parent.StateInit)
local config    = StateInit.config

local EffectsSetup = {}

-- Depth of field
local depthOfField: DepthOfFieldEffect? = game.Lighting:FindFirstChild("SPH_DoF") :: DepthOfFieldEffect?
if not depthOfField and config.blurEffects then
	depthOfField = Instance.new("DepthOfFieldEffect", game.Lighting)
end
if depthOfField then
	depthOfField.Name = "SPH_DoF"
end
EffectsSetup.depthOfField = depthOfField

-- Shoot blur
local shootBlur: BlurEffect = game.Lighting:FindFirstChild("ShootBlur") :: BlurEffect
	or Instance.new("BlurEffect", game.Lighting)
EffectsSetup.shootBlur = shootBlur

return EffectsSetup