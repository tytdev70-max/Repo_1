--!nonstrict
-- Customize/View/Gunsmith
-- View for the Gunsmith ScreenGui (HUD.GunGUIs.Gunsmith). Pure presentation: it shows
-- what the controller gives it and reports clicks as actions. Nothing here talks to SPH.
--
-- Expected hierarchy (names as built in Studio):
--   Gunsmith (ScreenGui)
--     Container
--       WeaponViewport.Viewport            ViewportFrame - weapon preview
--       General
--         WeaponName                       TextLabel
--         WeaponType                       TextLabel     - Rifle, Pistol... (WepStats.WeaponType / Tool attribute)
--         Stats                            (not used yet)
--         ClearAllAtachments               button - empties every slot (Apply puts it on the gun)
--         CancelLoadout                    button - discard and close
--         ApplyLoadout                     button - apply to the gun and close
--         TestLoadout                      button - try the build in the test area
--         SaveLoadout                      button - save the build (random name for now)
--       Attachments
--         BackToCategoryAttachments        button - back from a list to the categories (shown in lists only)
--         Attachments
--           AttachmentCategory             list of categories (one per slot this gun can use)
--             AttachmentCategoryTemplate   copied per slot (the original stays hidden)
--               InvisibleButton            click = open the slot's list
--               AttachmentName             TextLabel - picked attachment or "None"
--               AttachmentType             TextLabel - "OPTICS", "MUZZLE"...
--           Attachments                    list of the open slot's attachments
--             AttachmentTemplate           copied per attachment (the original stays hidden)
--               InvisibleButton            click = pick
--               AttachmentName             TextLabel
--
-- Optional: a "Selected" child in AttachmentTemplate (shown on the picked entry; without
-- it the name is tinted), a "Status" TextLabel anywhere for messages, sounds named
-- Hover/Select/Deselect in the ScreenGui. Buttons may be GuiButtons or contain one.
-- Copies carry the attribute CustomizeAuto and are removed on rebuild/Destroy.

local GunsmithView = {}
GunsmithView.__index = GunsmithView

local AUTO_ATTRIBUTE = "CustomizeAuto"

local function find(root: Instance?, path: { string }): Instance?
	local node = root
	for _, name in ipairs(path) do
		if not node then
			return nil
		end
		node = node:FindFirstChild(name)
	end
	return node
end

-- The clickable part of a button-like element: itself, or a GuiButton inside it.
local function clickable(element: Instance?): GuiButton?
	if not element then
		return nil
	end
	if element:IsA("GuiButton") then
		return element
	end
	return element:FindFirstChildWhichIsA("GuiButton", true)
end

local function rgb(value: any, fallback: Color3): Color3
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "table" and #value == 3 then
		return Color3.fromRGB(value[1], value[2], value[3])
	end
	return fallback
end

local function setText(label: Instance?, text: string)
	if label and (label:IsA("TextLabel") or label:IsA("TextButton") or label:IsA("TextBox")) then
		label.Text = text
	end
end

local PATHS = {
	viewport = { "Container", "WeaponViewport", "Viewport" },
	general = { "Container", "General" },
	back = { "Container", "Attachments", "BackToCategoryAttachments" },
	categories = { "Container", "Attachments", "Attachments", "AttachmentCategory" },
	items = { "Container", "Attachments", "Attachments", "Attachments" },
}

local REQUIRED = {
	{ "Container", "Attachments", "Attachments", "AttachmentCategory", "AttachmentCategoryTemplate" },
	{ "Container", "Attachments", "Attachments", "Attachments", "AttachmentTemplate" },
}

-- Path of the first required element that is missing (nil = all there), e.g.
-- "Gunsmith.Container.Attachments.Attachments.Attachments (missing: AttachmentTemplate)".
function GunsmithView.missing(gui: Instance): string?
	for _, path in ipairs(REQUIRED) do
		local node = gui
		local walked = { gui.Name }
		for _, name in ipairs(path) do
			local nextNode = node:FindFirstChild(name)
			if not nextNode then
				return table.concat(walked, ".") .. " (missing: " .. name .. ")"
			end
			node = nextNode
			table.insert(walked, name)
		end
	end
	return nil
end

-- Waits (up to `timeout` seconds in total) for the required frames: right after the
-- ScreenGui is copied into PlayerGui, its descendants may still be loading.
function GunsmithView.waitUntilReady(gui: Instance, timeout: number?): boolean
	local deadline = os.clock() + (timeout or 10)
	for _, path in ipairs(REQUIRED) do
		local node = gui
		for _, name in ipairs(path) do
			local nextNode = node:FindFirstChild(name)
			if not nextNode and node.WaitForChild then
				local remaining = deadline - os.clock()
				if remaining > 0 then
					nextNode = node:WaitForChild(name, remaining)
				end
			end
			if not nextNode then
				return false
			end
			node = nextNode
		end
	end
	return true
end

function GunsmithView.isGunsmith(gui: Instance): boolean
	local categories = find(gui, PATHS.categories)
	local items = find(gui, PATHS.items)
	return categories ~= nil and categories:FindFirstChild("AttachmentCategoryTemplate") ~= nil
		and items ~= nil and items:FindFirstChild("AttachmentTemplate") ~= nil
end

function GunsmithView.new(context: { [string]: any })
	local gui = context.gui
	local self = setmetatable({}, GunsmithView)
	self._gui = gui
	self._config = context.config
	self._options = context.config.gunsmith or {}
	self._text = context.config.text
	self._sounds = context.sounds or {}
	self._actions = {}
	self._connections = {}
	self._catalog = { slots = {} }
	self._selection = {}
	self._activeSlot = nil
	self._screen = "categories" -- | "attachments"
	self._presetNames = {}
	self._flashToken = 0
	self._original = {} -- element -> { Visible } restored on Destroy

	local general = find(gui, PATHS.general)
	self._viewport = find(gui, PATHS.viewport)
	self._weaponName = general and general:FindFirstChild("WeaponName")
	self._weaponType = general and general:FindFirstChild("WeaponType")
	self._clearAll = clickable(general and (general:FindFirstChild("ClearAllAtachments") or general:FindFirstChild("ClearAllAttachments")))
	self._cancel = clickable(general and general:FindFirstChild("CancelLoadout"))
	self._apply = clickable(general and general:FindFirstChild("ApplyLoadout"))
	self._test = clickable(general and general:FindFirstChild("TestLoadout"))
	self._save = clickable(general and general:FindFirstChild("SaveLoadout"))
	self._backElement = find(gui, PATHS.back)
	self._back = clickable(self._backElement)
	self._categoryList = find(gui, PATHS.categories)
	self._itemList = find(gui, PATHS.items)
	self._categoryTemplate = self._categoryList and self._categoryList:FindFirstChild("AttachmentCategoryTemplate")
	self._itemTemplate = self._itemList and self._itemList:FindFirstChild("AttachmentTemplate")
	local status = gui:FindFirstChild("Status", true)
	self._status = if status and status:IsA("TextLabel") then status else nil

	for _, element in ipairs({ self._categoryTemplate, self._itemTemplate, self._backElement, self._categoryList, self._itemList }) do
		if element and element:IsA("GuiObject") then
			self._original[element] = element.Visible
		end
	end
	if self._categoryTemplate then
		self._categoryTemplate.Visible = false
	end
	if self._itemTemplate then
		self._itemTemplate.Visible = false
	end

	self:_connectButtons()
	self:_showScreen("categories")
	return self
end

function GunsmithView:_connect(signal, fn)
	table.insert(self._connections, signal:Connect(fn))
end

function GunsmithView:_act(name: string, ...: any)
	local action = self._actions[name]
	if action then
		action(...)
	end
end

function GunsmithView:_connectButtons()
	local function onClick(button: GuiButton?, fn: () -> ())
		if button then
			self:_connect(button.MouseButton1Click, fn)
		end
	end
	onClick(self._apply, function()
		self:_act("confirm")
	end)
	onClick(self._cancel, function()
		self:_act("close")
	end)
	onClick(self._test, function()
		self:_act("testLoadout")
	end)
	onClick(self._save, function()
		self:_act("savePreset", self:_randomName())
	end)
	onClick(self._clearAll, function()
		for slot in pairs(table.clone(self._selection)) do
			self:_act("clear", slot)
		end
	end)
	onClick(self._back, function()
		self:_showScreen("categories")
	end)
end

-- "<word> <number>" that no saved preset of this gun uses yet.
function GunsmithView:_randomName(): string
	local words = self._options.randomNameWords
	if type(words) ~= "table" or #words == 0 then
		words = { "Loadout" }
	end
	local name = ""
	for _ = 1, 20 do
		name = ("%s %d"):format(words[math.random(1, #words)], math.random(1, 99))
		if not self._presetNames[name] then
			break
		end
	end
	return name
end

function GunsmithView:_showScreen(screen: string)
	self._screen = screen
	local inList = screen == "attachments"
	if self._categoryList and self._categoryList:IsA("GuiObject") then
		self._categoryList.Visible = not inList
	end
	if self._itemList and self._itemList:IsA("GuiObject") then
		self._itemList.Visible = inList
	end
	if self._backElement and self._backElement:IsA("GuiObject") then
		self._backElement.Visible = inList
	end
	if inList then
		self:_renderItems()
	end
end

local function clearCopies(container: Instance?)
	if not container then
		return
	end
	for _, child in ipairs(container:GetChildren()) do
		if child:GetAttribute(AUTO_ATTRIBUTE) then
			child:Destroy()
		end
	end
end

function GunsmithView:_slot(name: string?): any
	for _, slot in ipairs(self._catalog.slots) do
		if slot.name == name then
			return slot
		end
	end
	return nil
end

function GunsmithView:_label(slot: any, name: string?): string
	if not name then
		return self._text.none
	end
	for _, option in ipairs(slot and slot.options or {}) do
		if option.name == name then
			return option.label or name
		end
	end
	return name
end

-- ─── categories ───────────────────────────────────────────────────────────────

function GunsmithView:_renderCategories()
	clearCopies(self._categoryList)
	self._categoryRows = {}
	local template = self._categoryTemplate
	if not template then
		return
	end
	for index, slot in ipairs(self._catalog.slots) do
		local row = template:Clone()
		row.Name = "Category_" .. slot.name
		row.Visible = true
		row.LayoutOrder = index
		row:SetAttribute(AUTO_ATTRIBUTE, true)
		row:SetAttribute("Slot", slot.name)
		local label = slot.label or slot.name
		setText(row:FindFirstChild("AttachmentType"), if self._options.uppercaseCategories then string.upper(label) else label)
		local button = clickable(row:FindFirstChild("InvisibleButton")) or clickable(row)
		if button then
			button.MouseButton1Click:Connect(function()
				self:PlaySound("select")
				self._activeSlot = slot.name
				self:_act("selectSlot", slot.name)
				self:_showScreen("attachments")
			end)
			button.MouseEnter:Connect(function()
				self:PlaySound("hover")
			end)
		end
		row.Parent = self._categoryList
		self._categoryRows[slot.name] = row
	end
	self:_refreshCategoryNames()
end

function GunsmithView:_refreshCategoryNames()
	for slotName, row in pairs(self._categoryRows or {}) do
		setText(row:FindFirstChild("AttachmentName"), self:_label(self:_slot(slotName), self._selection[slotName]))
	end
end

-- ─── attachment list ──────────────────────────────────────────────────────────

function GunsmithView:_renderItems()
	clearCopies(self._itemList)
	self._itemRows = {}
	local template = self._itemTemplate
	local slot = self:_slot(self._activeSlot)
	if not template or not slot then
		return
	end
	local entries = {}
	if self._options.noneItem ~= false and slot.allowEmpty ~= false then
		table.insert(entries, { none = true, label = self._text.none, available = true })
	end
	for _, option in ipairs(slot.options) do
		table.insert(entries, { name = option.name, label = option.label or option.name, available = option.available ~= false, reason = option.reason })
	end
	for index, entry in ipairs(entries) do
		local row = template:Clone()
		row.Name = if entry.none then "Attachment_None" else "Attachment_" .. entry.name
		row.Visible = true
		row.LayoutOrder = index
		row:SetAttribute(AUTO_ATTRIBUTE, true)
		row:SetAttribute("Attachment", entry.name)
		row:SetAttribute("Available", entry.available)
		local nameLabel = row:FindFirstChild("AttachmentName")
		setText(nameLabel, entry.label)
		if nameLabel and nameLabel:IsA("TextLabel") then
			row:SetAttribute("OriginalColor", nameLabel.TextColor3)
			if not entry.available then
				nameLabel.TextTransparency = self._options.unavailableTransparency or 0.6
			end
		end
		local button = clickable(row:FindFirstChild("InvisibleButton")) or clickable(row)
		if button then
			button.MouseButton1Click:Connect(function()
				if entry.none then
					self:PlaySound("deselect")
					self:_act("clear", slot.name)
				elseif entry.available then
					self:PlaySound("select")
					self:_act("pick", slot.name, entry.name)
				else
					self:Flash(entry.reason or "Not available for this weapon", "warning")
				end
			end)
			button.MouseEnter:Connect(function()
				self:PlaySound("hover")
			end)
		end
		row.Parent = self._itemList
		table.insert(self._itemRows, { row = row, entry = entry })
	end
	self:_refreshItemMarks()
end

function GunsmithView:_refreshItemMarks()
	local picked = self._selection[self._activeSlot or ""]
	local tint = rgb(self._options.selectedColor, Color3.fromRGB(100, 200, 100))
	for _, item in ipairs(self._itemRows or {}) do
		local selected = if item.entry.none then picked == nil else picked == item.entry.name
		item.row:SetAttribute("Selected", selected)
		local marker = item.row:FindFirstChild("Selected")
		if marker and marker:IsA("GuiObject") then
			marker.Visible = selected
		else
			local nameLabel = item.row:FindFirstChild("AttachmentName")
			local original = item.row:GetAttribute("OriginalColor")
			if nameLabel and nameLabel:IsA("TextLabel") and typeof(original) == "Color3" then
				nameLabel.TextColor3 = if selected then tint else original
			end
		end
	end
end

-- ─── view interface ───────────────────────────────────────────────────────────

function GunsmithView:Bind(actions: { [string]: any })
	self._actions = actions
end

function GunsmithView:PlaySound(kind: string)
	local sound = self._sounds[kind]
	if sound then
		pcall(function()
			sound:Play()
		end)
	end
end

-- info: { tool, weaponType } (second argument, added for this view)
function GunsmithView:SetWeapon(name: string, info: { [string]: any }?)
	setText(self._weaponName, name)
	setText(self._weaponType, info and info.weaponType or "")
end

function GunsmithView:GetViewport(): ViewportFrame?
	local viewport = self._viewport
	return if viewport and viewport:IsA("ViewportFrame") then viewport else nil
end

function GunsmithView:SetCatalog(catalog: { slots: { any } })
	self._catalog = catalog or { slots = {} }
	self._selection = {}
	self._activeSlot = nil
	clearCopies(self._itemList) -- the previous weapon's list
	self._itemRows = {}
	self:_renderCategories()
	self:_showScreen("categories") -- every session starts on the categories
end

-- The controller picks a slot on open; the list only opens when a category is clicked.
function GunsmithView:SetActiveSlot(slot: string?)
	if slot == self._activeSlot then
		return
	end
	self._activeSlot = slot
	if self._screen == "attachments" then
		self:_renderItems()
	end
end

function GunsmithView:SetSelection(loadout: { [string]: string })
	self._selection = table.clone(loadout or {})
	self:_refreshCategoryNames()
	self:_refreshItemMarks()
end

function GunsmithView:SetSummary(_summary: { [string]: any }) end

-- No saved-loadouts screen yet: only remember names so Save picks a fresh one.
function GunsmithView:SetPresets(state: { [string]: any })
	self._presetNames = {}
	for _, preset in ipairs(state.presets or {}) do
		self._presetNames[preset.name] = true
	end
end

function GunsmithView:Flash(message: string, kind: string?)
	local label = self._status
	if not label then
		if kind == "error" then
			warn("[Gunsmith]", message)
		end
		return
	end
	self._flashToken += 1
	local token = self._flashToken
	label.Text = message or ""
	task.delay(3, function()
		if self._flashToken == token and label.Parent then
			label.Text = ""
		end
	end)
end

function GunsmithView:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	clearCopies(self._categoryList)
	clearCopies(self._itemList)
	for element, visible in pairs(self._original) do
		if element.Parent then
			element.Visible = visible
		end
	end
end

return GunsmithView
