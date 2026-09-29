--[[
	UIController.luau
	-----------------
	Module 4 of 6 - the plugin UI.

	A single DockWidgetPluginGui built entirely at runtime (no .rbxmodel asset, so
	the whole plugin is one folder of source files). Styling is a dark "terminal"
	theme: near-black panels, neon green accents, monospace font, and a
	block-letter ASCII banner that is exactly 31 cells wide so it never wraps.

	Layout
		┌─ header: ASCII banner + subtitle + rig/container status
		├─ target rig: picker button, container class, alias, rescan
		├─ stat chips: total / dirty / clean / selected
		├─ filter row: search box, select all/none/invert, dirty-only
		├─ animation list: scrolling rows with checkbox, badge, metadata
		├─ progress: bar + counters + status line
		├─ log: scrolling monospace log
		├─ footer: Upload Selected, dry run, options
		└─ options: cache backend, hash mode, creator, skip-clean, auto-reupload

	All list mutation happens on the main thread through small helper methods;
	the heavy work (scanning, hashing, uploading) runs in coroutines so the UI
	never blocks.
]]

local TweenService = game:GetService("TweenService")
local Selection = game:GetService("Selection")

local Util = require(script.Parent.Util)

local UIController = {}
UIController.__index = UIController

--------------------------------------------------------------------------------
-- Theme
--------------------------------------------------------------------------------

local PALETTE = {
	Background = Color3.fromRGB(9, 13, 11),
	Panel = Color3.fromRGB(15, 22, 18),
	PanelAlt = Color3.fromRGB(21, 31, 26),
	Row = Color3.fromRGB(18, 27, 22),
	RowHover = Color3.fromRGB(26, 40, 32),
	Stroke = Color3.fromRGB(0, 95, 62),
	Accent = Color3.fromRGB(0, 255, 150),
	AccentDim = Color3.fromRGB(0, 130, 82),
	Cyan = Color3.fromRGB(90, 215, 255),
	Text = Color3.fromRGB(196, 238, 214),
	TextDim = Color3.fromRGB(112, 152, 130),
	Warn = Color3.fromRGB(255, 198, 74),
	Error = Color3.fromRGB(255, 86, 86),
	Clean = Color3.fromRGB(0, 255, 150),
	Dirty = Color3.fromRGB(255, 168, 46),
	New = Color3.fromRGB(120, 200, 255),
	Track = Color3.fromRGB(28, 40, 34),
}

-- Verified 32-cell-wide block banner (all six rows exactly 32 characters).
local BANNER = table.concat({
	"█████╗  ██╗  ██  ██╗ ███╗   ███╗",
	"██╔══╝  ███╗ ██  ██║ ████╗ ████║",
	"█████╗  ██╔██╗██ ██║ ██╔████╔██║",
	"██╔══╝  ██║╚██╗█ ██║ ██║╚██╔╝██║",
	"██║  ██ ██║ ╚══  ██║ ██║ ╚████║ ",
	"╚═╝  ╚═ ╚═╝      ╚═╝ ╚═╝  ╚═══╝ ",
}, "\n")

local SUBTITLE = "S A V E S   //   B U L K   U P L O A D E R"
local TAGLINE = "AssetService:CreateAssetAsync  ·  zero ClipEditor"

-- Fixed heights, used both to size the sections and to size the widget.
local SECTION_HEIGHT = {
	Header = 132,
	Rig = 74,
	Stats = 30,
	Filters = 26,
	List = 240,
	Progress = 46,
	Log = 108,
	Footer = 32,
}

local STATE_COLORS = {
	New = PALETTE.New,
	Changed = PALETTE.Dirty,
	Clean = PALETTE.Clean,
	Incomplete = PALETTE.Warn,
}

--[[
	Safe enum lookup. The UI must never hard-fail on an older client, so any
	missing enum degrades to nil (Roblox then uses the property default).
]]
local function enumOr(family: string, name: string): any
	local ok, value = pcall(function()
		return (Enum :: any)[family][name]
	end)
	if ok and value ~= nil then
		return value
	end
	return nil
end

local MONO_FONT = enumOr("Font", "Code") or Enum.Font.Legacy

local HORIZONTAL = enumOr("FillDirection", "Horizontal")
local VERTICAL = enumOr("FillDirection", "Vertical")

--------------------------------------------------------------------------------
-- Instance helpers
--------------------------------------------------------------------------------

--[[
	Tiny declarative instance builder.

	el("TextLabel", {
		Text = "hello",
		TextColor3 = PALETTE.Text,
		Parent = someFrame,
		childA, childB,   -- numeric keys are parented after the props
	})
]]
local function el(className: string, props: { [any]: any }?): Instance
	local inst = Instance.new(className)
	if props then
		for key, value in pairs(props) do
			if type(key) ~= "number" and key ~= "Parent" then
				(inst :: any)[key] = value
			end
		end
		for key, value in pairs(props) do
			if type(key) == "number" and typeof(value) == "Instance" then
				value.Parent = inst
			end
		end
		if props.Parent ~= nil then
			inst.Parent = props.Parent
		end
	end
	return inst
end

local function corner(radius: number?): Instance
	return el("UICorner", { CornerRadius = UDim.new(0, radius or 4) })
end

local function stroke(color: Color3, thickness: number?): Instance
	return el("UIStroke", { Color = color, Thickness = thickness or 1 })
end

local function padding(all: number, top: number?): Instance
	return el("UIPadding", {
		PaddingLeft = UDim.new(0, all),
		PaddingRight = UDim.new(0, all),
		PaddingTop = UDim.new(0, top or all),
		PaddingBottom = UDim.new(0, top or all),
	})
end

local function list(paddingPx: number, direction: any?): Instance
	return el("UIListLayout", {
		Padding = UDim.new(0, paddingPx),
		FillDirection = direction or VERTICAL,
		SortOrder = enumOr("SortOrder", "LayoutOrder"),
	})
end

--[[
	Converts a Color3 into the #RRGGBB form Roblox RichText understands.
]]
local function hexColor(color: Color3): string
	return string.format("#%02X%02X%02X", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
end

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function UIController.new(pluginInstance: Plugin, deps: { [string]: any }): UIController
	local self = setmetatable({}, UIController)

	self._plugin = pluginInstance
	self._deps = deps or {}

	self._widget = nil :: DockWidgetPluginGui?
	self._refs = {} :: { [string]: any }
	self._rows = {} :: { { frame: Instance, record: any } }
	self._records = {} :: { any }
	self._filter = ""
	self._dirtyOnly = false
	self._maxRows = 300
	self._uploading = false
	self._rig = nil :: Instance?
	self._scan = nil :: any?
	self._destroyed = false

	self:_build()
	return self
end

function UIController:GetWidget(): DockWidgetPluginGui?
	return self._widget
end

--------------------------------------------------------------------------------
-- Widget construction
--------------------------------------------------------------------------------

function UIController:_build()
	local widget = self:_createWidget()
	self._widget = widget

	el("Frame", {
		Name = "Root",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = PALETTE.Background,
		BorderSizePixel = 0,
		Parent = widget,
		corner(2),
	})

	-- The shell scrolls, so no section can ever be pushed off-screen and lost.
	local shell = el("ScrollingFrame", {
		Name = "Shell",
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = PALETTE.AccentDim,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = enumOr("AutomaticSize", "Y"),
		Parent = widget:FindFirstChild("Root"),
		padding(10, 8),
		list(8),
	})

	self:_buildHeader(shell)
	self:_buildRigPanel(shell)
	self:_buildStats(shell)
	self:_buildFilters(shell)
	self:_buildList(shell)
	self:_buildProgress(shell)
	self:_buildLog(shell)
	self:_buildFooter(shell)
	self:_buildOptions(shell)

	widget.Enabled = false
end

function UIController:_createWidget(): DockWidgetPluginGui
	local info = DockWidgetPluginGuiInfo.new(
		enumOr("InitialDockState", "Float") or Enum.InitialDockState.Float,
		true, -- initially enabled
		false, -- do not override the previous enabled state
		460, -- default width
		700, -- default height
		360, -- min width
		520 -- min height
	)

	local id = "AnimSavesBulkUploader"

	-- Prefer the modern yielding API; fall back to the deprecated sync one.
	local ok, widget = pcall(function()
		return (self._plugin :: Plugin):CreateDockWidgetPluginGuiAsync(id, info)
	end)
	if ok and widget then
		return widget :: DockWidgetPluginGui
	end

	widget = (self._plugin :: Plugin):CreateDockWidgetPluginGui(id, info)
	return widget :: DockWidgetPluginGui
end

--------------------------------------------------------------------------------
-- Header
--------------------------------------------------------------------------------

function UIController:_buildHeader(parent: Instance)
	local header = el("Frame", {
		Name = "Header",
		Size = UDim2.new(1, 0, 0, SECTION_HEIGHT.Header),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		LayoutOrder = 1,
		Parent = parent,
		corner(6),
		stroke(PALETTE.Stroke, 1),
	})

	el("TextLabel", {
		Name = "Banner",
		Size = UDim2.new(1, -16, 0, 78),
		Position = UDim2.new(0, 8, 0, 4),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = BANNER,
		TextColor3 = PALETTE.Accent,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Parent = header,
	})

	el("TextLabel", {
		Name = "Subtitle",
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.new(0, 8, 0, 84),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = SUBTITLE,
		TextColor3 = PALETTE.Cyan,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	el("TextLabel", {
		Name = "Tagline",
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 8, 0, 100),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = TAGLINE,
		TextColor3 = PALETTE.TextDim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	el("TextLabel", {
		Name = "Status",
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 8, 0, 114),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "> awaiting target rig...",
		TextColor3 = PALETTE.AccentDim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = header,
	})

	self._refs.statusLabel = header:FindFirstChild("Status") :: TextLabel
end

--------------------------------------------------------------------------------
-- Target rig panel
--------------------------------------------------------------------------------

function UIController:_buildRigPanel(parent: Instance)
	local panel = el("Frame", {
		Name = "RigPanel",
		Size = UDim2.new(1, 0, 0, SECTION_HEIGHT.Rig),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		LayoutOrder = 2,
		Parent = parent,
		corner(6),
		stroke(PALETTE.Stroke, 1),
	})

	el("TextLabel", {
		Name = "SectionLabel",
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 8, 0, 6),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "// TARGET RIG",
		TextColor3 = PALETTE.TextDim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = panel,
	})

	el("TextButton", {
		Name = "RigButton",
		Size = UDim2.new(1, -98, 0, 26),
		Position = UDim2.new(0, 8, 0, 22),
		BackgroundColor3 = PALETTE.PanelAlt,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = MONO_FONT,
		Text = "  no rig selected  -  click to use Studio Selection",
		TextColor3 = PALETTE.Text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = enumOr("TextTruncate", "AtEnd"),
		Parent = panel,
		corner(4),
		stroke(PALETTE.Stroke, 1),
	})

	el("TextButton", {
		Name = "RescanButton",
		Size = UDim2.new(0, 82, 0, 26),
		Position = UDim2.new(1, -90, 0, 22),
		BackgroundColor3 = PALETTE.PanelAlt,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = MONO_FONT,
		Text = "RESCAN",
		TextColor3 = PALETTE.Accent,
		TextSize = 11,
		Parent = panel,
		corner(4),
		stroke(PALETTE.AccentDim, 1),
	})

	el("TextLabel", {
		Name = "RigInfo",
		Size = UDim2.new(1, -16, 0, 16),
		Position = UDim2.new(0, 8, 0, 52),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "container: --",
		TextColor3 = PALETTE.TextDim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = enumOr("TextTruncate", "AtEnd"),
		Parent = panel,
	})

	;(panel:FindFirstChild("RigButton") :: TextButton).MouseButton1Click:Connect(function()
		self:_pickRigFromSelection()
	end)
	;(panel:FindFirstChild("RescanButton") :: TextButton).MouseButton1Click:Connect(function()
		self:Refresh()
	end)

	self._refs.rigButton = panel:FindFirstChild("RigButton") :: TextButton
	self._refs.rigInfo = panel:FindFirstChild("RigInfo") :: TextLabel
end

--------------------------------------------------------------------------------
-- Stat chips
--------------------------------------------------------------------------------

function UIController:_buildStats(parent: Instance)
	local row = el("Frame", {
		Name = "Stats",
		Size = UDim2.new(1, 0, 0, SECTION_HEIGHT.Stats),
		BackgroundTransparency = 1,
		LayoutOrder = 3,
		Parent = parent,
		list(6, HORIZONTAL),
	})

	local definitions = {
		{ key = "total", label = "TOTAL", color = PALETTE.Text },
		{ key = "dirty", label = "DIRTY", color = PALETTE.Dirty },
		{ key = "clean", label = "CLEAN", color = PALETTE.Clean },
		{ key = "selected", label = "SELECTED", color = PALETTE.Cyan },
	}

	self._refs.chips = {}

	for index, definition in ipairs(definitions) do
		local chip = el("Frame", {
			Name = definition.key,
			Size = UDim2.new(0.25, -5, 1, 0),
			BackgroundColor3 = PALETTE.Panel,
			BorderSizePixel = 0,
			LayoutOrder = index,
			Parent = row,
			corner(4),
			stroke(PALETTE.Stroke, 1),
			el("TextLabel", {
				Name = "Value",
				Size = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Font = MONO_FONT,
				Text = "0",
				TextColor3 = definition.color,
				TextSize = 15,
			}),
		})
		self._refs.chips[definition.key] = (chip :: Frame):FindFirstChild("Value") :: TextLabel
	end
end

--------------------------------------------------------------------------------
-- Filter row
--------------------------------------------------------------------------------

function UIController:_buildFilters(parent: Instance)
	local row = el("Frame", {
		Name = "Filters",
		Size = UDim2.new(1, 0, 0, SECTION_HEIGHT.Filters),
		BackgroundTransparency = 1,
		LayoutOrder = 4,
		Parent = parent,
		list(6, HORIZONTAL),
	})

	local search = el("TextBox", {
		Name = "Search",
		Size = UDim2.new(0.4, -5, 1, 0),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		Font = MONO_FONT,
		PlaceholderText = "filter by name...",
		PlaceholderColor3 = PALETTE.TextDim,
		Text = "",
		TextColor3 = PALETTE.Text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Parent = row,
		corner(4),
		stroke(PALETTE.Stroke, 1),
	})
	;(search :: TextBox):GetPropertyChangedSignal("Text"):Connect(function()
		self._filter = (search :: TextBox).Text
		self:_renderRows()
	end)

	local buttons = {
		{ text = "ALL", width = 0.13, action = function()
			for _, record in ipairs(self._records) do
				record.selected = true
			end
			self:_renderRows()
			self:_updateStats()
		end },
		{ text = "NONE", width = 0.13, action = function()
			for _, record in ipairs(self._records) do
				record.selected = false
			end
			self:_renderRows()
			self:_updateStats()
		end },
		{ text = "INV", width = 0.13, action = function()
			for _, record in ipairs(self._records) do
				record.selected = not record.selected
			end
			self:_renderRows()
			self:_updateStats()
		end },
		{ text = "DIRTY", width = 0.21, action = function()
			self._dirtyOnly = not self._dirtyOnly
			self:_renderRows()
		end },
	}

	for index, definition in ipairs(buttons) do
		local button = el("TextButton", {
			Name = definition.text,
			Size = UDim2.new(definition.width, -5, 1, 0),
			BackgroundColor3 = PALETTE.PanelAlt,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = MONO_FONT,
			Text = definition.text,
			TextColor3 = PALETTE.Accent,
			TextSize = 11,
			LayoutOrder = index + 1,
			Parent = row,
			corner(4),
			stroke(PALETTE.AccentDim, 1),
		})
		;(button :: TextButton).MouseButton1Click:Connect(definition.action)
	end
end

--------------------------------------------------------------------------------
-- Animation list
--------------------------------------------------------------------------------

function UIController:_buildList(parent: Instance)
	local frame = el("Frame", {
		Name = "ListSection",
		Size = UDim2.new(1, 0, 0, SECTION_HEIGHT.List),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		LayoutOrder = 5,
		Parent = parent,
		corner(6),
		stroke(PALETTE.Stroke, 1),
	})

	el("TextLabel", {
		Name = "ListLabel",
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 8, 0, 6),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "// DETECTED KEYFRAMESEQUENCES",
		TextColor3 = PALETTE.TextDim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	local scroller = el("ScrollingFrame", {
		Name = "AnimList",
		Size = UDim2.new(1, -12, 1, -28),
		Position = UDim2.new(0, 6, 0, 22),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = PALETTE.AccentDim,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = enumOr("AutomaticSize", "Y"),
		Parent = frame,
		list(2),
	})

	el("TextLabel", {
		Name = "EmptyLabel",
		Size = UDim2.new(1, 0, 0, 40),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "  no animations detected - select a rig and press RESCAN",
		TextColor3 = PALETTE.TextDim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		Parent = scroller,
	})

	self._refs.listScroller = scroller :: ScrollingFrame
	self._refs.emptyLabel = (scroller :: ScrollingFrame):FindFirstChild("EmptyLabel") :: TextLabel
end

function UIController:_clearRows()
	for _, row in ipairs(self._rows) do
		row.frame:Destroy()
	end
	self._rows = {}
end

--[[
	Rebuilds every visible list row. Rows are destroyed and recreated rather than
	recycled: the lists are small and this keeps the code honest. Beyond
	`_maxRows` rows a "+N more" placeholder is shown instead.
]]
function UIController:_renderRows()
	local scroller = self._refs.listScroller :: ScrollingFrame?
	if not scroller then
		return
	end

	self:_clearRows()

	local visible = {}
	for _, record in ipairs(self._records) do
		if self:_matchesFilter(record) then
			table.insert(visible, record)
		end
	end

	local emptyLabel = self._refs.emptyLabel :: TextLabel?
	if emptyLabel then
		if #visible == 0 then
			emptyLabel.Visible = true
			emptyLabel.Text = if #self._records == 0
				then "  no animations detected - select a rig and press RESCAN"
				else "  no animations match the current filter"
		else
			emptyLabel.Visible = false
		end
	end

	local shown = math.min(#visible, self._maxRows)
	for index = 1, shown do
		table.insert(self._rows, { frame = self:_buildRow(visible[index], index, scroller), record = visible[index] })
	end

	if #visible > self._maxRows then
		el("TextLabel", {
			Name = "Overflow",
			Size = UDim2.new(1, 0, 0, 22),
			BackgroundTransparency = 1,
			Font = MONO_FONT,
			Text = string.format("  ... and %d more (use the filter box to narrow it down)", #visible - self._maxRows),
			TextColor3 = PALETTE.Warn,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = self._maxRows + 1,
			Parent = scroller,
		})
	end
end

function UIController:_matchesFilter(record: any): boolean
	if self._dirtyOnly and not record.dirty then
		return false
	end
	if self._filter ~= "" and not record.name:lower():find(self._filter:lower(), 1, true) then
		return false
	end
	return true
end

function UIController:_buildRow(record: any, order: number, parent: Instance): Instance
	local stateColor = STATE_COLORS[record.state] or PALETTE.TextDim
	local subPath = record.subPath or ""
	local displayName = if subPath ~= "" then subPath else record.name

	local row = el("TextButton", {
		Name = "Row_" .. record.name,
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundColor3 = if record.selected then PALETTE.RowHover else PALETTE.Row,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = MONO_FONT,
		Text = "",
		LayoutOrder = order,
		Parent = parent,
		corner(3),
	})

	el("TextLabel", {
		Name = "Check",
		Size = UDim2.new(0, 20, 1, 0),
		Position = UDim2.new(0, 4, 0, 0),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = if record.selected then "[x]" else "[ ]",
		TextColor3 = if record.selected then PALETTE.Accent else PALETTE.TextDim,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	el("TextLabel", {
		Name = "Name",
		Size = UDim2.new(0.5, -26, 1, 0),
		Position = UDim2.new(0, 24, 0, 0),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = displayName,
		TextColor3 = PALETTE.Text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = enumOr("TextTruncate", "AtEnd"),
		Parent = row,
	})

	el("TextLabel", {
		Name = "State",
		Size = UDim2.new(0, 74, 1, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = record.state:upper(),
		TextColor3 = stateColor,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = row,
	})

	el("TextLabel", {
		Name = "Meta",
		Size = UDim2.new(0.5, -110, 1, 0),
		Position = UDim2.new(1, -104, 0, 0),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = string.format("%s %dkf %dp", Util.formatDuration(record.length), record.keyframes, record.poses),
		TextColor3 = PALETTE.TextDim,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = row,
	})

	local button = row :: TextButton
	button.MouseButton1Click:Connect(function()
		record.selected = not record.selected
		self:_renderRows()
		self:_updateStats()
	end)

	button.MouseButton2Click:Connect(function()
		if record.cachedAssetId and record.cachedAssetId > 0 then
			self:Log("info", string.format("%s -> cached asset %d", record.name, record.cachedAssetId))
		else
			self:Log("info", string.format("%s -> no cached asset id", record.name))
		end
	end)

	return row
end

--------------------------------------------------------------------------------
-- Progress
--------------------------------------------------------------------------------

function UIController:_buildProgress(parent: Instance)
	local frame = el("Frame", {
		Name = "ProgressSection",
		Size = UDim2.new(1, 0, 0, SECTION_HEIGHT.Progress),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		LayoutOrder = 6,
		Parent = parent,
		corner(6),
		stroke(PALETTE.Stroke, 1),
	})

	local track = el("Frame", {
		Name = "Track",
		Size = UDim2.new(1, -16, 0, 10),
		Position = UDim2.new(0, 8, 0, 8),
		BackgroundColor3 = PALETTE.Track,
		BorderSizePixel = 0,
		Parent = frame,
		corner(5),
	})

	el("Frame", {
		Name = "Fill",
		Size = UDim2.new(0, 0, 1, 0),
		BackgroundColor3 = PALETTE.Accent,
		BorderSizePixel = 0,
		Parent = track,
		corner(5),
	})

	el("TextLabel", {
		Name = "Counter",
		Size = UDim2.new(0.5, -8, 0, 14),
		Position = UDim2.new(0, 8, 0, 22),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "0 / 0 uploaded",
		TextColor3 = PALETTE.Text,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	el("TextLabel", {
		Name = "Phase",
		Size = UDim2.new(0.5, -8, 0, 14),
		Position = UDim2.new(0.5, 0, 0, 22),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "idle",
		TextColor3 = PALETTE.TextDim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = frame,
	})

	self._refs.progressFill = (track :: Frame):FindFirstChild("Fill") :: Frame
	self._refs.progressCounter = (frame :: Frame):FindFirstChild("Counter") :: TextLabel
	self._refs.progressPhase = (frame :: Frame):FindFirstChild("Phase") :: TextLabel
end

--------------------------------------------------------------------------------
-- Log
--------------------------------------------------------------------------------

function UIController:_buildLog(parent: Instance)
	local frame = el("Frame", {
		Name = "LogSection",
		Size = UDim2.new(1, 0, 0, SECTION_HEIGHT.Log),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		LayoutOrder = 7,
		Parent = parent,
		corner(6),
		stroke(PALETTE.Stroke, 1),
	})

	el("TextLabel", {
		Name = "LogLabel",
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 8, 0, 5),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "// LOG",
		TextColor3 = PALETTE.TextDim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	local scroller = el("ScrollingFrame", {
		Name = "Log",
		Size = UDim2.new(1, -12, 1, -22),
		Position = UDim2.new(0, 6, 0, 19),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = PALETTE.AccentDim,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		AutomaticCanvasSize = enumOr("AutomaticSize", "Y"),
		Parent = frame,
	})

	el("TextLabel", {
		Name = "LogText",
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = enumOr("AutomaticSize", "Y"),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "",
		TextColor3 = PALETTE.TextDim,
		TextSize = 10,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		RichText = true,
		Parent = scroller,
	})

	self._refs.logScroller = scroller :: ScrollingFrame
	self._refs.logText = (scroller :: ScrollingFrame):FindFirstChild("LogText") :: TextLabel
end

--------------------------------------------------------------------------------
-- Footer
--------------------------------------------------------------------------------

function UIController:_buildFooter(parent: Instance)
	local row = el("Frame", {
		Name = "Footer",
		Size = UDim2.new(1, 0, 0, SECTION_HEIGHT.Footer),
		BackgroundTransparency = 1,
		LayoutOrder = 8,
		Parent = parent,
		list(6, HORIZONTAL),
	})

	local upload = el("TextButton", {
		Name = "UploadButton",
		Size = UDim2.new(0.56, -5, 1, 0),
		BackgroundColor3 = PALETTE.AccentDim,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = MONO_FONT,
		Text = "UPLOAD SELECTED",
		TextColor3 = Color3.new(0, 0.06, 0.02),
		TextSize = 13,
		Parent = row,
		corner(4),
	})
	;(upload :: TextButton).MouseButton1Click:Connect(function()
		self:_onUploadClicked(false)
	end)

	local dry = el("TextButton", {
		Name = "DryRunButton",
		Size = UDim2.new(0.22, -5, 1, 0),
		BackgroundColor3 = PALETTE.PanelAlt,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = MONO_FONT,
		Text = "DRY RUN",
		TextColor3 = PALETTE.Cyan,
		TextSize = 11,
		Parent = row,
		corner(4),
		stroke(PALETTE.Stroke, 1),
	})
	;(dry :: TextButton).MouseButton1Click:Connect(function()
		self:_onUploadClicked(true)
	end)

	local options = el("TextButton", {
		Name = "OptionsButton",
		Size = UDim2.new(0.22, -5, 1, 0),
		BackgroundColor3 = PALETTE.PanelAlt,
		BorderSizePixel = 0,
		AutoButtonColor = true,
		Font = MONO_FONT,
		Text = "OPTIONS",
		TextColor3 = PALETTE.Accent,
		TextSize = 11,
		Parent = row,
		corner(4),
		stroke(PALETTE.AccentDim, 1),
	})
	;(options :: TextButton).MouseButton1Click:Connect(function()
		self:_toggleOptions()
	end)

	self._refs.uploadButton = upload :: TextButton
	self._refs.dryRunButton = dry :: TextButton
	self._refs.optionsButton = options :: TextButton
end

--------------------------------------------------------------------------------
-- Options panel
--------------------------------------------------------------------------------

function UIController:_buildOptions(parent: Instance)
	local frame = el("Frame", {
		Name = "OptionsPanel",
		Size = UDim2.new(1, 0, 0, 176),
		BackgroundColor3 = PALETTE.Panel,
		BorderSizePixel = 0,
		LayoutOrder = 9,
		Visible = false,
		Parent = parent,
		corner(6),
		stroke(PALETTE.Stroke, 1),
	})

	el("TextLabel", {
		Name = "OptionsLabel",
		Size = UDim2.new(1, -16, 0, 14),
		Position = UDim2.new(0, 8, 0, 5),
		BackgroundTransparency = 1,
		Font = MONO_FONT,
		Text = "// OPTIONS",
		TextColor3 = PALETTE.TextDim,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = frame,
	})

	local cursorY = 22

	local function setOption(key: string, value: any)
		self._deps.options = self._deps.options or {}
		self._deps.options[key] = value
	end

	-- A two-state toggle row.
	local function addToggle(label: string, key: string)
		local button = el("TextButton", {
			Name = key,
			Size = UDim2.new(1, -16, 0, 20),
			Position = UDim2.new(0, 8, 0, cursorY),
			BackgroundColor3 = PALETTE.PanelAlt,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = MONO_FONT,
			Text = "",
			Parent = frame,
			corner(3),
			el("TextLabel", {
				Name = "Label",
				Size = UDim2.new(0.62, 0, 1, 0),
				Position = UDim2.new(0, 6, 0, 0),
				BackgroundTransparency = 1,
				Font = MONO_FONT,
				Text = label,
				TextColor3 = PALETTE.Text,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			el("TextLabel", {
				Name = "Value",
				Size = UDim2.new(0.36, -6, 1, 0),
				Position = UDim2.new(0.64, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = MONO_FONT,
				Text = "OFF",
				TextColor3 = PALETTE.TextDim,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}) :: TextButton

		local value = (button:FindFirstChild("Value") :: TextLabel)
		local state = false
		button.MouseButton1Click:Connect(function()
			state = not state
			value.Text = if state then "ON" else "OFF"
			value.TextColor3 = if state then PALETTE.Accent else PALETTE.TextDim
			setOption(key, state)
		end)

		cursorY += 22
	end

	-- A cycling row that walks through a list of values.
	local function addCycler(label: string, key: string, values: { string })
		local button = el("TextButton", {
			Name = key,
			Size = UDim2.new(1, -16, 0, 20),
			Position = UDim2.new(0, 8, 0, cursorY),
			BackgroundColor3 = PALETTE.PanelAlt,
			BorderSizePixel = 0,
			AutoButtonColor = true,
			Font = MONO_FONT,
			Text = "",
			Parent = frame,
			corner(3),
			el("TextLabel", {
				Name = "Label",
				Size = UDim2.new(0.42, 0, 1, 0),
				Position = UDim2.new(0, 6, 0, 0),
				BackgroundTransparency = 1,
				Font = MONO_FONT,
				Text = label,
				TextColor3 = PALETTE.Text,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),
			el("TextLabel", {
				Name = "Value",
				Size = UDim2.new(0.56, -6, 1, 0),
				Position = UDim2.new(0.44, 0, 0, 0),
				BackgroundTransparency = 1,
				Font = MONO_FONT,
				Text = values[1],
				TextColor3 = PALETTE.Cyan,
				TextSize = 11,
				TextXAlignment = Enum.TextXAlignment.Right,
			}),
		}) :: TextButton

		local value = (button:FindFirstChild("Value") :: TextLabel)
		local index = 1
		button.MouseButton1Click:Connect(function()
			index = index % #values + 1
			value.Text = values[index]
			setOption(key, values[index])
		end)

		cursorY += 22
	end

	-- A text field row.
	local function addField(label: string, key: string, placeholder: string)
		el("TextLabel", {
			Name = key .. "_Label",
			Size = UDim2.new(1, -16, 0, 14),
			Position = UDim2.new(0, 8, 0, cursorY),
			BackgroundTransparency = 1,
			Font = MONO_FONT,
			Text = label,
			TextColor3 = PALETTE.Text,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = frame,
		})
		local box = el("TextBox", {
			Name = key .. "_Box",
			Size = UDim2.new(1, -16, 0, 20),
			Position = UDim2.new(0, 8, 0, cursorY + 15),
			BackgroundColor3 = PALETTE.PanelAlt,
			BorderSizePixel = 0,
			Font = MONO_FONT,
			PlaceholderText = placeholder,
			PlaceholderColor3 = PALETTE.TextDim,
			Text = "",
			TextColor3 = PALETTE.Text,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Left,
			ClearTextOnFocus = false,
			Parent = frame,
			corner(3),
		}) :: TextBox

		box.FocusLost:Connect(function()
			setOption(key, box.Text)
		end)

		cursorY += 38
	end

	addToggle("skip unchanged (clean)", "skipClean")
	addToggle("auto re-upload dirty", "autoReupload")
	addCycler("cache backend", "backend", { "Settings", "StringValue" })
	addCycler("hash mode", "hashMode", { "Deep", "Fast" })
	addCycler("creator", "creatorType", { "User", "Group" })
	addField("group id (only when creator = Group)", "groupId", "e.g. 1234567")

	self._refs.optionsPanel = frame
end

function UIController:_toggleOptions()
	local panel = self._refs.optionsPanel :: Frame?
	if panel then
		panel.Visible = not panel.Visible
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--[[
	Shows or hides the widget.
]]
function UIController:Toggle()
	local widget = self._widget
	if not widget then
		return
	end
	widget.Enabled = not widget.Enabled
	if widget.Enabled then
		self:Refresh()
	end
end

function UIController:SetEnabled(enabled: boolean)
	local widget = self._widget
	if widget then
		widget.Enabled = enabled
	end
end

--[[
	Appends a line to the on-screen log.
]]
function UIController:Log(level: string, message: string)
	local label = self._refs.logText :: TextLabel?
	if not label then
		return
	end

	local color = PALETTE.TextDim
	if level == "error" then
		color = PALETTE.Error
	elseif level == "warn" then
		color = PALETTE.Warn
	elseif level == "ok" then
		color = PALETTE.Clean
	elseif level == "info" then
		color = PALETTE.Cyan
	end

	local line = string.format('<font color="%s">[%s] %s</font>', hexColor(color), os.date("%H:%M:%S"), message)
	label.Text = if label.Text == "" then line else label.Text .. "\n" .. line

	local scroller = self._refs.logScroller :: ScrollingFrame?
	if scroller then
		task.defer(function()
			pcall(function()
				scroller.CanvasPosition = Vector2.new(0, math.max(0, scroller.AbsoluteCanvasSize.Y))
			end)
		end)
	end
end

function UIController:SetStatus(text: string, color: Color3?)
	local label = self._refs.statusLabel :: TextLabel?
	if label then
		label.Text = "> " .. text
		if color then
			label.TextColor3 = color
		end
	end
end

function UIController:SetPhase(text: string)
	local label = self._refs.progressPhase :: TextLabel?
	if label then
		label.Text = text
	end
end

function UIController:SetProgress(done: number, total: number)
	local fill = self._refs.progressFill :: Frame?
	local counter = self._refs.progressCounter :: TextLabel?
	if fill then
		local ratio = if total > 0 then math.clamp(done / total, 0, 1) else 0
		TweenService:Create(fill, TweenInfo.new(0.12), { Size = UDim2.fromScale(ratio, 1) }):Play()
	end
	if counter then
		counter.Text = string.format("%d / %d uploaded", done, total)
	end
end

function UIController:_updateStats()
	local total = #self._records
	local dirty, clean, selected = 0, 0, 0
	for _, record in ipairs(self._records) do
		if record.dirty then
			dirty += 1
		else
			clean += 1
		end
		if record.selected then
			selected += 1
		end
	end

	local chips = self._refs.chips
	if chips then
		chips.total.Text = tostring(total)
		chips.dirty.Text = tostring(dirty)
		chips.clean.Text = tostring(clean)
		chips.selected.Text = tostring(selected)
	end

	local upload = self._refs.uploadButton :: TextButton?
	if upload then
		upload.Text = if selected > 0 then string.format("UPLOAD SELECTED (%d)", selected) else "UPLOAD SELECTED"
		upload.BackgroundColor3 = if selected > 0 then PALETTE.AccentDim else PALETTE.Track
	end
end

--------------------------------------------------------------------------------
-- Scanning
--------------------------------------------------------------------------------

function UIController:_pickRigFromSelection()
	local scanner = self._deps.scanner
	local rig = scanner and scanner:ResolveFromSelection()
	if not rig then
		self:SetStatus("selection has no AnimSaves container", PALETTE.Warn)
		self:Log("warn", "The current Studio Selection does not contain an AnimSaves container.")
		return
	end
	self:SetRig(rig)
end

--[[
	Points the plugin at a rig and re-scans.
]]
function UIController:SetRig(rig: Instance?)
	if not rig then
		return
	end
	self._rig = rig
	if self._deps.onRigChanged then
		self._deps.onRigChanged(rig)
	end
	self:Refresh()
end

--[[
	Runs scan + hash analysis in a coroutine so the UI thread never blocks.
]]
function UIController:Refresh()
	if self._destroyed then
		return
	end
	task.spawn(function()
		self:_refreshAsync()
	end)
end

function UIController:_refreshAsync()
	local scanner = self._deps.scanner
	local cache = self._deps.cache
	if not scanner then
		return
	end

	self:SetPhase("scanning")
	self:SetStatus("scanning rig...", PALETTE.Cyan)

	local scan = scanner:ScanRig(self._rig)
	self._scan = scan

	local rigButton = self._refs.rigButton :: TextButton?
	if rigButton then
		rigButton.Text = if scan.rig
			then string.format("  %s   [%s]", scan.rig.Name, scan.rig.ClassName)
			else "  no rig selected  -  click to use Studio Selection"
	end

	local rigInfo = self._refs.rigInfo :: TextLabel?
	if rigInfo then
		if scan.container then
			local alias = ""
			if scan.containerAlias then
				alias = string.format(" | value=%q%s", scan.containerAlias, if scan.aliasMatchesRig then " (=rig)" else " (!=rig)")
			end
			rigInfo.Text = string.format(
				"container: %s (%s) | %d seq%s%s",
				scan.container.Name,
				scan.containerClass or "?",
				#scan.sequences,
				alias,
				if scan.truncated then " | TRUNCATED" else ""
			)
		else
			rigInfo.Text = "container: --"
		end
	end

	if scan.error then
		self:SetStatus(scan.error, PALETTE.Warn)
		self:Log("warn", scan.error)
		self._records = {}
		self:_renderRows()
		self:_updateStats()
		self:SetPhase("idle")
		return
	end

	if cache then
		cache:SetRigInstance(scan.rig)
		local options = self._deps.options or {}
		if options.backend then
			cache._options.Backend = options.backend
		end
		if options.hashMode then
			cache._options.HashMode = options.hashMode
		end

		if cache:Load(scan.rig) then
			self:Log("info", "Binary cache loaded: " .. cache:Describe())
		else
			self:Log("info", "No usable binary cache for this rig - starting a fresh one.")
		end
	end

	self:SetPhase("hashing")
	self:SetStatus(string.format("hashing %d animation(s)...", #scan.sequences), PALETTE.Cyan)

	local records = if cache then cache:Analyze(scan, function()
		task.wait()
	end) else {}

	local registration = self._deps.registration
	if registration and #records > 0 then
		local verified = registration:Reconcile(scan.rig, records)
		if verified > 0 then
			self:Log("info", string.format("%d animation(s) verified against UploadedAnimations.", verified))
		end
	end

	self._records = records
	self:_renderRows()
	self:_updateStats()

	local dirty = 0
	for _, record in ipairs(records) do
		if record.dirty then
			dirty += 1
		end
	end

	self:SetStatus(
		string.format("%d animation(s) found | %d dirty | %d clean", #records, dirty, #records - dirty),
		PALETTE.Accent
	)
	self:Log("ok", string.format("Scan complete: %d found, %d dirty, %d clean.", #records, dirty, #records - dirty))
	self:SetPhase("idle")
end

--------------------------------------------------------------------------------
-- Uploading
--------------------------------------------------------------------------------

function UIController:_onUploadClicked(dryRun: boolean)
	if self._uploading then
		self:Log("warn", "An upload is already running.")
		return
	end

	local uploader = self._deps.uploader
	if not uploader then
		self:Log("error", "Upload service is not available.")
		return
	end

	local selected = {}
	for _, record in ipairs(self._records) do
		if record.selected then
			table.insert(selected, record)
		end
	end

	if #selected == 0 then
		self:SetStatus("nothing selected", PALETTE.Warn)
		self:Log("warn", "No animations selected.")
		return
	end

	if not self._rig then
		self:Log("error", "No rig selected.")
		return
	end

	self._uploading = true
	self:_setButtonsEnabled(false)
	self:SetProgress(0, #selected)

	local cache = self._deps.cache
	local registration = self._deps.registration
	local options = self._deps.options or {}

	uploader:SetOptions({
		CreatorType = if options.creatorType == "Group" then Enum.AssetCreatorType.Group else Enum.AssetCreatorType.User,
		GroupId = options.groupId,
	})

	local callbacks = {
		onStart = function(total: number)
			self:SetPhase(if dryRun then "dry run" else "uploading")
			self:SetStatus(
				string.format("%s %d animation(s)...", if dryRun then "simulating" else "uploading", total),
				PALETTE.Cyan
			)
			self:Log("info", string.format("%s started for %d animation(s).", if dryRun then "Dry run" else "Upload", total))
		end,

		onItemEnd = function(index: number, total: number, record: any, outcome: any)
			if outcome.success then
				self:Log("ok", string.format("[%d/%d] %s -> %d", index, total, record.name, outcome.assetId))
				if cache then
					cache:MarkUploaded(record, outcome.assetId)
				end
			else
				self:Log("error", string.format("[%d/%d] %s failed: %s", index, total, record.name, outcome.message))
			end
		end,

		onProgress = function(done: number)
			self:SetProgress(done, #selected)
		end,

		onComplete = function(summary: any)
			self:SetProgress(summary.succeeded + summary.failed, summary.total)

			if registration and not dryRun then
				local tally = registration:RegisterBatch(self._rig, summary)
				self:Log(
					"info",
					string.format("Registration: %d created, %d updated, %d failed.", tally.registered, tally.updated, tally.failed)
				)
			end

			if cache then
				if cache:Save() then
					self:Log("ok", "Binary cache saved: " .. cache:Describe())
				else
					self:Log("error", "Binary cache could not be saved: " .. tostring(cache:GetLastError()))
				end
			end

			self:SetPhase("done")
			if summary.cancelled then
				self:SetStatus("cancelled", PALETTE.Warn)
				self:Log("warn", "Upload cancelled.")
			elseif summary.failed == 0 then
				self:SetStatus(string.format("done - %d uploaded", summary.succeeded), PALETTE.Accent)
				self:Log(
					"ok",
					string.format("Finished in %.1fs: %d succeeded, %d skipped.", summary.elapsed, summary.succeeded, summary.skipped)
				)
			else
				self:SetStatus(string.format("done with %d error(s)", summary.failed), PALETTE.Error)
				self:Log(
					"error",
					string.format(
						"Finished in %.1fs: %d succeeded, %d failed, %d skipped.",
						summary.elapsed,
						summary.succeeded,
						summary.failed,
						summary.skipped
					)
				)
			end

			self._uploading = false
			self:_setButtonsEnabled(true)
			self:_renderRows()
			self:_updateStats()

			if options.autoReupload and not dryRun and summary.failed == 0 then
				task.delay(0.5, function()
					self:Refresh()
				end)
			end
		end,
	}

	if dryRun then
		uploader:DryRun(selected, callbacks, options.skipClean)
	else
		uploader:UploadBatchAsync(selected, callbacks, options.skipClean)
	end
end

function UIController:_setButtonsEnabled(enabled: boolean)
	for _, key in ipairs({ "uploadButton", "dryRunButton", "optionsButton" }) do
		local button = self._refs[key] :: TextButton?
		if button then
			button.Active = enabled
			button.AutoButtonColor = enabled
			button.TextTransparency = if enabled then 0 else 0.45
		end
	end
end

--------------------------------------------------------------------------------
-- Studio selection wiring
--------------------------------------------------------------------------------

--[[
	Connects the widget to Studio's Selection changes so the UI updates
	dynamically when the user clicks a different rig in the Explorer.
]]
function UIController:ConnectSelection(): RBXScriptSignal
	return Selection.SelectionChanged:Connect(function()
		if self._uploading then
			return
		end
		local scanner = self._deps.scanner
		if not scanner then
			return
		end
		local rig = scanner:ResolveFromSelection()
		if rig and rig ~= self._rig then
			self:SetRig(rig)
		end
	end)
end

--------------------------------------------------------------------------------
-- Teardown
--------------------------------------------------------------------------------

function UIController:Destroy()
	self._destroyed = true
	self:_clearRows()
	if self._widget then
		self._widget:Destroy()
		self._widget = nil
	end
end

return UIController
