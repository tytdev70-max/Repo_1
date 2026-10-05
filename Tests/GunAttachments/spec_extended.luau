-- Extended-capacity tests: rules (capacity/conflicts), content listing, CanEquip,
-- multi-slot roles (dual sights, stacked muzzles) and the Customize UI's pure modules
-- (Selection, Catalog, Config). Run via Tests/GunAttachments/run.py
local Mocks = require("./mocks")
local GunAttachments = require("./GunAttachments")
local Selection = require("./Customize/Selection")
local Catalog = require("./Customize/Catalog")
local Config = require("./Customize/Config")

local make, CF = Mocks.make, Mocks.CFrame.new

local passed, failed = 0, 0
local function test(name, fn)
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
local function under(instance, ancestorName)
	local node = instance and instance.Parent
	while node do
		if node.Name == ancestorName then
			return true
		end
		node = node.Parent
	end
	return false
end
local function keys(t)
	local list = {}
	for k in pairs(t) do
		table.insert(list, k)
	end
	table.sort(list)
	return table.concat(list, ",")
end

-- The SPH slot list (same as Weapons/Attachments/SPHAttachments).
local SLOTS = {
	{ name = "Optics", mountPart = "OpticPart", order = 1, role = "optic" },
	{ name = "Underbarrel", mountPart = "GripPart", order = 2, role = "grip" },
	{ name = "Muzzle", mountPart = "MuzzlePart", order = 3, role = "muzzle", overridesMuzzle = true },
	{ name = "Stock", mountPart = "StockPart", order = 4 },
	{ name = "Barrel", mountPart = "BarrelPart", order = 2.5, role = "muzzle", overridesMuzzle = true },
	{ name = "Magazine", mountPart = "MagazinePart", order = 5 },
	{ name = "SecondaryOptic", mountPart = "SecondaryOpticPart", order = 6, role = "optic" },
}

local function addContent(root, slot, name, config, parts, attributes)
	local slotFolder = root:FindFirstChild(slot) or make("Folder", { Name = slot, Parent = root })
	local folder = make("Folder", { Name = name, Parent = slotFolder })
	for _, part in ipairs(parts or { make("MeshPart", { Name = "Body", CFrame = CF() }) }) do
		part.Parent = folder
	end
	local module = make("ModuleScript", { Name = "Customization", Parent = folder })
	rawset(module, "_value", config)
	for key, value in pairs(attributes or {}) do
		folder:SetAttribute(key, value)
	end
	return folder
end

local function withMuzzle(name)
	local body = make("MeshPart", { Name = "Body", CFrame = CF() })
	make("Attachment", { Name = "Muzzle", Parent = body })
	return { body }
end

local function newContent()
	local root = make("Folder", { Name = "GunAttachments" })
	addContent(root, "Optics", "RedDot", { DisplayName = "Red Dot" }, {
		make("MeshPart", { Name = "Body", CFrame = CF() }),
		make("Part", { Name = "AimPart", CFrame = CF(0, 1, 0) }),
		make("Part", { Name = "AimPart2", CFrame = CF(0, 2, 0) }),
	})
	addContent(root, "Optics", "Scope", { IsCompatible = function(weaponName) return weaponName == "Sniper" end })
	addContent(root, "SecondaryOptic", "Canted", {}, {
		make("MeshPart", { Name = "Body", CFrame = CF() }),
		make("Part", { Name = "AimPart", CFrame = CF(5, 0, 0) }),
	}, { DisplayName = "Canted Dot", Icon = "rbxassetid://1" })
	addContent(root, "Underbarrel", "VGrip", { ConflictsWith = { "Magazine/Drum" } })
	addContent(root, "Muzzle", "Comp", { EnableSilencer = false }, withMuzzle())
	addContent(root, "Muzzle", "Suppressor", { EnableSilencer = true, ConflictsWith = { "Barrel" } }, withMuzzle())
	addContent(root, "Barrel", "Long", {}, withMuzzle())
	addContent(root, "Magazine", "Drum", { ApplyStats = function(s) s.mag = 50; return s end })
	addContent(root, "Magazine", "Extended", {})
	make("Folder", { Name = "NoConfig", Parent = root:FindFirstChild("Magazine") }) -- ignored by ListContent
	return root
end

local function newGun(withNewMounts)
	local model = make("Model", { Name = "M4" })
	local grip = make("Part", { Name = "Grip", Parent = model, CFrame = CF() })
	local barrelPart = make("Part", { Name = "Barrel", Parent = grip })
	make("Attachment", { Name = "Muzzle", Parent = barrelPart })
	local function mount(partName, names)
		local part = make("Part", { Name = partName, Parent = model })
		for _, name in ipairs(names) do
			make("Attachment", { Name = name, Parent = part })
		end
	end
	mount("OpticPart", { "RedDot", "Scope" })
	mount("GripPart", { "VGrip" })
	mount("MuzzlePart", { "Comp", "Suppressor" })
	if withNewMounts then
		mount("BarrelPart", { "Long" })
		mount("MagazinePart", { "Drum", "Extended" })
		mount("SecondaryOpticPart", { "Canted" })
	end
	model.Parent = make("Folder", { Name = "Workspace" })
	return model
end

local function newSystem(extra)
	local root = newContent()
	local options = {
		contentRoot = root,
		slots = SLOTS,
		allowUnknownSlots = false,
		services = {
			newInstance = Mocks.Instance.new,
			identityCFrame = CF(),
			http = Mocks.Http,
			heartbeat = Mocks.newSignal(),
			tween = function() end,
			require = function(module)
				return rawget(module, "_value")
			end,
		},
		log = false,
	}
	for key, value in pairs(extra or {}) do
		options[key] = value
	end
	return GunAttachments.new(options), root
end

local function newTool(name)
	return make("Tool", { Name = name or "M4" })
end

-- ─── package: rules ─────────────────────────────────────────────────────────

test("rules: declared conflicts resolved in slot order", function()
	local system = newSystem()
	local clean = system:SanitizeLoadout({ Optics = "RedDot", Underbarrel = "VGrip", Magazine = "Drum", Muzzle = "Suppressor", Barrel = "Long" }, newTool())
	-- VGrip<->Drum and Suppressor<->Barrel are declared conflicts, so those are dropped;
	-- everything else stays. (No capacity configured.)
	eq(keys(clean), "Barrel,Optics,Underbarrel", "slot order decides: Underbarrel(2) beats Magazine(5), Barrel(2.5) beats Muzzle(3)")
end)

test("rules: no conflicts declared -> identical to the old whitelist sanitize", function()
	local system = newSystem()
	local clean = system:SanitizeLoadout({ Optics = "RedDot", Muzzle = "Comp", Stock = "X", Bogus = "Y" }, newTool())
	eq(keys(clean), "Muzzle,Optics,Stock", "unknown slot removed, unknown names kept (Equip rejects later)")
end)

test("rules: capacity from tool attribute, kept in slot order", function()
	local system = newSystem()
	local tool = newTool()
	tool:SetAttribute("MaxAttachments", 2)
	eq(system:GetCapacity(tool), 2)
	local clean = system:SanitizeLoadout({ Magazine = "Extended", Optics = "RedDot", Muzzle = "Comp" }, tool)
	eq(keys(clean), "Muzzle,Optics", "Magazine (order 5) dropped")
end)

test("rules: global capacity option, attribute overrides it", function()
	local system = newSystem({ rules = { maxAttachments = 1, capacityAttribute = "MaxAttachments" } })
	eq(system:GetCapacity(newTool()), 1)
	local tool = newTool()
	tool:SetAttribute("MaxAttachments", 3)
	eq(system:GetCapacity(tool), 3)
	eq(system:GetCapacity(nil), 1)
end)

test("rules: CheckSelection displaces conflicts (both declaration directions)", function()
	local system = newSystem()
	local tool = newTool()
	local result = system:CheckSelection(tool, { Underbarrel = "VGrip", Optics = "RedDot" }, "Magazine", "Drum")
	eq(result.ok, true)
	eq(table.concat(result.displaced, ","), "Underbarrel", "VGrip declares Magazine/Drum")
	result = system:CheckSelection(tool, { Barrel = "Long" }, "Muzzle", "Suppressor")
	eq(table.concat(result.displaced, ","), "Barrel", "Suppressor declares the Barrel slot")
	result = system:CheckSelection(tool, { Underbarrel = "VGrip" }, "Magazine", "Extended")
	eq(#result.displaced, 0, "only the Drum conflicts")
end)

test("rules: CheckSelection capacity (replacement in the same slot is free)", function()
	local system = newSystem()
	local tool = newTool()
	tool:SetAttribute("MaxAttachments", 1)
	local result = system:CheckSelection(tool, { Optics = "RedDot" }, "Muzzle", "Comp")
	eq(result.ok, false, "second attachment refused")
	result = system:CheckSelection(tool, { Optics = "RedDot" }, "Optics", "Scope")
	eq(result.ok, true, "swap within slot allowed")
	result = system:CheckSelection(tool, { Optics = "RedDot" }, "Bogus", "X")
	eq(result.ok, false, "unknown slot refused")
end)

-- ─── package: content listing & CanEquip ────────────────────────────────────

test("ListContent: sorted names with a config module", function()
	local system = newSystem()
	eq(table.concat(system:ListContent("Magazine"), ","), "Drum,Extended")
	eq(#system:ListContent("Stock"), 0, "slot without content")
end)

test("CanEquip agrees with Equip for every slot/option", function()
	local system = newSystem()
	for _, withMounts in ipairs({ false, true }) do
		for _, def in ipairs(system:GetSlots()) do
			for _, name in ipairs(system:ListContent(def.name)) do
				local tool = newTool()
				local gun = newGun(withMounts)
				local can, reason = system:CanEquip(gun, tool, def.name, name)
				local did, equipReason = system:Equip(gun, tool, def.name, name)
				eq(can, did, def.name .. "/" .. name .. " (mounts=" .. tostring(withMounts) .. ")")
				eq(reason, equipReason, "same reason for " .. def.name .. "/" .. name)
			end
		end
	end
end)

-- ─── package: multi-slot roles ──────────────────────────────────────────────

test("sights: single optic behaves exactly as before", function()
	local system = newSystem()
	local gun, tool = newGun(true), newTool()
	system:Equip(gun, tool, "Optics", "RedDot")
	eq(system:GetSightCount(gun), 2)
	eq(system:GetAimPart(gun, 1).CFrame.Y, 1)
	eq(system:GetAimPart(gun, 2).CFrame.Y, 2, "AimPart2")
	eq(system:GetAimPart(gun, 3).CFrame.Y, 1, "missing index falls back to AimPart")
end)

test("sights: dual optics chain primary then secondary", function()
	local system = newSystem()
	local gun, tool = newGun(true), newTool()
	system:Equip(gun, tool, "SecondaryOptic", "Canted")
	eq(system:GetSightCount(gun), 1, "secondary alone still aims")
	eq(system:GetAimPart(gun, 1).CFrame.X, 5)
	system:Equip(gun, tool, "Optics", "RedDot")
	eq(system:GetSightCount(gun), 3)
	eq(system:GetAimPart(gun, 1).CFrame.Y, 1, "primary AimPart")
	eq(system:GetAimPart(gun, 2).CFrame.Y, 2, "primary AimPart2")
	eq(system:GetAimPart(gun, 3).CFrame.X, 5, "secondary AimPart")
	eq(system:GetAimPart(gun, 4).CFrame.Y, 1, "out of range -> first sight")
end)

test("muzzle: stacked Barrel + Muzzle, original restored only when both are gone", function()
	local system = newSystem()
	local gun, tool = newGun(true), newTool()
	local original = gun.Grip.Barrel
	system:Equip(gun, tool, "Barrel", "Long")
	system:Equip(gun, tool, "Muzzle", "Comp")
	eq(under(system:GetActiveMuzzle(gun), "Comp_Equipped"), true, "highest-order muzzle wins")
	eq(original.Transparency, 1, "original hidden")
	system:Unequip(gun, "Muzzle")
	eq(under(system:GetActiveMuzzle(gun), "Long_Equipped"), true, "falls back to barrel")
	eq(original.Transparency, 1, "still hidden while Barrel is mounted")
	eq(gun:GetAttribute("ActiveCustomMuzzle"), "Long")
	system:Unequip(gun, "Barrel")
	eq(original.Transparency, 0, "restored")
	eq(gun:GetAttribute("ActiveCustomMuzzle"), nil)
	-- Fallback is the original contract: <Root>.Muzzle as a direct child (here the gun's
	-- muzzle sits deeper, so no attachment muzzle and no fallback remain).
	local active = system:GetActiveMuzzle(gun)
	eq(active == nil or not under(active, "Long_Equipped") and not under(active, "Comp_Equipped"), true, "no attachment muzzle left")
end)

test("magazine slot: generic mount + stats in slot order", function()
	local system = newSystem()
	local gun, tool = newGun(true), newTool()
	system:SetBaseStats(tool, { mag = 30 })
	local applied = system:ApplyLoadout(gun, tool, nil, { Magazine = "Drum", Optics = "RedDot" })
	eq(applied.Magazine, true)
	eq(system:ComputeStats(tool, gun).mag, 50)
end)

-- ─── Customize/Selection ────────────────────────────────────────────────────

test("Selection: legacy toggle semantics + dirty + revert", function()
	local sel = Selection.new()
	local events = {}
	sel.Changed:Connect(function(change) table.insert(events, change.kind) end)
	sel:Load({ Optics = "RedDot", Bad = "" })
	eq(keys(sel:GetAll()), "Optics", "empty names dropped")
	eq(sel:IsDirty(), false)
	sel:Toggle("Optics", "RedDot")
	eq(sel:Get("Optics"), nil, "clicking the selected item clears")
	eq(sel:IsDirty(), true)
	sel:Toggle("Optics", "Scope")
	eq(sel:Get("Optics"), "Scope")
	sel:Revert()
	eq(sel:Get("Optics"), "RedDot")
	eq(sel:IsDirty(), false)
	eq(table.concat(events, ","), "load,clear,select,revert")
end)

test("Selection: rules via check (displace + refuse) and allowEmpty", function()
	local system = newSystem()
	local tool = newTool()
	tool:SetAttribute("MaxAttachments", 2)
	local sel = Selection.new({
		check = function(loadout, slot, name) return system:CheckSelection(tool, loadout, slot, name) end,
		allowEmpty = function(slot) return slot ~= "Magazine" end,
	})
	sel:Load({ Underbarrel = "VGrip" })
	local ok, _, displaced = sel:Select("Magazine", "Drum")
	eq(ok, true)
	eq(table.concat(displaced, ","), "Underbarrel")
	eq(keys(sel:GetAll()), "Magazine")
	sel:Select("Optics", "RedDot")
	local refused, reason = sel:Select("Muzzle", "Comp")
	eq(refused, false, "capacity 2 reached")
	eq(type(reason), "string")
	local cleared, why = sel:Clear("Magazine")
	eq(cleared, false, "Magazine cannot be empty")
	eq(type(why), "string")
	eq(sel:Count(), 2)
end)

test("Selection: MarkSaved resets dirty", function()
	local sel = Selection.new()
	sel:Load({})
	sel:Select("Stock", "Tac")
	sel:MarkSaved()
	eq(sel:IsDirty(), false)
	eq(sel:GetSaved().Stock, "Tac")
end)

-- ─── Customize/Catalog ──────────────────────────────────────────────────────

local function slotNames(catalog)
	local names = {}
	for _, slot in ipairs(catalog.slots) do
		table.insert(names, slot.name)
	end
	return table.concat(names, ",")
end

test("Catalog: legacy gun shows only the slots it can mount", function()
	local system = newSystem()
	local catalog = Catalog.build({ attachments = system, tool = newTool(), model = newGun(false) })
	eq(slotNames(catalog), "Optics,Underbarrel,Muzzle", "no Stock content; new slots have no mount parts")
	local optics = Catalog.find(catalog, "Optics")
	eq(#optics.options, 1, "Scope is incompatible with M4 and hidden")
	eq(optics.options[1].label, "Red Dot", "DisplayName from config")
end)

test("Catalog: new slots appear automatically when the gun has the mounts", function()
	local system = newSystem()
	local catalog = Catalog.build({ attachments = system, tool = newTool(), model = newGun(true) })
	eq(slotNames(catalog), "Optics,Underbarrel,Barrel,Muzzle,Magazine,SecondaryOptic", "slot order (Barrel 2.5)")
	local secondary = Catalog.find(catalog, "SecondaryOptic")
	eq(secondary.label, "Secondary Optic", "humanized")
	eq(secondary.options[1].label, "Canted Dot", "DisplayName attribute")
	eq(secondary.options[1].icon, "rbxassetid://1", "Icon attribute")
end)

test("Catalog: showUnavailable, slot meta, filters, missing model", function()
	local system = newSystem()
	local catalog = Catalog.build({
		attachments = system,
		tool = newTool(),
		model = newGun(false),
		showUnavailable = true,
		slotMeta = { Magazine = { label = "Mags", order = 0 }, Muzzle = { hidden = true }, Optics = { allowEmpty = false } },
	})
	eq(slotNames(catalog), "Magazine,Optics,Underbarrel,Barrel,SecondaryOptic")
	local mags = Catalog.find(catalog, "Magazine")
	eq(mags.label, "Mags")
	eq(mags.options[1].available, false)
	eq(type(mags.options[1].reason), "string")
	eq(Catalog.find(catalog, "Optics").allowEmpty, false)
	local scope = Catalog.find(catalog, "Optics").options[2]
	eq(scope.name, "Scope")
	eq(scope.available, false, "incompatible shown greyed")

	local filtered = Catalog.build({
		attachments = system, tool = newTool(), model = newGun(true),
		slotFilter = function(_, def) return def.name ~= "Magazine" end,
	})
	eq(Catalog.find(filtered, "Magazine"), nil, "slotFilter")

	local noModel = Catalog.build({ attachments = system, tool = newTool(), model = nil })
	eq(#noModel.slots, 0, "nothing available without a model")
end)

test("Catalog.humanize", function()
	eq(Catalog.humanize("SecondaryOptic"), "Secondary Optic")
	eq(Catalog.humanize("Under_barrel"), "Under barrel")
	eq(Catalog.humanize("Muzzle"), "Muzzle")
end)

-- ─── Customize/Config ───────────────────────────────────────────────────────

test("Config.resolve: deep merge, arrays replaced, defaults untouched", function()
	local config = Config.resolve({
		theme = { accent = { 1, 2, 3 } },
		slots = { Magazine = { order = 0 } },
		environment = { blockedKeys = { "W" } },
	})
	eq(config.theme.accent[1], 1)
	eq(config.theme.corner, Config.defaults.theme.corner, "untouched key kept")
	eq(config.slots.Magazine.order, 0)
	eq(config.slots.Magazine.label, "Magazine", "nested merge keeps label")
	eq(#config.environment.blockedKeys, 1, "array replaced")
	eq(#Config.defaults.environment.blockedKeys > 1, true, "defaults not mutated")
	config.theme.accent[1] = 99
	eq(Config.defaults.theme.accent[1], 92, "resolved tables are copies")
end)

print(("\nextended: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("extended tests failed")
end
