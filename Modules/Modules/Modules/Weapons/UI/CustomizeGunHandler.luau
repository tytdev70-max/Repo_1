local Players = game:GetService("Players")

local player        = Players.LocalPlayer
local playerScripts = player:WaitForChild("PlayerScripts")
local ProxPromptHandler = playerScripts:WaitForChild("SPH_Player")
	:WaitForChild("PlayerClient")
	:WaitForChild("ProxPromptHandler")
local Main = require(ProxPromptHandler:WaitForChild("Main"))

local CustomizeGunHandler = {}

local customizePrompts: { ProximityPrompt } = {}
local isOpenCallback: (() -> boolean)? = nil
local openCallback:   (() -> ())?      = nil

local function hasWeaponEquipped(): boolean
	local character = player.Character
	if not character then return false end
	local equipped = character:FindFirstChildWhichIsA("Tool")
	return equipped ~= nil and equipped:FindFirstChild("SPH_Weapon") ~= nil
end

local function refreshPromptText()
	local equipped = hasWeaponEquipped()
	local open = isOpenCallback and isOpenCallback() or false
	for i = #customizePrompts, 1, -1 do
		local prompt = customizePrompts[i]
		if not prompt or not prompt.Parent then
			table.remove(customizePrompts, i)
			continue
		end
		prompt.ActionText = equipped and "Customize Weapon" or "Equip a gun to customize it!"
		prompt.Enabled = not open
	end
end

function CustomizeGunHandler.BindCallbacks(openFn: () -> (), isOpenFn: () -> boolean)
	openCallback   = openFn
	isOpenCallback = isOpenFn
	refreshPromptText()
end

function CustomizeGunHandler.SetPromptsEnabled(enabled: boolean)
	for _, prompt in ipairs(customizePrompts) do
		if prompt.Parent then prompt.Enabled = enabled end
	end
	if enabled then refreshPromptText() end
end

function CustomizeGunHandler.Refresh()
	refreshPromptText()
end

Main.RegisterHandler({
	name = "WeaponCustomizeTable",
	match = function(prompt: ProximityPrompt): boolean
		return prompt.Parent ~= nil and prompt.Parent.Name == "ProxPart"
	end,
	configure = function(prompt: ProximityPrompt)
		prompt.HoldDuration          = 0
		prompt.RequiresLineOfSight   = true
		prompt.MaxActivationDistance = 15
		prompt.ClickablePrompt       = false
		prompt.ActionText            = hasWeaponEquipped()
			and "Customize Weapon"
			or "Equip a gun to customize it!"
		prompt.Enabled               = true
	end,
	onDetected = function(prompt: ProximityPrompt)
		table.insert(customizePrompts, prompt)
		refreshPromptText()
	end,
	onTriggered = function(prompt: ProximityPrompt, _triggeringPlayer: Player)
		if not hasWeaponEquipped() then return end
		if isOpenCallback and isOpenCallback() then return end
		if openCallback then openCallback() end
	end,
	onRemoved = function(prompt: ProximityPrompt)
		local idx = table.find(customizePrompts, prompt)
		if idx then table.remove(customizePrompts, idx) end
	end,
})

return CustomizeGunHandler