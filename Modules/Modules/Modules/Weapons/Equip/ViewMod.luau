local weldMod = require(script.Parent.Parent.Core.WeldMod)
local assets = game:GetService("ReplicatedStorage").SPH_Assets
local models = assets.Viewmodels

local viewMod = {}

viewMod.RigModel = function(player, forceDefault, attachTo)
	local newRig
	if forceDefault then
		local attachingHumanoid:Humanoid = attachTo.Parent:FindFirstChildWhichIsA("Humanoid")
		if attachingHumanoid and attachingHumanoid.RigType ~= Enum.HumanoidRigType.R15 and models:FindFirstChild("R6_Arms") then
			newRig = models.R6_Arms.WeaponRig
		else
			newRig = models.Default.WeaponRig
		end
	elseif player.Neutral or not player.Team or not models:FindFirstChild(player.Team.Name) then
		newRig = models.Default.WeaponRig
	else
		newRig = models[player.Team.Name].WeaponRig
	end

	newRig = newRig:Clone()

	local base = newRig.AnimBase
	local FkCamera = newRig.FakeCamera
	local lArm = newRig["Left Arm"]
	for _, part in ipairs(lArm:GetChildren()) do
		if part:IsA("BasePart") then
			weldMod.Weld(lArm,part)
			part.CanCollide = false
			part.CanQuery = false
		end
	end

	local rArm = newRig["Right Arm"]
	for _, part in ipairs(rArm:GetChildren()) do
		if part:IsA("BasePart") then
			weldMod.Weld(rArm,part)
			part.CanCollide = false
			part.CanQuery = false
		end
	end

	local cameraJoint = weldMod.M6D(newRig.AnimBase,FkCamera)
	cameraJoint.Name = "FakeCamera"

	local leftJoint = weldMod.M6D(newRig.AnimBase,lArm)
	leftJoint.Name = "LeftJoint"

	local rightJoint = weldMod.M6D(newRig.AnimBase,rArm)
	rightJoint.Name = "RightJoint"

	base.Transparency = 1
	base.CanCollide = false
	base.CanQuery = false
	base.CanTouch = false
	base.CastShadow = false

	lArm.CanCollide = false
	lArm.CanQuery = false
	lArm.CanTouch = false
	lArm.CastShadow = true

	rArm.CanCollide = false
	rArm.CanQuery = false
	rArm.CanTouch = false
	rArm.CastShadow = true

	if attachTo then
		local baseWeld = weldMod.BlankWeld(attachTo,newRig.AnimBase)
		baseWeld.Name = "BaseWeld"
		baseWeld.Parent = newRig
	end

	local weaponFolder = Instance.new("Folder",newRig)
	weaponFolder.Name = "Weapon"

	return newRig
end

return viewMod