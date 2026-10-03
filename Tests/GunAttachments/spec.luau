-- GunAttachments isolation tests. Run via Tests/GunAttachments/run.py
local Mocks = require("./mocks")
local GunAttachments = require("./GunAttachments")

local make, CF = Mocks.make, Mocks.CFrame.new

-- ─── tiny test framework ────────────────────────────────────────────────────
local passed, failed = 0, 0
local current = ""
local function test(name, fn)
	current = name
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end
local function eq(actual, expected, label)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label or "value", tostring(expected), tostring(actual)), 2)
	end
end
local function truthy(value, label)
	if not value then
		error((label or "expected truthy") .. " (got " .. tostring(value) .. ")", 2)
	end
end

-- ─── fixtures ───────────────────────────────────────────────────────────────
local warnings = {}
local function newSystem(extra)
	local heartbeat = Mocks.newSignal()
	local tweens = {}
	local options = {
		contentRoot = nil,
		services = {
			newInstance = Mocks.Instance.new,
			identityCFrame = CF(),
			http = Mocks.Http,
			heartbeat = heartbeat,
			tween = function(part, duration, delay, goals)
				table.insert(tweens, { part = part, duration = duration, delay = delay, goals = goals })
				for key, value in pairs(goals) do
					part[key] = value
				end
			end,
			require = function(module)
				local value = module:GetAttribute("__module")
				if value == "error" then
					error("boom")
				end
				return rawget(module, "_value")
			end,
		},
		log = { warn = function(...) table.insert(warnings, table.concat({ ... }, " ")) end },
	}
	for key, value in pairs(extra or {}) do
		if key == "services" or key == "hooks" then
			options[key] = options[key] or {}
			for k, v in pairs(value) do
				options[key][k] = v
			end
		else
			options[key] = value
		end
	end
	local system = GunAttachments.new(options)
	return system, heartbeat, tweens
end

local function moduleScript(value, parent)
	local module = make("ModuleScript", { Name = "Customization", Parent = parent })
	rawset(module, "_value", value)
	return module
end

-- content: <root>/<Slot>/<Name>/{parts..., Customization}
local function addContent(root, slot, name, config, parts)
	local slotFolder = root:FindFirstChild(slot) or make("Folder", { Name = slot, Parent = root })
	local folder = make("Folder", { Name = name, Parent = slotFolder })
	for _, part in ipairs(parts) do
		part.Parent = folder
	end
	moduleScript(config, folder)
	return folder
end

local function newGun()
	local model = make("Model", { Name = "MP5" })
	local grip = make("Part", { Name = "Grip", Parent = model, CFrame = CF() })
	local opticPart = make("Part", { Name = "OpticPart", Parent = model })
	make("Attachment", { Name = "RedDot", Parent = opticPart, CFrame = CF(1, 0, 0) })
	make("Attachment", { Name = "ACOG", Parent = opticPart, CFrame = CF(1, 0, 0) })
	local muzzlePart = make("Part", { Name = "MuzzlePart", Parent = model })
	make("Attachment", { Name = "Suppressor", Parent = muzzlePart })
	local gripPart = make("Part", { Name = "GripPart", Parent = model })
	make("Attachment", { Name = "VGrip", Parent = gripPart })
	make("Attachment", { Name = "LaserBox", Parent = gripPart })
	make("Part", { Name = "IronSight", Parent = model, Transparency = 0.3 })
	local barrel = make("Part", { Name = "Barrel", Parent = grip, Transparency = 0.1 })
	make("Attachment", { Name = "Muzzle", Parent = barrel })
	make("ParticleEmitter", { Name = "Smoke", Parent = barrel })
	model.Parent = make("Folder", { Name = "Workspace" })
	return model
end

local calls = {}
local function newContent()
	local root = make("Folder", { Name = "GunAttachments" })
	addContent(root, "Optics", "RedDot", {
		IsCompatible = function(weaponName) return weaponName == "MP5" end,
		MountOffset = CF(0, 1, 0),
		HideGunParts = { "IronSight" },
		VisibleParts = { "Lens" },
		TransparentOnADS = { "Body" },
		ReticleConfig = { Color = "red" },
		DepthOfField = { Enabled = true },
		ApplyStats = function(stats) stats.damage += 5; return stats end,
		OnEquip = function(...) table.insert(calls, { "equip", ... }) end,
		OnUnequip = function(...) table.insert(calls, { "unequip", ... }) end,
	}, {
		make("Part", { Name = "Lens", CFrame = CF(10, 2, 0), Transparency = 1 }),
		make("MeshPart", { Name = "Body", CFrame = CF(10, 0, 0) }),
		make("Part", { Name = "AimPart", CFrame = CF(10, 1, 0) }),
		make("Part", { Name = "AimPart2", CFrame = CF(10, 3, 0) }),
	})
	addContent(root, "Optics", "ACOG", {
		IsCompatible = function() return 1 end, -- truthy, not true
		ApplyStats = function(stats) stats.zoom = 4 end, -- returns nil: in-place edit kept
	}, { make("Part", { Name = "Scope" }) })
	local suppressor = make("MeshPart", { Name = "Can" })
	make("Attachment", { Name = "Muzzle", Parent = suppressor })
	addContent(root, "Muzzle", "Suppressor", {
		IsCompatible = function() return true end,
		EnableSilencer = true,
		overHeating = { Enabled = true },
		ApplyStats = function(stats) stats.damage *= 2; return stats end,
	}, { suppressor })
	local gripRoot = make("MeshPart", { Name = "Handle" })
	make("Attachment", { Name = "HandPos", Parent = gripRoot, CFrame = CF(0, 0, 5) })
	addContent(root, "Underbarrel", "VGrip", {
		IsCompatible = function() return true end,
		EnableHandPositioning = true,
		HandGripPart = "HandPos",
		ApplyStats = function() error("bad modifier") end,
	}, { gripRoot })
	local laserRoot = make("MeshPart", { Name = "Box" })
	make("Attachment", { Name = "Laser", Parent = laserRoot })
	make("Beam", { Name = "Beam", Parent = laserRoot })
	make("Part", { Name = "Flashlight", Parent = laserRoot })
	addContent(root, "Underbarrel", "LaserBox", {
		-- no IsCompatible: treated as compatible (old code errored)
		EnableLaser = true,
		EnableFlashlight = true,
		OnUpdate = function(...) table.insert(calls, { "update", ... }) end,
	}, { laserRoot })
	return root
end

local function newTool(name)
	return make("Tool", { Name = name or "MP5" })
end

-- ─── tests ──────────────────────────────────────────────────────────────────

test("defaults: slot part names and validity", function()
	local system = newSystem()
	eq(system:GetSlotPartName("Optics"), "OpticPart")
	eq(system:GetSlotPartName("Underbarrel"), "GripPart")
	eq(system:GetSlotPartName("Muzzle"), "MuzzlePart")
	eq(system:GetSlotPartName("Stock"), "StockPart")
	eq(system:IsValidSlot("Optics"), true)
	eq(system:IsValidSlot("Barrel"), false)
	eq(system:IsValidSlot(5), false)
	eq(system:GetSlotForRole("muzzle"), "Muzzle")
	eq(#system:GetSlots(), 4)
end)

test("allowUnknownSlots reproduces the old '<Slot>Part' fallback", function()
	local system = newSystem({ allowUnknownSlots = true })
	eq(system:GetSlotPartName("Barrel"), "BarrelPart")
	eq(system:IsValidSlot("Barrel"), true)
end)

test("registry: load, cache, missing, failing module", function()
	local root = newContent()
	local system = newSystem({ contentRoot = root })
	local a = system:LoadConfig("Optics", "RedDot")
	truthy(a, "config loaded")
	eq(system:LoadConfig("Optics", "RedDot"), a, "cached identity")
	eq(system:LoadConfig("Optics", "Nope"), nil)
	eq(system:LoadConfig("Nope", "RedDot"), nil)
	local bad = addContent(root, "Optics", "Broken", {}, { make("Part", {}) })
	bad.Customization:SetAttribute("__module", "error")
	eq(system:LoadConfig("Optics", "Broken"), nil, "erroring config")
end)

test("contentRoot may be a function (lazy lookup)", function()
	local root = newContent()
	local system = newSystem({ contentRoot = function() return root end })
	truthy(system:LoadConfig("Muzzle", "Suppressor"))
end)

test("equip: builds node, motors, visibility, callbacks", function()
	table.clear(calls)
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	local ok, reason = system:Equip(gun, tool, "Optics", "RedDot", "PLAYER")
	eq(ok, true, "equip ok (" .. tostring(reason) .. ")")
	local node = gun.OpticPart:FindFirstChild("RedDot_Equipped")
	truthy(node, "node folder created")
	local body = node:FindFirstChild("Body")
	local lens = node:FindFirstChild("Lens")
	truthy(body and lens, "parts cloned")
	local rootMotor = body:FindFirstChild("AttachmentMotor_Root_RedDot")
	truthy(rootMotor, "root motor")
	eq(rootMotor.Part0, gun.OpticPart, "root Part0 is mount host")
	eq(rootMotor.Part1, body)
	eq(rootMotor.C0, CF(1, 1, 0), "root C0 = mount.CFrame * MountOffset")
	local lensMotor = lens:FindFirstChild("AttachmentMotor_Lens")
	eq(lensMotor.Part0, body)
	eq(lensMotor.C0, CF(0, 2, 0), "relative layout preserved")
	eq(body.CanCollide, false)
	eq(body.Massless, true)
	eq(lens.Transparency, 0, "VisibleParts shown")
	eq(gun.IronSight.Transparency, 1, "HideGunParts hidden")
	eq(#calls, 1)
	eq(calls[1][2], "PLAYER", "OnEquip owner")
	eq(calls[1][3], tool, "OnEquip tool")
	eq(calls[1][4], node, "OnEquip node")
	local record = system:GetRecord(gun, "Optics")
	eq(record.model, node, "legacy .model field")
	eq(record.attachmentName, "RedDot")
end)

test("equip: same attachment twice is a no-op", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	system:Equip(gun, tool, "Optics", "RedDot")
	local node = system:GetRecord(gun, "Optics").node
	eq(system:Equip(gun, tool, "Optics", "RedDot"), true)
	eq(system:GetRecord(gun, "Optics").node, node, "node not rebuilt")
end)

test("equip: incompatible / missing mount leave nothing behind", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun = newGun()
	eq(system:Equip(gun, newTool("AK"), "Optics", "RedDot"), false, "incompatible")
	eq(gun.OpticPart:FindFirstChild("RedDot_Equipped"), nil)
	gun.OpticPart.RedDot:Destroy()
	eq(system:Equip(gun, newTool(), "Optics", "RedDot"), false, "missing mount")
	for _, d in ipairs(gun:GetDescendants()) do
		if d.Name:match("_Equipped$") then
			error("stray node " .. d.Name)
		end
	end
	eq(system:Equip(gun, newTool(), "Barrel", "X"), false, "unknown slot")
end)

test("equip: truthy IsCompatible and missing IsCompatible accepted", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	eq(system:Equip(gun, tool, "Optics", "ACOG"), true, "truthy compat")
	table.clear(warnings)
	eq(system:Equip(gun, tool, "Underbarrel", "LaserBox"), true, "no IsCompatible")
	truthy(#warnings == 1 and warnings[1]:find("IsCompatible"), "warned once")
end)

test("swap in same slot unequips previous", function()
	table.clear(calls)
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	system:Equip(gun, tool, "Optics", "RedDot")
	local oldNode = system:GetRecord(gun, "Optics").node
	system:Equip(gun, tool, "Optics", "ACOG")
	eq(oldNode.Parent, nil, "old node destroyed")
	eq(system:GetRecord(gun, "Optics").attachmentName, "ACOG")
	eq(gun.IronSight.Transparency, 0.3, "hidden part restored to original")
	eq(calls[2][1], "unequip")
	eq(calls[2][2], nil, "OnUnequip arg1 nil")
	eq(calls[2][3], nil, "OnUnequip arg2 nil")
	eq(calls[2][4], oldNode, "OnUnequip node")
end)

test("muzzle override hides original, publishes ActiveCustomMuzzle, restores", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	local barrel = gun.Grip.Barrel
	eq(system:Equip(gun, tool, "Muzzle", "Suppressor"), true)
	eq(barrel.Transparency, 1, "original muzzle host hidden")
	eq(barrel.Smoke.Enabled, false, "emitter disabled")
	eq(barrel:GetAttribute("OriginalTransparency_Muzzle"), 0.1)
	eq(barrel.Muzzle:GetAttribute("OverriddenByAttachment"), true)
	eq(gun:GetAttribute("ActiveCustomMuzzle"), "Suppressor")
	local active = system:GetActiveMuzzle(gun)
	eq(active.Parent.Name, "Can", "active muzzle is the attachment's")
	eq(system:GetConfigField(gun, "Muzzle", "overHeating").Enabled, true)
	system:Unequip(gun, "Muzzle")
	eq(barrel.Transparency, 0.1, "restored")
	eq(barrel.Smoke.Enabled, true)
	eq(barrel:GetAttribute("OriginalTransparency_Muzzle"), nil)
	eq(gun:GetAttribute("ActiveCustomMuzzle"), nil)
	eq(system:GetActiveMuzzle(gun), nil, "Grip.Muzzle (non-recursive) fallback")
end)

test("pre-hidden muzzle stays hidden after unequip; cleanup clears marker", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	system:PreHideOriginalMuzzle(gun)
	system:Equip(gun, tool, "Muzzle", "Suppressor")
	system:Unequip(gun, "Muzzle")
	eq(gun.Grip.Barrel.Transparency, 1, "still hidden")
	system:CleanupMuzzleState(gun)
	eq(gun.Grip.Barrel:GetAttribute("MuzzlePreHidden"), nil)
end)

test("ownership: another tool on same model resets it", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun = newGun()
	local toolA, toolB = newTool(), newTool()
	system:Equip(gun, toolA, "Optics", "RedDot")
	system:Equip(gun, toolB, "Muzzle", "Suppressor")
	eq(system:Has(gun, "Optics"), false, "previous owner's attachments removed")
	eq(system:Has(gun, "Muzzle"), true)
	eq(system:GetOwner(gun), toolB)
end)

test("stats: deep copy isolation and deterministic slot order", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	local base = { damage = 10, nested = { a = 1 } }
	system:SetBaseStats(tool, base)
	base.damage = 999
	base.nested.a = 999
	eq(system:GetBaseStats(tool).damage, 10, "stored copy isolated")
	-- equip muzzle first, then optic: order must still be Optics (+5) then Muzzle (*2)
	system:Equip(gun, tool, "Muzzle", "Suppressor")
	system:Equip(gun, tool, "Optics", "RedDot")
	local computed = system:ComputeStats(tool, gun)
	eq(computed.damage, 30, "(10 + 5) * 2")
	eq(system:GetBaseStats(tool).damage, 10, "base untouched by modifiers")
	truthy(tool:GetAttribute("ModifiedStats"), "modified snapshot written")
end)

test("stats: nil-returning and erroring modifiers", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	system:SetBaseStats(tool, { damage = 10 })
	system:Equip(gun, tool, "Optics", "ACOG")
	system:Equip(gun, tool, "Underbarrel", "VGrip")
	table.clear(warnings)
	local computed = system:ComputeStats(tool, gun)
	eq(computed.zoom, 4, "in-place edit kept when modifier returns nil")
	eq(computed.damage, 10)
	truthy(warnings[1] and warnings[1]:find("bad modifier"), "erroring modifier reported")
end)

test("stats: resolveModel hook, foreign owner, untracked model", function()
	local gun = newGun()
	local system = newSystem({ contentRoot = newContent(), hooks = { resolveModel = function() return gun end } })
	local tool, other = newTool(), newTool()
	system:SetBaseStats(tool, { damage = 10 })
	system:SetBaseStats(other, { damage = 10 })
	eq(system:ComputeStats(tool).damage, 10, "untracked → base copy")
	system:Equip(gun, tool, "Optics", "RedDot")
	eq(system:ComputeStats(tool).damage, 15, "resolved model used")
	eq(system:ComputeStats(other, gun).damage, 10, "foreign owner → base copy")
	eq(system:ComputeStats(newTool()), nil, "no base stats → nil")
end)

test("stats: snapshot restore in a second system + hook", function()
	local tool = newTool()
	local first = newSystem()
	first:SetBaseStats(tool, { damage = 7 })
	local restored = nil
	local second = newSystem({ hooks = { onSnapshotRestored = function(t, stats) restored = t; stats.patched = true end } })
	local stats = second:GetBaseStats(tool)
	eq(stats.damage, 7)
	eq(stats.patched, true)
	eq(restored, tool)
end)

test("loadout: sanitize, write, read, JSON mirror", function()
	local system = newSystem()
	local clean = system:SanitizeLoadout({
		Optics = "RedDot", Muzzle = "", Stock = string.rep("x", 65), Bogus = "A", [1] = "B", Underbarrel = 5,
	})
	eq(clean.Optics, "RedDot")
	eq(clean.Muzzle, nil)
	eq(clean.Stock, nil)
	eq(clean.Bogus, nil)
	eq(clean[1], nil)
	eq(clean.Underbarrel, nil)
	eq(next(system:SanitizeLoadout("nope")), nil, "non-table → empty")
	local tool = newTool()
	system:SetLoadout(tool, { Optics = "RedDot", Muzzle = "Suppressor" })
	local folder = tool.SavedAttachments
	truthy(folder, "folder created")
	eq(#folder:GetChildren(), 2)
	eq(folder.Optics.Value, "RedDot")
	truthy(tool:GetAttribute("SavedAttachmentsJSON"), "json mirror")
	system:SetLoadout(tool, { Stock = "Tac" })
	eq(folder.Parent, nil, "old folder replaced (destroyed)")
	eq(#tool:GetChildren(), 1, "exactly one SavedAttachments folder")
	eq(#tool.SavedAttachments:GetChildren(), 1)
	local loadout = system:GetLoadout(tool)
	eq(loadout.Stock, "Tac")
	eq(loadout.Optics, nil)
	eq(system:HasLoadout(newTool()), false)
end)

test("stats: cache survives until the tool is destroyed", function()
	local system = newSystem()
	local tool = newTool()
	system:SetBaseStats(tool, { damage = 3, fn = function() end })
	tool:SetAttribute("OriginalStats", nil) -- prove we are not reading the snapshot
	eq(type(system:GetBaseStats(tool).fn), "function", "strong cache keeps non-JSON fields")
	tool:Destroy()
	eq(system:GetBaseStats(tool), nil, "released on Destroying")
end)

test("loadout: filterLoadout hook", function()
	local system = newSystem({ hooks = { filterLoadout = function(_, l) l.Optics = nil; return l end } })
	local clean = system:SanitizeLoadout({ Optics = "RedDot", Muzzle = "Suppressor" })
	eq(clean.Optics, nil)
	eq(clean.Muzzle, "Suppressor")
end)

test("loadout: ApplyLoadout + LoadoutHasFlag", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	system:SetLoadout(tool, { Optics = "RedDot", Muzzle = "Suppressor", Stock = "Missing" })
	local results = system:ApplyLoadout(gun, tool, nil)
	eq(results.Optics, true)
	eq(results.Muzzle, true)
	eq(results.Stock, false)
	eq(system:LoadoutHasFlag(tool, "EnableSilencer"), true)
	eq(system:LoadoutHasFlag(tool, "EnableSilencer", "Optics"), false)
	eq(system:LoadoutHasFlag(newTool(), "EnableSilencer"), false)
	-- re-apply on a dirty model: stale nodes are rebuilt, not duplicated
	system:ApplyLoadout(gun, tool, nil)
	local count = 0
	for _, d in ipairs(gun:GetDescendants()) do
		if d.Name == "RedDot_Equipped" then
			count += 1
		end
	end
	eq(count, 1, "single node after re-apply")
end)

test("scheduler: OnUpdate runs only while mounted", function()
	table.clear(calls)
	local system, heartbeat = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	eq(heartbeat:Count(), 0, "idle: not connected")
	system:Equip(gun, tool, "Underbarrel", "LaserBox")
	eq(heartbeat:Count(), 1, "connected")
	heartbeat:Fire(0.016)
	local update = calls[#calls]
	eq(update[1], "update")
	eq(update[2], nil)
	eq(update[3], nil)
	eq(update[4], 0.016, "OnUpdate(nil, nil, dt)")
	system:Unequip(gun, "Underbarrel")
	eq(heartbeat:Count(), 0, "disconnected")
end)

test("model destroy purges state and updaters", function()
	local system, heartbeat = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	system:Equip(gun, tool, "Underbarrel", "LaserBox")
	gun:Destroy()
	eq(system:IsTracked(gun), false)
	eq(next(system:GetActive(gun)), nil)
	eq(heartbeat:Count(), 0)
end)

test("laser / flashlight precedence", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	eq(system:GetLaserSource(gun), nil, "no laser anywhere")
	eq(system:GetFlashlightSource(gun), nil)
	system:Equip(gun, tool, "Underbarrel", "LaserBox")
	eq(system:AnyActiveFlag(gun, "EnableLaser"), true)
	local laser = system:GetLaserSource(gun)
	eq(laser.Parent.Name, "Box", "attachment laser")
	eq(laser.Parent.Beam.Enabled, false, "beams disabled on mount")
	eq(system:GetFlashlightSource(gun).Parent.Name, "Box", "attachment flashlight")
	-- built-in Grip.Flashlight wins for flashlight; attachment still wins for laser
	make("Part", { Name = "Flashlight", Parent = gun.Grip })
	make("Attachment", { Name = "Laser", Parent = gun.Grip })
	eq(system:GetFlashlightSource(gun).Parent, gun.Grip, "Grip.Flashlight first")
	eq(system:GetLaserSource(gun).Parent.Name, "Box", "attachment laser first")
	system:Unequip(gun, "Underbarrel")
	eq(system:GetLaserSource(gun).Parent, gun.Grip, "falls back to Grip.Laser")
end)

test("optic queries: aim part index, configs, ADS tween", function()
	local system, _, tweens = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	eq(system:GetAimPart(gun, 1), nil, "no optic")
	system:Equip(gun, tool, "Optics", "RedDot")
	eq(system:GetAimPart(gun, 1).Name, "AimPart")
	eq(system:GetAimPart(gun, 2).Name, "AimPart2")
	eq(system:GetAimPart(gun, 3).Name, "AimPart", "falls back to AimPart")
	eq(system:GetConfigField(gun, "Optics", "ReticleConfig").Color, "red")
	eq(system:GetConfigField(gun, "Optics", "DepthOfField").Enabled, true)
	system:ApplyADSVisibility(gun, true, 4)
	eq(#tweens, 1)
	eq(tweens[1].part.Name, "Body")
	eq(tweens[1].duration, 0.2, "aimTime / 20")
	eq(tweens[1].delay, 0.2)
	eq(tweens[1].goals.Transparency, 1)
	system:ApplyADSVisibility(gun, false, nil)
	eq(tweens[2].duration, 0.2, "fallback 0.2")
	eq(tweens[2].goals.Transparency, 0)
end)

test("grip data", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	eq(system:GetGripData(gun), nil)
	eq(system:HasHandGrip(gun), false)
	system:Equip(gun, tool, "Underbarrel", "VGrip")
	eq(system:HasHandGrip(gun), true)
	local data = system:GetGripData(gun)
	eq(data.handToPosition, "Left Arm")
	eq(data.transitionSpeed, 15)
	eq(data.matchRotation, true)
	truthy(data.gripWorldCFrame, "world cframe")
end)

test("GetActive is a frozen copy", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	system:Equip(gun, tool, "Optics", "RedDot")
	local active = system:GetActive(gun)
	truthy(active.Optics, "has optics")
	local ok = pcall(function() active.Muzzle = {} end)
	eq(ok, false, "cannot mutate")
	local okRecord = pcall(function() active.Optics.config = nil end)
	eq(okRecord, false, "records frozen")
	eq(next(system:GetActive(newGun())), nil, "untracked → empty")
end)

test("ResetModel vs ClearModel tracking + stray node purge", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	make("Folder", { Name = "Old_Equipped", Parent = gun.OpticPart })
	system:ResetModel(gun)
	eq(gun.OpticPart:FindFirstChild("Old_Equipped"), nil, "stray purged")
	eq(system:IsTracked(gun), true, "Reset keeps tracking")
	system:Equip(gun, tool, "Muzzle", "Suppressor")
	system:ClearModel(gun)
	eq(system:IsTracked(gun), false, "Clear forgets")
	eq(system:GetOwner(gun), nil)
	eq(gun:GetAttribute("ActiveCustomMuzzle"), nil)
end)

test("signals fire and handler errors are isolated", function()
	local system = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	local seen = {}
	system.Equipped:Connect(function() error("handler crash") end)
	system.Equipped:Connect(function(model, record) table.insert(seen, record.attachmentName) end)
	system.Unequipped:Connect(function(model, slot, name) table.insert(seen, "-" .. name) end)
	eq(system:Equip(gun, tool, "Optics", "RedDot"), true, "equip survives handler crash")
	system:Unequip(gun, "Optics")
	eq(seen[1], "RedDot")
	eq(seen[2], "-RedDot")
end)

test("independent systems do not share state", function()
	local content = newContent()
	local a = newSystem({ contentRoot = content })
	local b = newSystem({ contentRoot = content })
	local gun, tool = newGun(), newTool()
	a:Equip(gun, tool, "Optics", "RedDot")
	eq(b:Has(gun, "Optics"), false)
end)

test("Destroy tears everything down", function()
	local system, heartbeat = newSystem({ contentRoot = newContent() })
	local gun, tool = newGun(), newTool()
	system:Equip(gun, tool, "Underbarrel", "LaserBox")
	system:Destroy()
	eq(heartbeat:Count(), 0)
	eq(gun.GripPart:FindFirstChild("LaserBox_Equipped"), nil)
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("tests failed")
end
