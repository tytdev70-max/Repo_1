-- Bootstrap/FlashFXSetup
-- Creates flashlight beam FX and populates vars.flashFX.

local AssetRefs = require(script.Parent.AssetRefs)
local StateInit = require(script.Parent.StateInit)
local modules   = AssetRefs.modules
local vars      = StateInit.vars

local flashMod = require(modules.Weapons.Attachments.FlashlightBeamMod) :: any

vars.flashFX = {}
vars.flashFX.mod = flashMod
vars.flashFX.beamFP, vars.flashFX.endFP = flashMod.CreateBeam("FlashlightBeamFP")
vars.flashFX.beamTP, vars.flashFX.endTP = flashMod.CreateBeam("FlashlightBeamTP")

local FlashFXSetup = {}
FlashFXSetup.flashMod = flashMod
return FlashFXSetup