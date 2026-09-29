-- Bootstrap/CharacterRefs
-- Character, humanoid, HumanoidRootPart, joints (R6/R15 aware).
-- Returns all character-level references needed across the system.

local CharacterRefs = {}

-- The LocalScript that holds this module lives inside the character
-- (StarterCharacterScripts), so script.Parent.Parent is the character model.
local character: Model      = script.Parent.Parent.Parent.Parent.Parent :: Model  -- Script -> Boot -> LocalScript -> Character
local humanoid: Humanoid    = character:WaitForChild("Humanoid")         :: Humanoid
local humanoidRootPart: BasePart = character:WaitForChild("HumanoidRootPart") :: BasePart
local rootJoint: Motor6D    = humanoidRootPart:WaitForChild("RootJoint") :: Motor6D

CharacterRefs.character         = character
CharacterRefs.humanoid          = humanoid
CharacterRefs.humanoidRootPart  = humanoidRootPart
CharacterRefs.rootJoint         = rootJoint

-- Joints (rig-type aware)
local neckJoint: Motor6D?
local leftHipJoint: Motor6D?
local rightHipJoint: Motor6D?
local defaultLeftHipC0: CFrame?
local defaultRightHipC0: CFrame?

if humanoid.RigType == Enum.HumanoidRigType.R6 then
	local torso = character:FindFirstChild("Torso")
	if torso and torso:IsA("BasePart") then
		neckJoint      = torso:FindFirstChild("Neck")      :: Motor6D?
		leftHipJoint   = torso:FindFirstChild("Left Hip")  :: Motor6D?
		rightHipJoint  = torso:FindFirstChild("Right Hip") :: Motor6D?
		if leftHipJoint  then defaultLeftHipC0  = leftHipJoint.C0  end
		if rightHipJoint then defaultRightHipC0 = rightHipJoint.C0 end
	end
elseif humanoid.RigType == Enum.HumanoidRigType.R15 then
	local upperTorso = character:FindFirstChild("UpperTorso")
	if upperTorso and upperTorso:IsA("BasePart") then
		neckJoint = upperTorso:FindFirstChild("Neck") :: Motor6D?
	end
end

CharacterRefs.neckJoint           = neckJoint
CharacterRefs.leftHipJoint        = leftHipJoint
CharacterRefs.rightHipJoint       = rightHipJoint
CharacterRefs.defaultLeftHipC0    = defaultLeftHipC0
CharacterRefs.defaultRightHipC0   = defaultRightHipC0

return CharacterRefs