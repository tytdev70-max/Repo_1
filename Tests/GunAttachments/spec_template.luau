-- Customize/View/Template: drives the CustomizeGunGUI designed in Studio.
-- Run via Tests/GunAttachments/run.py (GUI globals come from gui_globals.luau).
local Mocks = require("./mocks")
local G = require("./gui_globals")
local Config = require("./Customize/Config")
local TemplateView = require("./Customize/View/Template")

local make = Mocks.make
local UDim2, Vector2, Color3 = G.UDim2, G.Vector2, G.Color3

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

local GREY = Color3.fromRGB(50, 50, 50)
local function item(name, extra)
	local props = {
		Name = "item",
		Size = UDim2.new(1, 0, 0, 40),
		Position = UDim2.new(0, 0, 0, 0),
		AnchorPoint = Vector2.new(0, 0),
		BackgroundColor3 = GREY,
		BackgroundTransparency = 0.3,
	}
	for key, value in pairs(extra or {}) do
		props[key] = value
	end
	return make("Frame", props, {
		make("Frame", { Name = "padding" }, { make("TextLabel", { Name = "itemname", Text = name }) }),
	})
end
local function column(order, items, props)
	local p = { Name = "column", LayoutOrder = order }
	for key, value in pairs(props or {}) do
		p[key] = value
	end
	return make("Frame", p, {
		make("Frame", { Name = "columnheading" }, { make("TextLabel", { Name = "title", Text = "?" }) }),
		make("Frame", { Name = "display" }, { make("ScrollingFrame", { Name = "items" }, items) }),
	})
end

-- The original SPH template. Columns are created out of order on purpose: LayoutOrder decides.
local function template()
	local columns = make("Frame", { Name = "AttachmentsColumn" }, {
		column(3, { item("Suppressor"), item("Compensator") }), -- Muzzle
		column(1, { item("RedDot"), item("ACOG") }), -- Optics
		column(4, { item("Fixed") }), -- Stock
		column(2, { item("VerticalGrip") }), -- Underbarrel
	})
	return make("ScreenGui", { Name = "CustomizeGunGUI" }, {
		make("Frame", { Name = "AttachmentsFrame" }, { make("Frame", { Name = "Padding" }, { columns }) }),
		make("Frame", { Name = "MainDisplayFrame" }, {
			make("Frame", { Name = "content" }, {
				make("TextButton", { Name = "ConfirmButton" }),
				make("TextButton", { Name = "CloseButton" }),
				make("Frame", { Name = "BlankFrame" }, { make("TextLabel", { Name = "GunName", Text = "" }) }),
			}),
			make("Frame", { Name = "3DView" }, { make("ViewportFrame", { Name = "3DVPF" }) }),
		}),
	})
end

local function opt(name, available, reason)
	return { name = name, label = name .. "!", available = available ~= false, reason = reason }
end
local function slot(name, order, options)
	return { name = name, label = name:upper(), order = order, options = options }
end

local function newView(gui, overrides)
	local actions = {}
	local view = TemplateView.new({ gui = gui, config = Config.resolve(overrides or {}), sounds = {} })
	view:Bind({
		pick = function(s, n) table.insert(actions, { "pick", s, n }) end,
		clear = function(s) table.insert(actions, { "clear", s }) end,
		confirm = function() table.insert(actions, { "confirm" }) end,
		close = function() table.insert(actions, { "close" }) end,
		revert = function() table.insert(actions, { "revert" }) end,
	})
	return view, actions
end

local function columnOf(gui, title)
	for _, c in ipairs(gui.AttachmentsFrame.Padding.AttachmentsColumn:GetChildren()) do
		if c.columnheading.title.Text == title then
			return c
		end
	end
	return nil
end
local function itemsOf(c)
	local map, list = {}, {}
	for _, child in ipairs(c.display.items:GetChildren()) do
		if child:FindFirstChild("padding") then
			map[child:GetAttribute("Attachment") or child.padding.itemname.Text] = child
			table.insert(list, child)
		end
	end
	return map, list
end
local function click(frame, button)
	frame.ClickButton[button or "MouseButton1Click"]:Fire()
end

local CATALOG = {
	slots = {
		slot("Optics", 1, { opt("RedDot"), opt("Holo") }), -- Holo is not designed -> auto item
		slot("Underbarrel", 2, { opt("VerticalGrip") }),
		slot("Muzzle", 3, { opt("Suppressor"), opt("Compensator", false, "Needs a threaded barrel") }),
		slot("Magazine", 5, { opt("Drum") }), -- no column -> auto column
	},
}

test("isTemplate recognises the SPH layout only", function()
	eq(TemplateView.isTemplate(template()), true)
	eq(TemplateView.isTemplate(make("ScreenGui", { Name = "CustomizeGunGUI" })), false)
end)

test("legacy columns map by LayoutOrder; titles set; unoffered items hidden", function()
	local gui = template()
	local view = newView(gui, { behaviour = { showUnavailable = true } })
	view:SetWeapon("M4")
	view:SetCatalog(CATALOG)
	eq(gui.MainDisplayFrame.content.BlankFrame.GunName.Text, "M4")
	local optics = columnOf(gui, "OPTICS")
	assert(optics, "optics column titled")
	eq(optics.LayoutOrder, 1, "first by LayoutOrder is Optics")
	local muzzle = columnOf(gui, "MUZZLE")
	eq(muzzle.LayoutOrder, 3)
	local items = itemsOf(optics)
	eq(items.RedDot.Visible, true)
	eq(items.ACOG.Visible, false, "ACOG not offered for this gun")
	assert(items.RedDot:FindFirstChild("ClickButton"), "designed item wired")
	-- Stock has no slot in the catalog: column stays (hideEmptyColumns=false), items hidden
	local stockColumn = columnOf(gui, "?")
	assert(stockColumn, "stock column untouched")
	eq(stockColumn.Visible, true)
	eq(itemsOf(stockColumn).Fixed.Visible, false)
end)

test("auto item for an undesigned attachment, auto column for a new slot", function()
	local gui = template()
	local view = newView(gui)
	view:SetCatalog(CATALOG)
	local holo = itemsOf(columnOf(gui, "OPTICS")).Holo
	assert(holo, "Holo cloned from the first item")
	eq(holo:GetAttribute("Attachment"), "Holo")
	eq(holo.padding.itemname.Text, "Holo!", "auto item label = option label (DisplayName)")
	eq(itemsOf(columnOf(gui, "OPTICS")).RedDot.padding.itemname.Text, "RedDot", "designed label untouched")
	eq(holo.LayoutOrder > 1000, true, "after designed items")

	local magazine = columnOf(gui, "MAGAZINE")
	assert(magazine, "Magazine column created")
	eq(magazine:GetAttribute("Slot"), "Magazine")
	local map, list = itemsOf(magazine)
	eq(#list, 1, "only catalog items in the copy")
	assert(map.Drum, "Drum item")
end)

test("clicks: pick, unavailable flashes, right-click clears, buttons", function()
	local gui = template()
	local view, actions = newView(gui, { behaviour = { showUnavailable = true } })
	view:SetCatalog(CATALOG)
	local muzzle = itemsOf(columnOf(gui, "MUZZLE"))
	click(muzzle.Suppressor)
	eq(actions[1][1], "pick"); eq(actions[1][2], "Muzzle"); eq(actions[1][3], "Suppressor")
	click(muzzle.Compensator)
	eq(#actions, 1, "unavailable item does not pick")
	eq(gui.Status.Text, "Needs a threaded barrel", "reason shown in auto Status label")
	eq(muzzle.Compensator.BackgroundTransparency, 0.6, "unavailable dimmed")
	click(muzzle.Suppressor, "MouseButton2Click")
	eq(actions[2][1], "clear"); eq(actions[2][2], "Muzzle")
	gui.MainDisplayFrame.content.ConfirmButton.MouseButton1Click:Fire()
	gui.MainDisplayFrame.content.CloseButton.MouseButton1Click:Fire()
	eq(actions[3][1], "confirm"); eq(actions[4][1], "close")
end)

test("selection look: selected grows + colour, deselect restores original", function()
	local gui = template()
	local view = newView(gui)
	view:SetCatalog(CATALOG)
	local optics = itemsOf(columnOf(gui, "OPTICS"))
	view:SetSelection({ Optics = "RedDot" })
	eq(optics.RedDot.BackgroundColor3, Color3.fromRGB(100, 200, 100))
	eq(optics.RedDot.BackgroundTransparency, 0)
	eq(optics.RedDot.Size, UDim2.new(1.03, 0, 0, 41.2))
	eq(optics.RedDot.AnchorPoint, Vector2.new(0.5, 0.5))
	eq(optics.RedDot.Position, UDim2.new(0.5, 0, 0, 20), "kept centred")
	view:SetSelection({ Optics = "Holo" })
	eq(optics.RedDot.BackgroundColor3, GREY, "original colour back")
	eq(optics.RedDot.BackgroundTransparency, 0.3)
	eq(optics.RedDot.Size, UDim2.new(1, 0, 0, 40))
	eq(optics.RedDot.Position, UDim2.new(0, 0, 0, 0))
	-- hover on the selected item doesn't shrink it
	optics.Holo.ClickButton.MouseEnter:Fire()
	G.flushTweens()
	eq(optics.Holo.Size, UDim2.new(1.03, 0, 0, 41.2))
end)

test("rebuild for another weapon: no leftovers or duplicate buttons", function()
	local gui = template()
	local view = newView(gui)
	view:SetCatalog(CATALOG)
	view:SetSelection({ Optics = "RedDot" })
	view:SetCatalog({ slots = { slot("Optics", 1, { opt("ACOG"), opt("RedDot") }) } })
	eq(columnOf(gui, "MAGAZINE"), nil, "auto column removed")
	local map, list = itemsOf(columnOf(gui, "OPTICS"))
	eq(map.Holo, nil, "auto item removed")
	eq(#list, 2)
	eq(map.ACOG.Visible, true)
	eq(map.RedDot.BackgroundColor3, GREY, "look reset between weapons")
	local buttons = 0
	for _, child in ipairs(map.RedDot:GetChildren()) do
		if child.Name == "ClickButton" then
			buttons += 1
		end
	end
	eq(buttons, 1, "one click button")
end)

test("Slot attribute / column name override the legacy order", function()
	local gui = template()
	local container = gui.AttachmentsFrame.Padding.AttachmentsColumn
	column(9, { item("Drum") }, { Name = "Mags", Parent = container }):SetAttribute("Slot", "Magazine")
	column(0, { item("Long") }, { Name = "Barrel", Parent = container })
	local view = newView(gui)
	view:SetCatalog({ slots = { slot("Magazine", 5, { opt("Drum") }), slot("Barrel", 6, { opt("Long") }), slot("Optics", 1, { opt("RedDot") }) } })
	eq(columnOf(gui, "MAGAZINE").Name, "Mags", "designed Magazine column used, no copy")
	eq(columnOf(gui, "BARREL").Name, "Barrel")
	eq(columnOf(gui, "OPTICS").LayoutOrder, 1, "named columns don't shift the legacy order")
end)

test("hideEmptyColumns, autoColumns=false warns", function()
	local gui = template()
	local view = newView(gui, { template = { hideEmptyColumns = true, autoColumns = false } })
	table.clear(G.warnings)
	view:SetCatalog(CATALOG)
	eq(columnOf(gui, "?").Visible, false, "Stock column hidden")
	eq(columnOf(gui, "MAGAZINE"), nil)
	eq(#G.warnings, 1, "one warning for the slot without a column")
end)

test("Destroy restores the designed GUI", function()
	local gui = template()
	local view, actions = newView(gui)
	view:SetCatalog(CATALOG)
	view:SetSelection({ Optics = "RedDot" })
	view:Destroy()
	local optics = itemsOf(columnOf(gui, "OPTICS"))
	eq(optics.Holo, nil, "auto item gone")
	eq(optics.RedDot:FindFirstChild("ClickButton"), nil)
	eq(optics.RedDot.BackgroundColor3, GREY)
	eq(gui:FindFirstChild("Status"), nil, "auto Status removed")
	eq(columnOf(gui, "MAGAZINE"), nil)
	gui.MainDisplayFrame.content.ConfirmButton.MouseButton1Click:Fire()
	eq(#actions, 0, "buttons disconnected")
	-- a new view on the same GUI works (restart / respawn)
	local again = newView(gui)
	again:SetCatalog(CATALOG)
	assert(itemsOf(columnOf(gui, "OPTICS")).Holo, "rebuilt")
end)

print(("\ntemplate: %d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("template tests failed")
end
