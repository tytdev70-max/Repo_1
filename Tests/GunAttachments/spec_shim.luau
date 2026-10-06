-- Verifies the deprecated AttachmentManager shim maps every legacy call (and its
-- argument order) onto the new API correctly. Run via Tests/GunAttachments/run.py
local Mocks = require("./mocks")
local AM = require("./AttachmentManager") -- shim, wired to the mock-backed system
local System = AM.System
local make, CF = Mocks.make, Mocks.CFrame.new

local passed, failed = 0, 0
local function test(name, fn)
	local ok, err = pcall(fn)
	if ok then passed += 1 else failed += 1; print("FAIL  " .. name .. "\n      " .. tostring(err)) end
end
local function eq(a, b, label)
	if a ~= b then error(("%s: expected %s, got %s"):format(label or "value", tostring(b), tostring(a)), 2) end
end

local root = System._contentRootForTests
local function gun()
	local model = make("Model", { Name = "MP5" })
	local grip = make("Part", { Name = "Grip", Parent = model })
	make("Attachment", { Name = "Muzzle", Parent = make("Part", { Name = "Barrel", Parent = grip }) })
	make("Attachment", { Name = "RedDot", Parent = make("Part", { Name = "OpticPart", Parent = model }) })
	make("Attachment", { Name = "Can", Parent = make("Part", { Name = "MuzzlePart", Parent = model }) })
	make("Attachment", { Name = "Grip1", Parent = make("Part", { Name = "GripPart", Parent = model }) })
	model.Parent = make("Folder", { Name = "Workspace" })
	return model
end
local tool = make("Tool", { Name = "MP5" })

test("EquipAttachment(player, tool, model, name, category) argument order", function()
	local model = gun()
	local seenOwner
	System.Equipped:Once(function(_, record) seenOwner = record.tool end)
	eq(AM.EquipAttachment("PLAYER", tool, model, "RedDot", "Optics"), true)
	eq(seenOwner, tool, "tool forwarded")
	eq(AM.HasAttachment(model, "Optics"), true)
	eq(AM.GetActiveAttachments(model).Optics.attachmentName, "RedDot")
	eq(AM.GetActiveAttachments(model).Optics.model.Name, "RedDot_Equipped", "legacy .model")
	eq(AM.LoadAttachmentConfig("RedDot", "Optics").Tag, "reddot", "LoadAttachmentConfig(name, category)")
	eq(AM.GetAttachmentAimPart(model, 1).Name, "AimPart")
	eq(AM.GetReticleConfig(model).Color, "red")
	eq(AM.GetDepthOfFieldConfig(model).Enabled, true)
end)

test("muzzle helpers", function()
	local model = gun()
	AM.EquipAttachment(nil, tool, model, "Can", "Muzzle")
	eq(AM.HasMuzzleOverride(model), true)
	eq(AM.GetMuzzleAttachmentConfig(model).Tag, "can")
	eq(AM.GetOverheatConfig(model).Enabled, true)
	eq(AM.GetActiveMuzzle(model).Parent.Name, "Body")
	AM.UnequipAttachment(model, "Muzzle")
	eq(AM.HasMuzzleOverride(model), false)
end)

test("grip / laser / flashlight helpers", function()
	local model = gun()
	AM.EquipAttachment(nil, tool, model, "Grip1", "Underbarrel")
	eq(AM.HasGripEquipped(model), true)
	eq(AM.GetGripHandPosition(model, "MP5").handToPosition, "Left Arm")
	eq(AM.HasLaserAttachment(model), true)
	eq(AM.HasFlashlightAttachment(model), true)
	eq(AM.GetLaserSource(model).Name, "Laser")
	eq(AM.GetFlashlightLights(model).part.Name, "Flashlight")
end)

test("stats helpers", function()
	local model = gun()
	AM.StoreOriginalStats(tool, { damage = 10, aimTime = 4 })
	AM.EquipAttachment(nil, tool, model, "RedDot", "Optics")
	eq(AM.ApplyAttachmentStats(tool, model).damage, 11)
	eq(AM.RestoreStatsFromTool(tool).damage, 10)
end)

test("Prepare / Clear", function()
	local model = gun()
	AM.EquipAttachment(nil, tool, model, "RedDot", "Optics")
	AM.PrepareForEquip(model)
	eq(AM.HasAttachment(model, "Optics"), false)
	eq(System:IsTracked(model), true)
	AM.EquipAttachment(nil, tool, model, "RedDot", "Optics")
	AM.ClearAllAttachments(model)
	eq(System:IsTracked(model), false)
	AM.DebugMuzzleState(model) -- no-op, must not error
	AM.ClearOriginalStats(tool)
end)

print(("\nshim: %d passed, %d failed"):format(passed, failed))
if failed > 0 then error("shim tests failed") end
