-- Weapons/Presets/PresetBook: the preset rules (pure). Run via run.py.
local PresetBook = require("./Presets/PresetBook")

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

local CQB = { Optics = "RedDot", Muzzle = "Compensator" }
local LONG = { Optics = "ACOG", Muzzle = "Suppressor", Underbarrel = "Bipod" }

test("cleanName trims, collapses, strips control chars, limits length", function()
	eq(PresetBook.cleanName("  CQB   setup \n", 24), "CQB setup")
	eq(PresetBook.cleanName("\t\n  ", 24), nil, "blank")
	eq(PresetBook.cleanName(42, 24), nil, "not a string")
	eq(PresetBook.cleanName("abcdefghij", 4), "abcd")
	eq(PresetBook.cleanName("ab  cd", 3), "ab", "no trailing space after cut")
	eq(PresetBook.cleanName("Ünïcødé ✓", 9), "Ünïcødé ✓", "UTF-8 counted by characters")
	eq(PresetBook.cleanName("Ünïcødé", 3), "Ünï")
	eq(PresetBook.cleanName("bad\255utf8", 24), nil, "invalid UTF-8 refused")
end)

test("save, list in order, overwrite keeps place, get returns copies", function()
	local book = PresetBook.new()
	assert(book:Save("M4", "CQB", CQB))
	assert(book:Save("M4", "Long", LONG))
	local ok, err, name = book:Save("M4", " CQB ", { Optics = "Holo" })
	eq(ok, true); eq(err, nil); eq(name, "CQB", "overwrite by cleaned name")
	local list = book:List("M4")
	eq(#list, 2); eq(list[1].name, "CQB", "overwrite keeps position"); eq(list[1].loadout.Optics, "Holo")
	list[1].loadout.Optics = "Hacked"
	eq(book:Get("M4", "CQB").Optics, "Holo", "List returns copies")
	local got = book:Get("M4", "Long"); got.Optics = "X"
	eq(book:Get("M4", "Long").Optics, "ACOG", "Get returns copies")
	eq(#book:List("AK47"), 0, "other guns separate")
	eq(book:Get("M4", "nope"), nil)
end)

test("limits and bad input", function()
	local book = PresetBook.new()
	assert(book:Save("M4", "A", CQB, { maxPresets = 2 }))
	assert(book:Save("M4", "B", CQB, { maxPresets = 2 }))
	local ok, err = book:Save("M4", "C", CQB, { maxPresets = 2 })
	eq(ok, false); eq(err, "limit")
	eq((book:Save("M4", "A", LONG, { maxPresets = 2 })), true, "overwriting is allowed at the limit")
	eq(select(2, book:Save("M4", "", CQB)), "name")
	eq(select(2, book:Save("", "X", CQB)), "gun")
	eq(select(2, book:Save(string.rep("g", 65), "X", CQB)), "gun")
	-- a refused first preset doesn't leave an empty gun entry
	book:Save("AK", "X", CQB, { maxPresets = 0 })
	eq(book:Serialize().guns.AK, nil)
	-- loadout structure is cleaned
	book:Save("M4", "Junk", { Optics = "RedDot", [5] = "x", Muzzle = 7, Stock = "", Grip = string.rep("y", 65) })
	local junk = book:Get("M4", "Junk")
	eq(junk.Optics, "RedDot"); eq(junk[5], nil); eq(junk.Muzzle, nil); eq(junk.Stock, nil); eq(junk.Grip, nil)
	local many = {}
	for i = 1, 40 do many["Slot" .. i] = "A" end
	book:Save("M4", "Many", many)
	local count = 0
	for _ in pairs(book:Get("M4", "Many")) do count += 1 end
	eq(count, PresetBook.MAX_SLOTS, "slot count capped")
end)

test("delete and rename keep order and the active mark", function()
	local book = PresetBook.new()
	book:Save("M4", "A", CQB); book:Save("M4", "B", LONG); book:Save("M4", "C", CQB)
	assert(book:SetActive("M4", "B"))
	local ok, err, name = book:Rename("M4", "B", "  Bravo ")
	eq(ok, true); eq(name, "Bravo")
	eq(book:List("M4")[2].name, "Bravo", "rename keeps position")
	eq((book:GetActive("M4")), "Bravo", "active follows rename")
	eq(select(2, book:Rename("M4", "A", "C")), "exists")
	eq(select(2, book:Rename("M4", "Zulu", "Y")), "missing")
	eq(select(2, book:Rename("M4", "A", "   ")), "name")
	eq((book:Rename("M4", "A", "A")), true, "same name is a no-op")
	eq(book:Delete("M4", "Bravo"), true)
	eq((book:GetActive("M4")), nil, "deleting the active preset clears it")
	eq(book:Delete("M4", "Bravo"), false)
	book:Delete("M4", "A"); book:Delete("M4", "C")
	eq(book:Serialize().guns.M4, nil, "empty gun entry removed")
end)

test("active preset per gun", function()
	local book = PresetBook.new()
	book:Save("M4", "CQB", CQB); book:Save("AK", "Long", LONG)
	eq(book:SetActive("M4", "Nope"), false, "unknown preset can't be active")
	assert(book:SetActive("M4", "CQB")); assert(book:SetActive("AK", "Long"))
	local name, loadout = book:GetActive("M4")
	eq(name, "CQB"); eq(loadout.Muzzle, "Compensator")
	loadout.Muzzle = "X"
	eq(select(2, book:GetActive("M4")).Muzzle, "Compensator", "copy")
	book:SetActive("M4", nil)
	eq((book:GetActive("M4")), nil); eq((book:GetActive("AK")), "Long", "other gun untouched")
	eq(book:SetActive("Ghost", nil), true, "clearing an unknown gun is harmless")
end)

test("serialize round-trip and untrusted stored data", function()
	local book = PresetBook.new()
	book:Save("M4", "CQB", CQB); book:Save("M4", "Long", LONG); book:SetActive("M4", "Long")
	local again = PresetBook.new(book:Serialize())
	local list, active = again:List("M4")
	eq(#list, 2); eq(list[1].name, "CQB"); eq(active, "Long")
	eq(PresetBook.sameLoadout(again:Get("M4", "Long"), LONG), true)

	local hostile = PresetBook.new({
		version = 1,
		guns = {
			M4 = { order = { "B", "B", 5, "Ghost" }, presets = { A = CQB, B = LONG, C = "nope", ["  pad"] = CQB }, active = "Ghost" },
			[7] = { presets = { X = CQB } },
			Empty = { presets = {} },
			Bad = "string",
		},
	})
	local hl, ha = hostile:List("M4")
	eq(#hl, 2, "only valid presets"); eq(hl[1].name, "B", "stored order first"); eq(hl[2].name, "A", "rest sorted")
	eq(ha, nil, "active pointing at a missing preset dropped")
	local guns = hostile:Serialize().guns
	eq(guns.Empty, nil); eq(guns.Bad, nil); eq(guns[7], nil)
	eq(#PresetBook.new(nil):List("M4"), 0); eq(#PresetBook.new("garbage"):List("M4"), 0)
end)

test("sameLoadout compares exact pairs", function()
	eq(PresetBook.sameLoadout(CQB, { Muzzle = "Compensator", Optics = "RedDot" }), true)
	eq(PresetBook.sameLoadout(CQB, { Optics = "RedDot" }), false)
	eq(PresetBook.sameLoadout({ Optics = "RedDot" }, CQB), false)
	eq(PresetBook.sameLoadout(nil, {}), true)
end)

print(("\npresets: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("preset tests failed")
end
