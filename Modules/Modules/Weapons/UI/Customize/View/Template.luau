--!nonstrict
-- Customize/View/Template
-- Drives the CustomizeGunGUI that is designed in Roblox Studio (SPH_Assets.HUD.GunGUIs.
-- CustomizeGunGUI) instead of generating a UI. Implements the same view interface as
-- View/init, so the controller does not know which one is used.
--
-- Expected template (the original SPH layout; every element marked * is optional):
--   CustomizeGunGUI (ScreenGui)
--     Hover / Select / Deselect      Sounds*
--     AttachmentsFrame.Padding.AttachmentsColumn
--       <column>                     Frame, one per slot (see "Columns" below)
--         columnheading.title*       TextLabel  - slot label
--         display.items              ScrollingFrame - the attachment items
--           <item>                   Frame with a "padding" child (see "Items" below)
--             padding.itemname       TextLabel  - attachment name (or the Attachment attribute)
--             padding.icon*          ImageLabel - set from the attachment's Icon
--     MainDisplayFrame
--       content.BlankFrame.GunName*  TextLabel  - weapon name
--       content.ConfirmButton        GuiButton
--       content.CloseButton*         GuiButton
--       3DView.3DVPF*                ViewportFrame - 3D preview
--   Anywhere in the ScreenGui (found by name, all optional):
--     RevertButton, ClearAllButton   GuiButtons
--     Summary                        TextLabel  - "2 attachments" / "2 / 3"
--     Status                         TextLabel  - capacity / conflict messages (created if missing)
--
-- Columns: a column is used for slot X when it has the attribute Slot = "X", or is named
--   "X". Otherwise the columns named "column" are assigned in order to the legacy slots
--   (Optics, Underbarrel, Muzzle, Stock). A slot that has options but no column gets a
--   copy of the first column (template.autoColumns).
-- Items: an item is matched to an attachment by its Attachment attribute, else the
--   itemname text. Attachments without a designed item get a copy of the first item
--   (template.autoItems); designed items the weapon can't take are hidden.

local TweenService = game:GetService("TweenService")

local TemplateView = {}
TemplateView.__index = TemplateView

local TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_TWEEN = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local AUTO_ATTRIBUTE = "CustomizeAuto" -- marks clones made by this view (removed on rebuild)

local function rgb(value: any, fallback: Color3): Color3
	if typeof(value) == "Color3" then
		return value
	end
	if type(value) == "table" then
		return Color3.fromRGB(value[1] or 0, value[2] or 0, value[3] or 0)
	end
	return fallback
end

local function scaled(size: UDim2, factor: number): UDim2
	return UDim2.new(size.X.Scale * factor, size.X.Offset * factor, size.Y.Scale * factor, size.Y.Offset * factor)
end

local function find(root: Instance?, path: { string }): Instance?
	local node = root
	for _, name in ipairs(path) do
		node = node and node:FindFirstChild(name)
	end
	return node
end

local function findDeep(root: Instance, name: string, className: string?): Instance?
	local found = root:FindFirstChild(name, true)
	if found and (not className or found:IsA(className)) then
		return found
	end
	return nil
end

-- True when `gui` contains the parts this view cannot work without.
function TemplateView.isTemplate(gui: Instance): boolean
	return find(gui, { "AttachmentsFrame", "Padding", "AttachmentsColumn" }) ~= nil
		and find(gui, { "MainDisplayFrame", "content", "ConfirmButton" }) ~= nil
end

local function itemName(frame: Instance): string?
	local attribute = frame:GetAttribute("Attachment")
	if type(attribute) == "string" and attribute ~= "" then
		return attribute
	end
	local padding = frame:FindFirstChild("padding")
	if not padding then
		return nil
	end
	local label = padding:FindFirstChild("itemname")
	if label and label:IsA("TextLabel") then
		return if label.Text ~= "" then label.Text else nil
	end
	for _, child in ipairs(padding:GetChildren()) do
		if child:IsA("TextLabel") then
			return child.Name -- legacy fallback: a label named after the attachment
		end
	end
	return nil
end

local function isItem(frame: Instance): boolean
	return frame:IsA("GuiObject") and frame:FindFirstChild("padding") ~= nil
end

local function itemsFrame(column: Instance): Instance?
	return find(column, { "display", "items" })
end

-- context = { gui, config, sounds }
function TemplateView.new(context: { [string]: any })
	local self = setmetatable({}, TemplateView)
	self._gui = context.gui
	self._config = context.config
	self._options = context.config.template
	self._text = context.config.text
	self._sounds = context.sounds or {}
	self._actions = {}
	self._connections = {}
	self._slotColumns = {} -- slot -> column
	self._items = {} -- slot -> { [name] = item }
	self._original = {} -- item frame -> original look
	self._selection = {}
	self._flashToken = 0

	local gui = self._gui
	self._container = find(gui, { "AttachmentsFrame", "Padding", "AttachmentsColumn" })
	local content = find(gui, { "MainDisplayFrame", "content" })
	self._confirmButton = content and content:FindFirstChild("ConfirmButton")
	self._closeButton = content and content:FindFirstChild("CloseButton")
	self._gunName = (content and find(content, { "BlankFrame", "GunName" })) or findDeep(gui, "GunName", "TextLabel")
	self._viewport = findDeep(gui, "3DVPF", "ViewportFrame")
	self._revertButton = findDeep(gui, "RevertButton", "GuiButton")
	self._clearAllButton = findDeep(gui, "ClearAllButton", "GuiButton")
	self._summary = findDeep(gui, "Summary", "TextLabel")
	self._status = findDeep(gui, "Status", "TextLabel") or self:_createStatus()

	self:_collectColumns()
	self:_connectButtons()
	return self
end

-- ─── setup ────────────────────────────────────────────────────────────────────

function TemplateView:_createStatus(): TextLabel?
	if not self._options.createStatus then
		return nil
	end
	local label = Instance.new("TextLabel")
	label.Name = "Status"
	label.BackgroundTransparency = 1
	label.AnchorPoint = Vector2.new(0.5, 1)
	label.Position = UDim2.new(0.5, 0, 1, -24)
	label.Size = UDim2.new(0.6, 0, 0, 28)
	label.Font = Enum.Font.GothamMedium
	label.TextScaled = true
	label.TextColor3 = rgb(self._config.theme.warning, Color3.new(1, 0.7, 0.3))
	label.TextStrokeTransparency = 0.5
	label.Text = ""
	label.ZIndex = 50
	label:SetAttribute(AUTO_ATTRIBUTE, true)
	label.Parent = self._gui
	return label
end

function TemplateView:_collectColumns()
	self._columns = {}
	self._prototypeColumn = nil
	self._prototypeItem = nil
	if not self._container then
		return
	end
	local unnamed = {}
	for _, child in ipairs(self._container:GetChildren()) do
		if child:IsA("GuiObject") and itemsFrame(child) then
			if child:GetAttribute(AUTO_ATTRIBUTE) then
				child:Destroy() -- leftover auto column from an earlier session
				continue
			end
			table.insert(self._columns, child)
			local slot = child:GetAttribute("Slot")
			if type(slot) ~= "string" or slot == "" then
				slot = if child.Name ~= "column" then child.Name else nil
			end
			if slot then
				self._slotColumns[slot] = child
			else
				table.insert(unnamed, child)
			end
			child.Active = false
			child.ClipsDescendants = false
		end
	end
	-- Unnamed columns: legacy order. Children order is not guaranteed, LayoutOrder is.
	table.sort(unnamed, function(a, b)
		if a.LayoutOrder ~= b.LayoutOrder then
			return a.LayoutOrder < b.LayoutOrder
		end
		return table.find(self._columns, a) < table.find(self._columns, b)
	end)
	local legacyOrder = self._options.legacyOrder or {}
	for index, column in ipairs(unnamed) do
		local slot = legacyOrder[index]
		if slot and not self._slotColumns[slot] then
			self._slotColumns[slot] = column
		end
	end
	self._prototypeColumn = self._columns[1]
	for _, column in ipairs(self._columns) do
		local items = itemsFrame(column)
		for _, child in ipairs(items and items:GetChildren() or {}) do
			if isItem(child) then
				if child:GetAttribute(AUTO_ATTRIBUTE) then
					child:Destroy()
				elseif not self._prototypeItem then
					self._prototypeItem = child
				end
			end
		end
	end
end

function TemplateView:_connect(signal, fn)
	table.insert(self._connections, signal:Connect(fn))
end

function TemplateView:_connectButtons()
	if self._confirmButton and self._confirmButton:IsA("GuiButton") then
		self:_connect(self._confirmButton.MouseButton1Click, function()
			self:_act("confirm")
		end)
	end
	if self._closeButton and self._closeButton:IsA("GuiButton") then
		self:_connect(self._closeButton.MouseButton1Click, function()
			self:_act("close")
		end)
	end
	if self._revertButton then
		self:_connect(self._revertButton.MouseButton1Click, function()
			self:_act("revert")
		end)
	end
	if self._clearAllButton then
		self:_connect(self._clearAllButton.MouseButton1Click, function()
			for slot in pairs(self._selection) do
				self:_act("clear", slot)
			end
		end)
	end
end

-- ─── interface ────────────────────────────────────────────────────────────────

function TemplateView:Bind(actions: { [string]: any })
	self._actions = actions
end

function TemplateView:_act(name: string, ...: any)
	local action = self._actions[name]
	if action then
		action(...)
	end
end

function TemplateView:PlaySound(kind: string)
	local sound = self._sounds[kind]
	if sound then
		pcall(function()
			sound:Play()
		end)
	end
end

function TemplateView:SetWeapon(name: string)
	if self._gunName then
		self._gunName.Text = name
	end
end

function TemplateView:GetViewport(): ViewportFrame?
	return self._viewport
end

function TemplateView:SetActiveSlot(_slot: string?)
	-- every column is visible at once in this layout; nothing to do
end

function TemplateView:_columnFor(slot: any): Instance?
	local column = self._slotColumns[slot.name]
	if column or not self._options.autoColumns or not self._prototypeColumn or #slot.options == 0 then
		return column
	end
	column = self._prototypeColumn:Clone()
	column.Name = slot.name
	column:SetAttribute("Slot", slot.name)
	column:SetAttribute(AUTO_ATTRIBUTE, true)
	column.LayoutOrder = self._prototypeColumn.LayoutOrder + slot.order
	local items = itemsFrame(column)
	for _, child in ipairs(items and items:GetChildren() or {}) do
		if isItem(child) then
			child:Destroy() -- the copy gets its own items from the catalog
		end
	end
	column.Parent = self._container
	self._slotColumns[slot.name] = column
	return column
end

function TemplateView:_remember(frame: GuiObject)
	if not self._original[frame] then
		self._original[frame] = {
			Size = frame.Size,
			Position = frame.Position,
			AnchorPoint = frame.AnchorPoint,
			BackgroundColor3 = frame.BackgroundColor3,
			BackgroundTransparency = frame.BackgroundTransparency,
		}
	end
	return self._original[frame]
end

function TemplateView:_restore(frame: GuiObject)
	local original = self._original[frame]
	if original then
		for property, value in pairs(original) do
			frame[property] = value
		end
	end
end

function TemplateView:_makeAutoItem(items: Instance, option: any): GuiObject?
	if not self._options.autoItems or not self._prototypeItem then
		return nil
	end
	local frame = self._prototypeItem:Clone()
	self:_restore(frame) -- the prototype may be mid-tween
	frame.Name = option.name
	frame:SetAttribute("Attachment", option.name)
	frame:SetAttribute(AUTO_ATTRIBUTE, true)
	local old = frame:FindFirstChild("ClickButton")
	if old then
		old:Destroy()
	end
	frame.Parent = items
	return frame
end

function TemplateView:_wireItem(frame: GuiObject, slotName: string, option: any)
	local original = self:_remember(frame)
	self:_restore(frame)
	frame.Visible = true
	frame.Active = false
	frame.ClipsDescendants = false

	local padding = frame:FindFirstChild("padding")
	local label = padding and padding:FindFirstChild("itemname")
	if label and label:IsA("TextLabel") and (frame:GetAttribute(AUTO_ATTRIBUTE) or label.Text == "") then
		label.Text = option.label or option.name
	end
	local icon = padding and padding:FindFirstChild("icon")
	if icon and icon:IsA("ImageLabel") and option.icon then
		icon.Image = option.icon
	end
	if not option.available then
		frame.BackgroundTransparency = math.max(original.BackgroundTransparency, self._options.unavailableTransparency)
	end

	local button = frame:FindFirstChild("ClickButton")
	if button then
		button:Destroy() -- drop connections from an earlier session
	end
	button = Instance.new("TextButton")
	button.Name = "ClickButton"
	button.Size = UDim2.fromScale(1, 1)
	button.BackgroundTransparency = 1
	button.Text = ""
	button.AutoButtonColor = false
	button.ZIndex = 10000
	button.Parent = frame
	-- clicks must reach the overlay: legacy made the item's ancestors non-Active
	local node = frame.Parent
	while node and node ~= self._gui and node:IsA("GuiObject") do
		node.Active = false
		node = node.Parent
	end

	button.MouseEnter:Connect(function()
		self:PlaySound("hover")
		if self._selection[slotName] == option.name then
			return
		end
		local base = original.Size
		local tween = TweenService:Create(frame, HOVER_TWEEN, { Size = scaled(base, self._options.hoverScale) })
		tween.Completed:Connect(function()
			if frame.Parent and self._selection[slotName] ~= option.name then
				TweenService:Create(frame, HOVER_TWEEN, { Size = base }):Play()
			end
		end)
		tween:Play()
	end)
	button.MouseButton1Click:Connect(function()
		if not option.available then
			self:Flash(option.reason or "Not available for this weapon", "warning")
			return
		end
		self:_act("pick", slotName, option.name) -- picking the selected item clears it (legacy)
	end)
	button.MouseButton2Click:Connect(function()
		self:_act("clear", slotName)
	end)
end

function TemplateView:SetCatalog(catalog: { slots: { any } })
	-- reset everything from the previous weapon
	for frame in pairs(self._original) do
		if frame.Parent then
			self:_restore(frame)
		end
	end
	for _, column in ipairs(self._container and self._container:GetChildren() or {}) do
		if column:GetAttribute(AUTO_ATTRIBUTE) then
			self._slotColumns[column:GetAttribute("Slot")] = nil
			column:Destroy()
		else
			local items = itemsFrame(column)
			for _, child in ipairs(items and items:GetChildren() or {}) do
				if child:GetAttribute(AUTO_ATTRIBUTE) then
					self._original[child] = nil
					child:Destroy()
				elseif isItem(child) then
					child.Visible = false
				end
			end
		end
	end
	self._items = {}

	local used = {}
	for _, slot in ipairs(catalog.slots or {}) do
		local column = self:_columnFor(slot)
		if not column then
			if #slot.options > 0 then
				warn(("[CustomizeUI] no column for slot %q in the template; add a column named %q"):format(slot.name, slot.name))
			end
			continue
		end
		used[column] = true
		column.Visible = true
		local title = find(column, { "columnheading", "title" })
		if title and title:IsA("TextLabel") then
			title.Text = slot.label or slot.name
		end
		local items = itemsFrame(column)
		local designed = {}
		for _, child in ipairs(items:GetChildren()) do
			if isItem(child) then
				local name = itemName(child)
				if name then
					designed[name] = child
				end
			end
		end
		local slotItems = {}
		for index, option in ipairs(slot.options) do
			local frame = designed[option.name] or self:_makeAutoItem(items, option)
			if frame then
				if frame:GetAttribute(AUTO_ATTRIBUTE) then
					frame.LayoutOrder = 1000 + index -- after the designed items
				end
				self:_wireItem(frame, slot.name, option)
				slotItems[option.name] = frame
			end
		end
		self._items[slot.name] = slotItems
	end
	-- columns with no slot for this weapon
	for _, column in ipairs(self._columns) do
		if not used[column] then
			column.Visible = not self._options.hideEmptyColumns
		end
	end
	for _, slot in ipairs(catalog.slots or {}) do
		local column = self._slotColumns[slot.name]
		if column and #slot.options == 0 and self._options.hideEmptyColumns then
			column.Visible = false
		end
	end
end

function TemplateView:SetSelection(loadout: { [string]: string })
	self._selection = loadout or {}
	local selectedColor = rgb(self._options.selectedColor, Color3.fromRGB(100, 200, 100))
	for slot, items in pairs(self._items) do
		for name, frame in pairs(items) do
			local original = self._original[frame]
			if not original then
				continue
			end
			if self._selection[slot] == name then
				-- grow from the centre, like the original UI
				local size, position = original.Size, original.Position
				frame.AnchorPoint = Vector2.new(0.5, 0.5)
				frame.Position = UDim2.new(
					position.X.Scale + size.X.Scale * (0.5 - original.AnchorPoint.X),
					position.X.Offset + size.X.Offset * (0.5 - original.AnchorPoint.X),
					position.Y.Scale + size.Y.Scale * (0.5 - original.AnchorPoint.Y),
					position.Y.Offset + size.Y.Offset * (0.5 - original.AnchorPoint.Y)
				)
				TweenService:Create(frame, TWEEN, {
					BackgroundColor3 = selectedColor,
					BackgroundTransparency = 0,
					Size = scaled(size, self._options.selectedScale),
				}):Play()
			else
				TweenService:Create(frame, TWEEN, {
					BackgroundColor3 = original.BackgroundColor3,
					BackgroundTransparency = original.BackgroundTransparency,
					Size = original.Size,
				}):Play()
				frame.AnchorPoint = original.AnchorPoint
				frame.Position = original.Position
			end
		end
	end
end

function TemplateView:SetSummary(summary: { count: number, capacity: number?, dirty: boolean })
	if self._revertButton then
		self._revertButton.Visible = summary.dirty
	end
	if self._summary then
		local text = self._text
		local count = if summary.capacity
			then text.countWithCapacity:format(summary.count, summary.capacity)
			else text.count:format(summary.count)
		self._summary.Text = if summary.dirty then count .. "  ·  " .. text.unsaved else count
	end
end

function TemplateView:Flash(message: string, kind: string?)
	local label = self._status
	if not label then
		warn("[CustomizeUI]", message)
		return
	end
	local theme = self._config.theme
	self._flashToken += 1
	local token = self._flashToken
	label.Text = message or ""
	label.TextColor3 = rgb(
		if kind == "error" then theme.danger elseif kind == "info" then theme.subtext else theme.warning,
		Color3.new(1, 1, 1)
	)
	task.delay(3, function()
		if self._flashToken == token and label.Parent then
			label.Text = ""
		end
	end)
end

function TemplateView:Destroy()
	for _, connection in ipairs(self._connections) do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for frame in pairs(self._original) do
		if frame.Parent then
			self:_restore(frame)
			local button = frame:FindFirstChild("ClickButton")
			if button then
				button:Destroy()
			end
		end
	end
	for _, descendant in ipairs(self._gui:GetDescendants()) do
		if descendant:GetAttribute(AUTO_ATTRIBUTE) then
			descendant:Destroy()
		end
	end
end

return TemplateView
