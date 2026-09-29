--!strict

--// Services
local ContentProvider = game:GetService("ContentProvider")

--// Types
type FakeArmsRig = Model & {
	["Left Arm"]: BasePart,
	["Right Arm"]: BasePart,
}

type WeaponRig = Model & {
	["Left Arm"]: BasePart,
	["Right Arm"]: BasePart,
	FakeArms: FakeArmsRig,
}

--// Configuration

local SYNCED_ARM_PARTS = { "Left Arm", "Right Arm" }
local SYNCED_ARM_PROPERTIES = { "Color" }

--// Rig Reference
local function getWeaponRig(): WeaponRig?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end

	local rig = camera:WaitForChild("WeaponRig", 20)
	if not rig then
		return nil
	end

	return rig :: WeaponRig
end

local newRig: WeaponRig? = getWeaponRig()

--// Generic Property Mirroring

local function mirrorProperty(source: Instance, target: Instance, property: string)
	(target :: any)[property] = (source :: any)[property]
	source:GetPropertyChangedSignal(property):Connect(function()
		(target :: any)[property] = (source :: any)[property]
	end)
end

--// Arm Sync
local function applyArmSync(rig: WeaponRig)
	for _, partName in SYNCED_ARM_PARTS do
		local realPart = rig:FindFirstChild(partName)
		local fakePart = rig.FakeArms:FindFirstChild(partName)

		if realPart and fakePart then
			for _, property in SYNCED_ARM_PROPERTIES do
				mirrorProperty(realPart, fakePart, property)
			end
		end
	end
end

--// Shirt Sync
local function applyShirtSync(rig: WeaponRig)
	local fakeShirt = rig.FakeArms:WaitForChild("Shirt") :: Shirt
	local rigShirt = rig:WaitForChild("Clothing") :: Shirt

	local function applyTemplate()
		local template = rigShirt.ShirtTemplate
		if template ~= "" then
			task.spawn(function()
				ContentProvider:PreloadAsync({ rigShirt })
			end)
		end
		fakeShirt.ShirtTemplate = template
	end

	applyTemplate()
	rigShirt:GetPropertyChangedSignal("ShirtTemplate"):Connect(applyTemplate)
end

--// Listener Setup
local function setupListeners(rig: WeaponRig)
	task.spawn(applyArmSync, rig)
	task.spawn(applyShirtSync, rig)

	rig.Destroying:Connect(function()
		task.wait()
		local nextRig = getWeaponRig()
		newRig = nextRig
		if nextRig then
			setupListeners(nextRig)
		end
	end)
end

--// Initialization
if newRig and newRig.Parent and newRig:FindFirstChild("FakeArms") then
	setupListeners(newRig)
end

return true