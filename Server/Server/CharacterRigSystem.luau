-- CharacterRigSystem
-- MakeCharacterRig: creates the third-person weapon rig for a character.

local AssetRefs = require(script.Parent.AssetRefs)

local weldMod = AssetRefs.weldMod
local viewMod = AssetRefs.viewMod

local CharacterRigSystem = {}

function CharacterRigSystem.MakeCharacterRig(char: Model)
	local head  = char:WaitForChild("Head", 20)
	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
	local rig   = viewMod.RigModel(nil, true, head)
	rig.Parent  = char

	local lArmWeld = weldMod.BlankWeld(rig["Left Arm"], char["Left Arm"])
	lArmWeld.Parent = rig
	lArmWeld.Name   = "law"
	rig["Left Arm"].Transparency = 1

	local rArmWeld = weldMod.BlankWeld(rig["Right Arm"], char["Right Arm"])
	rArmWeld.Parent = rig
	rArmWeld.Name   = "raw"
	rig["Right Arm"].Transparency = 1

	local animController = Instance.new("AnimationController", rig)
	local animator       = Instance.new("Animator", animController)

	local animBase = rig:FindFirstChild("AnimBase")
	if animBase then
		for _, motor in ipairs(animBase:GetChildren()) do
			if motor:IsA("Motor6D") and not motor:GetAttribute("OriginalC0_Rest") then
				motor:SetAttribute("OriginalC0_Rest", motor.C0)
			end
		end
	end

	return rig
end

return CharacterRigSystem