-- Bootstrap/ViewmodelSetup
-- Creates the viewmodel rig, arm coloring, humanoid/animator setup,
-- animBase placement, and shirt instance.

local AssetRefs     = require(script.Parent.AssetRefs)
local CharacterRefs = require(script.Parent.CharacterRefs)
local StateInit     = require(script.Parent.StateInit)
local CameraSetup   = require(script.Parent.CameraSetup)
local ServiceRefs   = require(script.Parent.ServiceRefs)

local modules       = AssetRefs.modules
local character     = CharacterRefs.character
local camera        = CameraSetup.camera
local storageCFrame = StateInit.storageCFrame
local vars          = StateInit.vars
local config        = StateInit.config
local humanoid      = CharacterRefs.humanoid
local humanoidRootPart = CharacterRefs.humanoidRootPart
local players       = ServiceRefs.players

local viewMod            = require(modules.Weapons.Equip.ViewMod)
local proceduralWalkCycle= require(modules.Weapons.Aiming.ProceduralWalkCycle)
local fireSelectorMod    = require(modules.Weapons.Attachments.FireSelectorMod)
local bulletHandler      = require(modules.Weapons.Fire.BulletHandler)

local ViewmodelSetup = {}

-- Create rig
vars.rig = viewMod.RigModel(players.LocalPlayer) :: any
local lArm: BasePart = vars.rig["Left Arm"]  :: BasePart
local rArm: BasePart = vars.rig["Right Arm"] :: BasePart

-- Arm coloring
lArm.Color = character["Left Arm"].Color
rArm.Color = character["Right Arm"].Color

for _, part in ipairs(vars.rig:GetDescendants()) do
	if part.Name == "Skin" and part.Parent then
		if part.Parent.Name == "Left Arm" then
			part.Color = character["Left Arm"].Color
		elseif part.Parent.Name == "Right Arm" then
			part.Color = character["Right Arm"].Color
		end
	end
end

-- Viewmodel humanoid (all states disabled)
local vmHuman = Instance.new("Humanoid", vars.rig)
for _, state in ipairs(Enum.HumanoidStateType:GetEnumItems()) do
	if state == Enum.HumanoidStateType.None then continue end
	vmHuman:SetStateEnabled(state, false)
end

local vmAnimator = Instance.new("Animator", vmHuman)
local vmShirt    = Instance.new("Shirt",    vars.rig)

-- AnimBase placement
local animBase: BasePart = vars.rig.AnimBase :: BasePart
animBase.CFrame = storageCFrame
vars.rig.Parent = camera

bulletHandler.SetViewmodelRig(vars.rig)

-- Procedural walk cycle init
proceduralWalkCycle.Init({
	humanoid          = humanoid,
	humanoidRootPart  = humanoidRootPart,
	animBase          = animBase,
})

-- Fire selector init
fireSelectorMod.Init({
	viewmodelRig = vars.rig,
})

-- WeaponRig reference
vars.weaponRig = character:FindFirstChild("WeaponRig")
	or character:WaitForChild("WeaponRig", 20)
vars.characterAnimator = vars.weaponRig
	:WaitForChild("AnimationController")
	:WaitForChild("Animator") :: Animator

-- Miscellaneous character setup
if humanoidRootPart:FindFirstChild("Died") then
	local diedSound = humanoidRootPart:FindFirstChild("Died") :: Sound
	diedSound.Volume = 0
end

if config.lockFirstPerson then
	players.LocalPlayer.CameraMode = Enum.CameraMode.Classic
end

ViewmodelSetup.lArm        = lArm
ViewmodelSetup.rArm        = rArm
ViewmodelSetup.vmShirt     = vmShirt
ViewmodelSetup.vmAnimator  = vmAnimator
ViewmodelSetup.animBase    = animBase
ViewmodelSetup.vmHuman     = vmHuman

-- Re-export modules needed downstream
ViewmodelSetup.proceduralWalkCycle = proceduralWalkCycle
ViewmodelSetup.fireSelectorMod     = fireSelectorMod
ViewmodelSetup.bulletHandler       = bulletHandler

return ViewmodelSetup