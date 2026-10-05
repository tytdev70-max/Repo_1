--!nonstrict
-- Customize/View  (default view)
-- Builds the customization window procedurally inside the given ScreenGui. Holds no
-- game logic: it renders what the controller tells it and reports user intent
-- through the bound actions. Replace it entirely with config.view (same interface).
--
-- ┌ header: title · weapon name ·························· [✕] ┐
-- │ slot rail (scroll) │   3D preview viewport   │ option grid (scroll) │
-- └ footer: count / capacity · unsaved · message ···· [Revert] [CONFIRM] ┘
--
-- View interface (what a custom view must implement):
--   view:Bind(actions)   actions = { selectSlot(slot), pick(slot, name?), clear(slot),
--                                    confirm(), revert(), close() }
--   view:SetWeapon(name)
--   view:SetCatalog(catalog)          -- catalog from Customize/Catalog
--   view:SetActiveSlot(slotName?)
--   view:SetSelection(loadout)        -- slot -> attachment name
--   view:SetSummary({ count, capacity?, dirty })
--   view:Flash(message, kind?)        -- kind: "info" | "warning" | "error"
--   view:PlaySound("hover" | "select" | "deselect")
--   view:GetViewport() -> ViewportFrame?
--   view:Destroy()

local Components = require(script.Components)

local create = Components.create
local color = Components.color
local font = Components.font
local text = Components.text

local View = {}
View.__index = View

-- context = { gui: ScreenGui, config: resolved config, sounds: { hover?, select?, deselect? } }
function View.new(context: { [string]: any })
	local self = setmetatable({}, View)
	self._gui = context.gui
	self._config = context.config
	self._theme = context.config.theme
	self._layout = context.config.layout
	self._text = context.config.text
	self._sounds = context.sounds or {}
	self._actions = {}
	self._catalog = { slots = {} }
	self._selection = {}
	self._activeSlot = nil
	self._slotTabs = {} -- slot -> tab
	self._cards = {} -- name ("" for None) -> card (for the active slot)
	self._flashToken = 0
	self:_build()
	return self
end

function View:Bind(actions: { [string]: any })
	self._actions = actions
end

function View:_act(name: string, ...: any)
	local action = self._actions[name]
	if action then
		action(...)
	end
end

function View:PlaySound(kind: string)
	local sound = self._sounds[kind]
	if sound then
		pcall(function()
			sound:Play()
		end)
	end
end

-- ─── construction ────────────────────────────────────────────────────────────

function View:_panel(props: { [string]: any }): Frame
	local theme = self._theme
	local panel = create("Frame", {
		Name = props.Name,
		BackgroundColor3 = color(theme.panel),
		BackgroundTransparency = theme.panelTransparency,
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position,
		ClipsDescendants = true,
		Parent = props.Parent,
	}) :: any
	Components.corner(panel, theme.corner)
	Components.stroke(panel, color(theme.stroke), 1, 0.35)
	return panel
end

function View:_build()
	local theme, layout, strings = self._theme, self._layout, self._text
	local gap = layout.gap

	local root = create("Frame", {
		Name = "CustomizeRoot",
		BackgroundColor3 = color(theme.backdrop),
		BackgroundTransparency = theme.backdropTransparency,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Active = true, -- swallow clicks so they don't reach the world
		ZIndex = 1,
		Parent = self._gui,
	}) :: any
	self._root = root

	local window = create("Frame", {
		Name = "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(layout.windowSize[1], layout.windowSize[2]),
		BackgroundColor3 = color(theme.window),
		BackgroundTransparency = theme.windowTransparency,
		BorderSizePixel = 0,
		Parent = root,
	}) :: any
	Components.corner(window, theme.corner + 4)
	Components.stroke(window, color(theme.stroke), 1, 0.2)
	create("UISizeConstraint", {
		MaxSize = Vector2.new(layout.windowMaxPixels[1], layout.windowMaxPixels[2]),
		Parent = window,
	})
	Components.padding(window, gap + 4)
	self._window = window

	-- header
	local header = create("Frame", {
		Name = "Header",
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, layout.headerHeight, 0),
		Parent = window,
	}) :: any
	text({
		Name = "Title",
		Text = strings.title,
		Font = font(theme.fontBold),
		TextColor3 = color(theme.subtext),
		Size = UDim2.fromScale(0.5, 0.42),
		Parent = header,
	}, 14)
	self._weaponLabel = text({
		Name = "WeaponName",
		Text = "",
		Font = font(theme.fontBold),
		TextColor3 = color(theme.text),
		Size = UDim2.fromScale(0.8, 0.58),
		Position = UDim2.fromScale(0, 0.42),
		Parent = header,
	}, 30)
	local closeButton = Components.button({
		Name = "CloseButton",
		Text = "✕",
		Bold = true,
		Size = UDim2.fromScale(0.75, 0.75),
		Position = UDim2.fromScale(1, 0.5),
		AnchorPoint = Vector2.new(1, 0.5),
		MaxTextSize = 20,
		Parent = header,
	}, theme)
	create("UIAspectRatioConstraint", { AspectRatio = 1, Parent = closeButton })
	closeButton.MouseButton1Click:Connect(function()
		self:_act("close")
	end)

	-- body
	local bodyTop = layout.headerHeight
	local bodyHeight = 1 - layout.headerHeight - layout.footerHeight
	local body = create("Frame", {
		Name = "Body",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, bodyTop, gap / 2),
		Size = UDim2.new(1, 0, bodyHeight, -gap),
		Parent = window,
	}) :: any

	local railWidth, panelWidth = layout.railWidth, layout.panelWidth
	local rail = self:_panel({
		Name = "SlotRail",
		Size = UDim2.new(railWidth, -gap / 2, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		Parent = body,
	})
	local stage = self:_panel({
		Name = "Stage",
		Size = UDim2.new(1 - railWidth - panelWidth, -gap, 1, 0),
		Position = UDim2.new(railWidth, gap / 2, 0, 0),
		Parent = body,
	})
	local panel = self:_panel({
		Name = "OptionPanel",
		Size = UDim2.new(panelWidth, -gap / 2, 1, 0),
		Position = UDim2.new(1 - panelWidth, gap / 2, 0, 0),
		Parent = body,
	})

	-- slot rail
	text({
		Name = "Heading",
		Text = strings.slotsHeader,
		Font = font(theme.fontBold),
		TextColor3 = color(theme.subtext),
		Size = UDim2.new(1, -24, 0, 28),
		Position = UDim2.fromOffset(12, 6),
		Parent = rail,
	}, 13)
	local slotList = create("ScrollingFrame", {
		Name = "Slots",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 38),
		Size = UDim2.new(1, 0, 1, -44),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = color(theme.stroke),
		Parent = rail,
	}) :: any
	create("UIListLayout", {
		Padding = UDim.new(0, 6),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = slotList,
	})
	create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8), Parent = slotList })
	self._slotList = slotList

	-- stage (3D preview)
	local viewport = create("ViewportFrame", {
		Name = "Preview",
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(170, 170, 170),
		LightColor = Color3.fromRGB(255, 255, 255),
		LightDirection = Vector3.new(-1, -1, -0.5),
		Active = true,
		Parent = stage,
	}) :: any
	self._viewport = viewport
	text({
		Name = "Hint",
		Text = strings.hint,
		Font = font(theme.font),
		TextColor3 = color(theme.subtext),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -20, 0, 22),
		Position = UDim2.new(0.5, 0, 1, -10),
		AnchorPoint = Vector2.new(0.5, 1),
		ZIndex = 3,
		Parent = stage,
	}, 13)
	self._emptyLabel = text({
		Name = "Empty",
		Text = "",
		Font = font(theme.font),
		TextColor3 = color(theme.subtext),
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(0.8, 0, 0, 30),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Parent = stage,
	}, 16)

	-- option panel
	self._panelTitle = text({
		Name = "SlotTitle",
		Text = "",
		Font = font(theme.fontBold),
		TextColor3 = color(theme.text),
		Size = UDim2.new(0.65, -12, 0, 28),
		Position = UDim2.fromOffset(12, 6),
		Parent = panel,
	}, 18)
	local clearButton = Components.button({
		Name = "ClearButton",
		Text = strings.clear,
		Size = UDim2.new(0.3, -12, 0, 26),
		Position = UDim2.new(1, -10, 0, 7),
		AnchorPoint = Vector2.new(1, 0),
		MaxTextSize = 14,
		Parent = panel,
	}, theme)
	clearButton.MouseButton1Click:Connect(function()
		if self._activeSlot then
			self:_act("clear", self._activeSlot)
		end
	end)
	self._clearButton = clearButton
	local grid = create("ScrollingFrame", {
		Name = "Options",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(1, 0, 1, -46),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = color(theme.stroke),
		Parent = panel,
	}) :: any
	local cell = layout.optionCell
	create("UIGridLayout", {
		CellSize = UDim2.new(cell[1], cell[2], cell[3], cell[4]),
		CellPadding = UDim2.fromOffset(layout.optionPadding, layout.optionPadding),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Parent = grid,
	})
	create("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10), Parent = grid })
	self._grid = grid

	-- footer
	local footer = create("Frame", {
		Name = "Footer",
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 0, 1 - layout.footerHeight, 0),
		Size = UDim2.new(1, 0, layout.footerHeight, 0),
		Parent = window,
	}) :: any
	self._summaryLabel = text({
		Name = "Summary",
		Text = "",
		Font = font(theme.font),
		TextColor3 = color(theme.subtext),
		Size = UDim2.new(0.5, 0, 0.42, 0),
		Position = UDim2.fromScale(0, 0.1),
		Parent = footer,
	}, 15)
	self._messageLabel = text({
		Name = "Message",
		Text = "",
		Font = font(theme.font),
		TextColor3 = color(theme.warning),
		Size = UDim2.new(0.55, 0, 0.38, 0),
		Position = UDim2.fromScale(0, 0.55),
		Parent = footer,
	}, 14)
	local confirmButton = Components.button({
		Name = "ConfirmButton",
		Text = strings.confirm,
		Bold = true,
		BackgroundColor3 = color(theme.accent),
		HoverColor3 = color(theme.accent):Lerp(Color3.new(1, 1, 1), 0.15),
		TextColor3 = color(theme.accentText),
		Size = UDim2.new(0.2, 0, 0.78, 0),
		Position = UDim2.fromScale(1, 0.5),
		AnchorPoint = Vector2.new(1, 0.5),
		MaxTextSize = 20,
		Parent = footer,
	}, theme)
	confirmButton.MouseButton1Click:Connect(function()
		self:_act("confirm")
	end)
	local revertButton = Components.button({
		Name = "RevertButton",
		Text = strings.revert,
		Size = UDim2.new(0.13, 0, 0.78, 0),
		Position = UDim2.new(0.8, -gap, 0.5, 0),
		AnchorPoint = Vector2.new(1, 0.5),
		MaxTextSize = 16,
		Parent = footer,
	}, theme)
	revertButton.MouseButton1Click:Connect(function()
		self:_act("revert")
	end)
	self._revertButton = revertButton
end

-- ─── rendering ───────────────────────────────────────────────────────────────

function View:SetWeapon(name: string)
	self._weaponLabel.Text = name or ""
end

function View:GetViewport(): ViewportFrame?
	return self._viewport
end

local function optionLabel(slot: any, name: string?): string?
	if not name then
		return nil
	end
	for _, option in ipairs(slot.options) do
		if option.name == name then
			return option.label
		end
	end
	return name
end

function View:_findSlot(slotName: string?): any
	if not slotName then
		return nil
	end
	for _, slot in ipairs(self._catalog.slots) do
		if slot.name == slotName then
			return slot
		end
	end
	return nil
end

function View:SetCatalog(catalog: { slots: { any } })
	self._catalog = catalog
	for _, tab in pairs(self._slotTabs) do
		tab:Destroy()
	end
	table.clear(self._slotTabs)
	local theme = self._theme
	for index, slot in ipairs(catalog.slots) do
		local tab = Components.button({
			Name = "Slot_" .. slot.name,
			Size = UDim2.new(1, -12, 0, self._layout.slotTabHeight),
			BackgroundColor3 = color(theme.card),
			Parent = self._slotList,
		}, theme) :: any
		tab.LayoutOrder = index
		create("Frame", {
			Name = "Accent",
			BackgroundColor3 = color(theme.accent),
			BorderSizePixel = 0,
			Size = UDim2.new(0, 4, 0.6, 0),
			Position = UDim2.new(0, 4, 0.2, 0),
			Visible = false,
			ZIndex = 3,
			Parent = tab,
		})
		text({
			Name = "SlotName",
			Text = slot.label,
			Font = font(theme.fontBold),
			TextColor3 = color(theme.text),
			Size = UDim2.new(1, -24, 0.45, 0),
			Position = UDim2.new(0, 16, 0.08, 0),
			ZIndex = 3,
			Parent = tab,
		}, 16)
		text({
			Name = "Current",
			Text = self._text.empty,
			Font = font(theme.font),
			TextColor3 = color(theme.subtext),
			Size = UDim2.new(1, -24, 0.38, 0),
			Position = UDim2.new(0, 16, 0.53, 0),
			ZIndex = 3,
			Parent = tab,
		}, 13)
		tab.MouseEnter:Connect(function()
			self:PlaySound("hover")
		end)
		tab.MouseButton1Click:Connect(function()
			self:_act("selectSlot", slot.name)
		end)
		self._slotTabs[slot.name] = tab
	end
	self._emptyLabel.Text = if #catalog.slots == 0 then self._text.noSlots else ""
	self:_refreshTabs()
end

function View:SetActiveSlot(slotName: string?)
	self._activeSlot = slotName
	for _, card in pairs(self._cards) do
		card:Destroy()
	end
	table.clear(self._cards)

	local slot = self:_findSlot(slotName)
	self._panelTitle.Text = slot and slot.label or ""
	self._clearButton.Visible = slot ~= nil and slot.allowEmpty
	if slot then
		local order = 0
		if slot.allowEmpty then
			order += 1
			self:_makeCard(slot, { name = "", label = self._text.none, available = true }, order)
		end
		for _, option in ipairs(slot.options) do
			order += 1
			self:_makeCard(slot, option, order)
		end
	end
	self:_refreshTabs()
	self:_refreshCards()
end

function View:_makeCard(slot: any, option: any, order: number)
	local theme = self._theme
	local available = option.available ~= false
	local card = Components.button({
		Name = if option.name == "" then "Option_None" else "Option_" .. option.name,
		BackgroundColor3 = color(if available then theme.card else theme.cardUnavailable),
		Parent = self._grid,
	}, theme) :: any
	card.LayoutOrder = order
	card:SetAttribute("Available", available)
	local hasIcon = option.icon ~= nil
	if hasIcon then
		create("ImageLabel", {
			Name = "Icon",
			BackgroundTransparency = 1,
			Image = option.icon,
			ScaleType = Enum.ScaleType.Fit,
			Size = UDim2.new(1, -16, 0.58, -6),
			Position = UDim2.fromOffset(8, 6),
			ImageTransparency = if available then 0 else 0.6,
			ZIndex = 3,
			Parent = card,
		})
	end
	text({
		Name = "OptionName",
		Text = option.label,
		Font = font(theme.fontBold),
		TextColor3 = color(if available then theme.text else theme.subtext),
		TextXAlignment = Enum.TextXAlignment.Center,
		TextWrapped = true,
		Size = if hasIcon then UDim2.new(1, -12, 0.34, 0) else UDim2.new(1, -12, if available then 0.7 else 0.5, 0),
		Position = if hasIcon then UDim2.new(0.5, 0, 1, -6) else UDim2.fromScale(0.5, if available then 0.5 else 0.38),
		AnchorPoint = if hasIcon then Vector2.new(0.5, 1) else Vector2.new(0.5, 0.5),
		ZIndex = 3,
		Parent = card,
	}, 15)
	if not available and not hasIcon then
		text({
			Name = "Reason",
			Text = option.reason or "",
			Font = font(theme.font),
			TextColor3 = color(theme.subtext),
			TextXAlignment = Enum.TextXAlignment.Center,
			TextWrapped = true,
			Size = UDim2.new(1, -12, 0.3, 0),
			Position = UDim2.fromScale(0.5, 0.75),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = 3,
			Parent = card,
		}, 11)
	end
	card.MouseEnter:Connect(function()
		self:PlaySound("hover")
	end)
	card.MouseButton1Click:Connect(function()
		if not available then
			self:Flash(option.reason or "Unavailable", "warning")
			return
		end
		self:_act("pick", slot.name, if option.name == "" then nil else option.name)
	end)
	self._cards[option.name] = card
end

function View:_refreshTabs()
	local theme = self._theme
	for slotName, tab in pairs(self._slotTabs) do
		local slot = self:_findSlot(slotName)
		local active = slotName == self._activeSlot
		local current = tab:FindFirstChild("Current")
		local picked = self._selection[slotName]
		if current then
			local label = slot and optionLabel(slot, picked) or picked
			current.Text = label or self._text.empty
			current.TextColor3 = color(if picked then theme.accent else theme.subtext)
		end
		local accent = tab:FindFirstChild("Accent")
		if accent then
			accent.Visible = active
		end
		local base = color(if active then theme.hover else theme.card)
		tab:SetAttribute("BaseColor", base)
		tab:SetAttribute("Locked", active)
		Components.tween(tab, theme.tweenTime, { BackgroundColor3 = base })
	end
end

function View:_refreshCards()
	local theme = self._theme
	local picked = self._activeSlot and self._selection[self._activeSlot] or nil
	for name, card in pairs(self._cards) do
		local selected = (name == "" and picked == nil) or (name ~= "" and name == picked)
		local unavailable = card:GetAttribute("Available") == false and not selected
		local base = if selected then color(theme.accent) elseif unavailable then color(theme.cardUnavailable) else color(theme.card)
		card:SetAttribute("BaseColor", base)
		card:SetAttribute("Locked", selected)
		Components.tween(card, theme.tweenTime, { BackgroundColor3 = base })
		local label = card:FindFirstChild("OptionName")
		if label then
			label.TextColor3 = color(if selected then theme.accentText elseif unavailable then theme.subtext else theme.text)
		end
		local stroke = card:FindFirstChildOfClass("UIStroke") or Components.stroke(card, color(theme.accent), 2, 1)
		stroke.Transparency = if selected then 0 else 1
	end
end

function View:SetSelection(loadout: { [string]: string })
	self._selection = loadout or {}
	self:_refreshTabs()
	self:_refreshCards()
end

function View:SetSummary(summary: { count: number, capacity: number?, dirty: boolean })
	local strings = self._text
	local countText = if summary.capacity
		then strings.countWithCapacity:format(summary.count, summary.capacity)
		else strings.count:format(summary.count)
	self._summaryLabel.Text = if summary.dirty then countText .. "  ·  " .. strings.unsaved else countText
	self._revertButton.Visible = summary.dirty
end

function View:Flash(message: string, kind: string?)
	local theme = self._theme
	self._flashToken += 1
	local token = self._flashToken
	self._messageLabel.Text = message or ""
	self._messageLabel.TextColor3 = color(if kind == "error" then theme.danger elseif kind == "info" then theme.subtext else theme.warning)
	task.delay(3, function()
		if self._flashToken == token and self._messageLabel.Parent then
			self._messageLabel.Text = ""
		end
	end)
end

function View:Destroy()
	if self._root then
		self._root:Destroy()
		self._root = nil
	end
end

return View
