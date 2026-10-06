--!nonstrict
-- Customize/TestHud
-- The "Return to Gunsmith" button shown while testing a loadout. The menu's own
-- ScreenGui is disabled during a test, so the button lives in its own ScreenGui:
--   PlayerGui.GunsmithTestHUD (design it yourself: it needs a GuiButton named ReturnButton,
--   or a button-like element containing one), otherwise a simple one is created
--   at the top left.

local TestHud = {}
TestHud.__index = TestHud

local GUI_NAME = "GunsmithTestHUD"

-- options: { playerGui: Instance, text: string, onReturn: () -> () }
function TestHud.new(options: { [string]: any })
	local self = setmetatable({}, TestHud)
	self._playerGui = options.playerGui
	self._text = options.text or "Return"
	self._onReturn = options.onReturn
	self._gui = nil
	self._created = false
	self._connection = nil
	return self
end

local function findButton(gui: Instance): GuiButton?
	local element = gui:FindFirstChild("ReturnButton", true)
	if not element then
		return nil
	end
	if element:IsA("GuiButton") then
		return element
	end
	return element:FindFirstChildWhichIsA("GuiButton", true)
end

function TestHud:_ensure(): (Instance?, GuiButton?)
	if self._gui and self._gui.Parent then
		return self._gui, findButton(self._gui)
	end
	local gui = self._playerGui and self._playerGui:FindFirstChild(GUI_NAME)
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = GUI_NAME
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 50
		local button = Instance.new("TextButton")
		button.Name = "ReturnButton"
		button.AnchorPoint = Vector2.new(0, 0)
		button.Position = UDim2.fromOffset(16, 16) -- below the Roblox top bar (inset is kept)
		button.Size = UDim2.fromOffset(200, 44)
		button.BackgroundColor3 = Color3.fromRGB(24, 26, 30)
		button.BackgroundTransparency = 0.15
		button.TextColor3 = Color3.fromRGB(235, 238, 242)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.Text = self._text
		button.AutoButtonColor = true
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 8)
		corner.Parent = button
		button.Parent = gui
		gui.Parent = self._playerGui
		self._created = true
	end
	self._gui = gui
	return gui, findButton(gui)
end

function TestHud:Show()
	local gui, button = self:_ensure()
	if not gui then
		return
	end
	if self._connection then
		self._connection:Disconnect()
	end
	if button then
		self._connection = button.MouseButton1Click:Connect(function()
			if self._onReturn then
				self._onReturn()
			end
		end)
	else
		warn("[Gunsmith] " .. gui:GetFullName() .. " has no ReturnButton")
	end
	gui.Enabled = true
end

function TestHud:Hide()
	if self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
	if self._gui and self._gui.Parent then
		self._gui.Enabled = false
	end
end

function TestHud:Destroy()
	self:Hide()
	if self._created and self._gui then
		self._gui:Destroy()
	end
	self._gui = nil
end

return TestHud
