--[[
	AttachmentSystem.Gunsmith.View
	──────────────────────────────
	The gunsmith menu itself: the column of attachment buttons, their select /
	deselect / hover states, and the 3D preview that updates as the selection
	changes.

	This is a faithful port of the menu that previously lived at
	`SPH_Assets.HUD.CustomizeGunGUI`. Two things changed:

	  • every attachment query now goes through the system API rather than
	    reaching into the asset folder and the config cache directly, and
	  • the preview's mounting maths now comes from `Mounter` (see Preview3D).

	The template ScreenGui this builds on still has to have the same instance
	names as before (`MainDisplayFrame`, `content`, `ConfirmButton`, the
	`attachments` column, and each item's `padding` → `itemname`). That is the
	one thing the system asks of the host's GUI.
]]

local TweenService   = game:GetService("TweenService")
local RunService     = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config    = require(script.Parent.Parent.Config)
local Preview3D = require(script.Preview3D)

local View = {}

View.__index = View

local BUTTON_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HOVER_TWEEN  = TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local SELECTED_COLOR = Color3.fromRGB(100, 200, 100)
local IDLE_COLOR     = Color3.fromRGB(50, 50, 50)

function View.new(options)
	local self = setmetatable({
		gui            = options.gui,
		system         = options.system,
		host           = options.host,
		onSelectionChanged = options.onSelectionChanged,
		onConfirm      = options.onConfirm,

		weapon   = nil,
		weaponName = nil,
		selection = {},

		buttons   = {},   -- GuiButton -> { category, name, frame, originalSize, originalPosition, tween }
		selected  = {},   -- category -> GuiButton
		columnButtons = {},-- column index -> { GuiButton }

		preview = nil,
		enabledConnection = nil,
		preRenderConnection = nil,
	}, View)

	self:_connectGui()
	return self
end

-- ─── Template discovery ─────────────────────────────────────────────────────

function View:_discover()
	local gui = self.gui
	if not gui then
		return nil
	end

	local main = gui:FindFirstChild("MainDisplayFrame")
	if not main then
		warn("[AttachmentSystem] gunsmith template has no MainDisplayFrame")
		return nil
	end

	local content = main:FindFirstChild("content")
	if not content then
		warn("[AttachmentSystem] gunsmith template has no MainDisplayFrame.content")
		return nil
	end

	local attachments = main:FindFirstChild("attachments")
	local viewport = nil
	local threeD = main:FindFirstChild("3DView")
	if threeD then
		viewport = threeD:FindFirstChild("3DVPF")
	end

	return {
		main          = main,
		content       = content,
		confirmButton = content:FindFirstChild("ConfirmButton"),
		closeButton   = content:FindFirstChild("CloseButton"),
		gunNameLabel  = main:FindFirstChild("gunname") or main:FindFirstChild("GunName"),
		attachments   = attachments,
		viewport      = viewport,
	}
end

-- ─── Selection ──────────────────────────────────────────────────────────────

function View:GetSelection(): { [string]: string }
	return self.selection
end

function View:SetEntry(category: string, name: string?)
	if type(name) == "string" and name ~= "" then
		self.selection[category] = name
	else
		self.selection[category] = nil
	end
	self:_syncVisuals()
	if self.onSelectionChanged then
		self.onSelectionChanged(self.selection)
	end
end

function View:ClearSelection()
	table.clear(self.selection)
	self:_syncVisuals()
end

function View:_syncVisuals()
	for category, button in pairs(self.selected) do
		if self.selection[category] == nil then
			self:_deselectVisual(button, false)
			self.selected[category] = nil
		end
	end

	for category, name in pairs(self.selection) do
		for button, data in pairs(self.buttons) do
			if data.category == category and data.name == name then
				local previous = self.selected[category]
				if previous and previous ~= button then
					self:_deselectVisual(previous, false)
				end
				self.selected[category] = button
				self:_selectVisual(button, false)
			end
		end
	end
end

-- ─── Button states ──────────────────────────────────────────────────────────

local function scaleFromCenter(size, factor)
	return UDim2.new(
		size.X.Scale * factor, size.X.Offset * factor,
		size.Y.Scale * factor, size.Y.Offset * factor
	)
end

function View:_deselectVisual(button: GuiButton, playSound: boolean?)
	local data = self.buttons[button]
	if not data or not data.frame then
		return
	end
	if data.tween then
		pcall(function() data.tween:Cancel() end)
		data.tween = nil
	end

	local tween = TweenService:Create(data.frame, BUTTON_TWEEN, {
		BackgroundColor3      = IDLE_COLOR,
		BackgroundTransparency = 0.3,
		Size                   = data.originalSize or data.frame.Size,
		Position               = data.originalPosition or data.frame.Position,
		AnchorPoint            = Vector2.new(0, 0),
	})
	data.tween = tween
	tween:Play()
	tween.Completed:Connect(function()
		if data.tween == tween then data.tween = nil end
	end)

	if playSound ~= false then
		self:_playSound("deselect")
	end
end

function View:_selectVisual(button: GuiButton, playSound: boolean?)
	local data = self.buttons[button]
	if not data or not data.frame then
		return
	end
	if data.tween then
		pcall(function() data.tween:Cancel() end)
		data.tween = nil
	end

	local frame = data.frame
	if not data.originalSize then data.originalSize = frame.Size end
	if not data.originalPosition then data.originalPosition = frame.Position end

	local centerX        = data.originalPosition.X.Scale + data.originalSize.X.Scale / 2
	local centerXOffset  = data.originalPosition.X.Offset + data.originalSize.X.Offset / 2
	local centerY        = data.originalPosition.Y.Scale + data.originalSize.Y.Scale / 2
	local centerYOffset  = data.originalPosition.Y.Offset + data.originalSize.Y.Offset / 2

	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position    = UDim2.new(centerX, centerXOffset, centerY, centerYOffset)

	local tween = TweenService:Create(frame, BUTTON_TWEEN, {
		BackgroundColor3      = SELECTED_COLOR,
		BackgroundTransparency = 0,
		Size                   = scaleFromCenter(data.originalSize, 1.03),
	})
	data.tween = tween
	tween:Play()
	tween.Completed:Connect(function()
		if data.tween == tween then data.tween = nil end
	end)

	if playSound ~= false then
		self:_playSound("select")
	end
end

function View:_playHover(button: GuiButton)
	local data = self.buttons[button]
	if not data or not data.frame then
		return
	end
	self:_playSound("hover")

	for _, selectedButton in pairs(self.selected) do
		if selectedButton == button then
			return
		end
	end

	local frame = data.frame
	local base  = data.originalSize or frame.Size
	local tween = TweenService:Create(frame, HOVER_TWEEN, { Size = scaleFromCenter(base, 1.01) })
	tween:Play()
	tween.Completed:Connect(function()
		if self.buttons[button] then
			TweenService:Create(frame, HOVER_TWEEN, { Size = base }):Play()
		end
	end)
end

function View:_playSound(kind: string)
	local sounds = self.host and self.host.sounds
	if sounds and sounds[kind] then
		pcall(function() sounds[kind]:Play() end)
	end
end

-- ─── Building the columns ───────────────────────────────────────────────────

--[[
	Read the attachment name a template item frame represents. The original
	menu looked for a `padding` → `itemname` label and fell back to the first
	TextLabel child; both are supported here.
]]
local function readItemName(item: Instance): string?
	local padding = item:FindFirstChild("padding")
	if not padding then
		return nil
	end

	local itemName = padding:FindFirstChild("itemname")
	if itemName and itemName:IsA("TextLabel") then
		if itemName.Text ~= "" then
			return itemName.Text
		end
		return nil
	end

	for _, child in ipairs(padding:GetChildren()) do
		if child:IsA("TextLabel") and not child:IsA("UIAspectRatioConstraint") then
			return child.Name
		end
	end
	return nil
end

function View:_registerButton(item: Instance, columnIndex: number, category: string, name: string)
	local button = item:FindFirstChildWhichIsA("GuiButton") or (item:IsA("GuiButton") and item)
	if not button then
		-- The original wrapped the clickable area in a child; if the template
		-- has none, make the item itself clickable rather than dropping the row.
		button = Instance.new("TextButton")
		button.Name = "attachmentButton"
		button.Size = UDim2.fromScale(1, 1)
		button.BackgroundTransparency = 1
		button.Text = ""
		button.Parent = item
	end

	local frame = button.Parent

	self.buttons[button] = {
		category = category,
		name     = name,
		frame    = (frame and frame ~= item) and frame or item,
		originalSize     = nil,
		originalPosition = nil,
	}

	table.insert(self.columnButtons[columnIndex], button)

	button.Activated:Connect(function()
		if self.selection[category] == name then
			self:SetEntry(category, nil)
		else
			self:SetEntry(category, name)
		end
		if self.host and self.host.onItemToggled then
			self.host.onItemToggled(category, name, self.selection[category] == name)
		end
	end)

	button.MouseEnter:Connect(function()
		self:_playHover(button)
	end)
end

--[[
	Populate one column.

	Only attachments the weapon can *physically* take are shown: the weapon has
	to have an `Attachment` named after them under the category's mount part.
	Everything else is hidden rather than shown-and-failing, which is what the
	original did and it is the right behaviour.
]]
function View:_setupColumn(parts, columnIndex: number, category: string, weaponModel: Instance?, weaponName: string?)
	local heading = parts.attachments and parts.attachments:FindFirstChild("column" .. columnIndex)
	local items = heading and heading:FindFirstChild("items")
	if not items then
		return
	end

	items.Active = false
	items.ScrollingEnabled = true
	items.ClipsDescendants = false

	if heading then
		local title = heading:FindFirstChild("title")
		if title then
			title.Text = category
		end
	end

	self.columnButtons[columnIndex] = {}

	local available = self.system.ListAvailableFor(weaponModel, category, weaponName)
	local availableSet = {}
	for _, name in ipairs(available) do
		availableSet[name] = true
	end

	for _, item in ipairs(items:GetChildren()) do
		if item:IsA("Frame") or item:IsA("GuiButton") then
			local name = readItemName(item)
			if name and name ~= "" and availableSet[name] then
				item.Visible = true
				self:_registerButton(item, columnIndex, category, name)
			else
				item.Visible = false
			end
		end
	end
end

function View:Build(weapon: Instance?, weaponModel: Instance?, weaponName: string?)
	local parts = self:_discover()
	if not parts then
		return false
	end
	self.parts = parts

	self:ClearButtons()

	self.weapon     = weapon
	self.weaponName = weaponName or (weapon and weapon.Name)

	if parts.gunNameLabel and self.weaponName then
		parts.gunNameLabel.Text = self.weaponName
	end

	if not parts.attachments then
		return false
	end

	local columns = {}
	for _, child in ipairs(parts.attachments:GetChildren()) do
		if child:IsA("Frame") and child.Name == "column" then
			table.insert(columns, child)
		end
	end

	local categories = Config.GetCategoryList()
	for index, column in ipairs(columns) do
		local category = categories[index]
		if category then
			self:_setupColumn(parts, index, category, weaponModel, self.weaponName)
		end
	end

	-- Hydrate from the weapon's saved loadout.
	local saved = self.system.GetSaved(weapon)
	for category, name in pairs(saved) do
		self.selection[category] = name
	end
	self:_syncVisuals()

	-- Build the 3D preview.
	if parts.viewport then
		local source = self.host and self.host.getWeaponModel
			and self.host.getWeaponModel(self.weaponName)
		self.preview = Preview3D.new({ viewport = parts.viewport, system = self.system })
		if source and self.preview:Build(source, self.weaponName) then
			self.preview:ApplySelection(self.selection)
		else
			self.preview = nil
		end
	end

	return true
end

function View:ClearButtons()
	for button, data in pairs(self.buttons) do
		if data.tween then
			pcall(function() data.tween:Cancel() end)
		end
		pcall(function()
			if data.frame then
				data.frame.BackgroundColor3      = IDLE_COLOR
				data.frame.BackgroundTransparency = 0.3
				data.frame.AnchorPoint = Vector2.new(0, 0)
				if data.originalSize then data.frame.Size = data.originalSize end
				if data.originalPosition then data.frame.Position = data.originalPosition end
			end
		end)
	end
	table.clear(self.buttons)
	table.clear(self.selected)
	table.clear(self.columnButtons)
end

-- ─── Confirm / close wiring ─────────────────────────────────────────────────

function View:_connectGui()
	local gui = self.gui
	if not gui then
		return
	end

	local parts = self._parts or self:_discover()
	if not parts then
		return
	end
	self.parts = parts

	if parts.confirmButton then
		parts.confirmButton.Activated:Connect(function()
			if self.onConfirm then
				self.onConfirm(self.selection)
			end
		end)
	end

	if parts.closeButton then
		parts.closeButton.Activated:Connect(function()
			if self.host and self.host.onCloseRequested then
				self.host.onCloseRequested()
			end
		end)
	end

	self.enabledConnection = gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		if gui.Enabled then
			self:_onEnabled()
		else
			self:_onDisabled()
		end
	end)
end

--[[
	While the menu is open some hosts fight the mouse cursor and open other
	menus. This is the same PreRender override the original used, but it is
	skipped entirely when the host has not asked for it.
]]
function View:_onEnabled()
	if self.host and self.host.keepMouseDefault then
		self.previousMouseBehavior    = UserInputService.MouseBehavior
		self.previousMouseIconEnabled = UserInputService.MouseIconEnabled
		pcall(function()
			UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
			UserInputService.MouseIconEnabled = true
		end)

		if self.preRenderConnection then
			pcall(function() self.preRenderConnection:Disconnect() end)
		end
		self.preRenderConnection = RunService.PreRender:Connect(function()
			pcall(function()
				UserInputService.MouseBehavior    = Enum.MouseBehavior.Default
				UserInputService.MouseIconEnabled = true
			end)
		end)
	end

	if self.host and self.host.onOpened then
		self.host.onOpened()
	end
end

function View:_onDisabled()
	if self.preRenderConnection then
		pcall(function() self.preRenderConnection:Disconnect() end)
		self.preRenderConnection = nil
	end
	if self.host and self.host.onClosed then
		self.host.onClosed()
	end
end

function View:Clear()
	self:ClearButtons()
	if self.preview then
		self.preview:Clear()
		self.preview = nil
	end
	self.weapon = nil
	table.clear(self.selection)
end

function View:RefreshSelection()
	if self.preview then
		self.preview:ApplySelection(self.selection)
	end
end

return View
