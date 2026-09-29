--!strict

local UserInputService          = game:GetService("UserInputService")
local TweenService              = game:GetService("TweenService")
local ProximityPromptService    = game:GetService("ProximityPromptService")
local ReplicatedStorage         = game:GetService("ReplicatedStorage")
local Players                   = game:GetService("Players")
local Workspace                 = game:GetService("Workspace")

local Config = require(ReplicatedStorage.SPH_Assets.GameConfig)

local Main = require(script.Parent:WaitForChild("Main"))

local player    = Players.LocalPlayer
local character = player.Character or player.CharacterAdded:Wait()

local canView: BoolValue = script.CanView
local pickUpUI = (player.PlayerGui:WaitForChild("SPH_UI") :: any).PickUpUI

local TWEEN_TIME = 0.2
local DELAY_TIME = 0.05
local ACTION_PICK_UP = "Pick Up"
local ACTION_REFILL  = "Refill"

local activePickupPrompt: ProximityPrompt? = nil
local isMobile = UserInputService.TouchEnabled

-- ---------------------------------------------------------------------------
-- Billboard show / hide (SPH_PromptConfig prompts)
-- ---------------------------------------------------------------------------

local function ShowPrompt(promptPart, prompt)
	if not (canView.Value and character and character.Humanoid.Health > 0) then return end
	local newUI = promptPart.PromptUI
	local input = newUI.Main.Input
	local pressSquare = newUI.Main.Input.Key.Frame

	newUI.Enabled = true
	pressSquare.BackgroundTransparency = 0
	newUI.Main.Size = UDim2.fromScale(0, 0)
	newUI.Main.White.BackgroundTransparency = 0
	newUI.Main.Input.Frame.Visible = false
	newUI.Main.Input.Key.Visible = false
	for _, element in ipairs(input:GetChildren()) do
		if element:IsA("TextLabel") then element.Visible = false end
	end

	TweenService:Create(newUI.Main, TweenInfo.new(TWEEN_TIME), { Size = UDim2.fromScale(1, 0.05) }):Play()
	task.wait(TWEEN_TIME + DELAY_TIME)
	TweenService:Create(newUI.Main, TweenInfo.new(TWEEN_TIME), { Size = UDim2.fromScale(1, 1) }):Play()
	TweenService:Create(newUI.Main.White, TweenInfo.new(TWEEN_TIME), { BackgroundTransparency = 1 }):Play()
	newUI.Main.Input.Frame.Visible = true
	newUI.Main.Input.Key.Visible = true
	for _, element in ipairs(input:GetChildren()) do
		if element:IsA("TextLabel") then element.Visible = true end
	end
	task.wait(TWEEN_TIME)

	if prompt:GetAttribute("Shown") and not newUI.Enabled then
		ShowPrompt(promptPart, prompt)
	end
end

local function HidePrompt(promptPart)
	local newUI = promptPart.PromptUI
	local input = newUI.Main.Input
	local pressSquare = newUI.Main.Input.Key.Frame

	pressSquare.BackgroundTransparency = 1
	TweenService:Create(newUI.Main, TweenInfo.new(TWEEN_TIME), { Size = UDim2.fromScale(1, 0.05) }):Play()
	TweenService:Create(newUI.Main.White, TweenInfo.new(TWEEN_TIME), { BackgroundTransparency = 0 }):Play()
	newUI.Main.Input.Frame.Visible = false
	newUI.Main.Input.Key.Visible = false
	for _, element in ipairs(input:GetChildren()) do
		if element:IsA("TextLabel") then element.Visible = false end
	end
	task.wait(TWEEN_TIME + DELAY_TIME)
	TweenService:Create(newUI.Main, TweenInfo.new(TWEEN_TIME), { Size = UDim2.fromScale(0, 0.05) }):Play()
	task.wait(TWEEN_TIME)
	newUI.Enabled = false
end

-- ---------------------------------------------------------------------------
-- Prompt config UI
-- ---------------------------------------------------------------------------

local function InitAmmoPromptUI(input, promptConfig)
	input.AmmoType.Text = promptConfig.AmmoType.Value
	if promptConfig.InfAmmo.Value then
		input.AmmoPool.Text = "INF"
		return
	end
	local function updateAmmoText()
		input.AmmoPool.Text = promptConfig.AmmoPool.Value .. " / " .. promptConfig.AmmoPool.MaxValue
	end
	updateAmmoText()
	promptConfig.AmmoPool.Changed:Connect(updateAmmoText)
end

local function InitGunPromptUI(input, promptConfig, proxPrompt)
	local gunName = (proxPrompt:FindFirstChildWhichIsA("Tool") :: Tool).Name
	input.GunName.Text = gunName
	if promptConfig.InfGuns.Value then
		input.Remaining.Text = "INF"
		return
	end
	if promptConfig.GunPool.MaxValue <= 1 then
		input.Remaining.Text = ""
		return
	end
	local function updateRemainingText()
		input.Remaining.Text = promptConfig.GunPool.Value .. " / " .. promptConfig.GunPool.MaxValue .. " REMAINING"
	end
	updateRemainingText()
	promptConfig.GunPool.Changed:Connect(updateRemainingText)
end

local function SetupPrompt(prompt)
	local proxPrompt: ProximityPrompt = prompt:FindFirstChildWhichIsA("ProximityPrompt") :: ProximityPrompt
	local promptConfig = (proxPrompt :: any).SPH_PromptConfig
	local newUI = script[promptConfig.ProxType.Value]:Clone()

	newUI.Name = "PromptUI"
	newUI.Parent = prompt
	newUI.Enabled = false
	newUI.Main.HoldBar.Visible = proxPrompt.HoldDuration > 0
	newUI.Main.HoldBar.Bar.Size = UDim2.fromScale(0, 1)

	local input = newUI.Main.Input
	input.Key.KeyText.Text = UserInputService:GetStringForKeyCode(proxPrompt.KeyboardKeyCode)

	if promptConfig:FindFirstChild("AmmoType") then
		InitAmmoPromptUI(input, promptConfig)
	elseif promptConfig:FindFirstChild("GunPool") then
		InitGunPromptUI(input, promptConfig, proxPrompt)
	end

	local pressSquare = newUI.Main.Input.Key.Frame
	local pressAnim = TweenService:Create(pressSquare, TweenInfo.new(0.3), { BackgroundTransparency = 0.7, Size = UDim2.fromScale(1, 1) })
	local releaseAnim = TweenService:Create(pressSquare, TweenInfo.new(0.1), { BackgroundTransparency = 1, Size = UDim2.fromScale(0, 0) })

	if proxPrompt.HoldDuration <= 0 then
		proxPrompt.Triggered:Connect(function()
			pressSquare.Size = UDim2.fromScale(1, 1)
			pressSquare.BackgroundTransparency = 0.7
		end)
		proxPrompt.TriggerEnded:Connect(function() releaseAnim:Play() end)
	else
		local bar = newUI.Main.HoldBar.Bar
		local barAnim = TweenService:Create(bar, TweenInfo.new(proxPrompt.HoldDuration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) })
		local barReset = TweenService:Create(bar, TweenInfo.new(0.1), { Size = UDim2.fromScale(0, 1) })

		proxPrompt.PromptButtonHoldBegan:Connect(function()
			pressAnim:Play()
			barReset:Pause()
			bar.Size = UDim2.fromScale(0, 1)
			barAnim:Play()
		end)
		proxPrompt.PromptButtonHoldEnded:Connect(function()
			releaseAnim:Play()
			pressSquare.Size = UDim2.fromScale(0, 0)
			barAnim:Pause()
			barReset:Play()
		end)
	end
end

-- ---------------------------------------------------------------------------
-- Character lifecycle
-- ---------------------------------------------------------------------------

player.CharacterAdded:Connect(function(newCharacter)
	character = newCharacter
	pickUpUI = (player.PlayerGui:WaitForChild("SPH_UI") :: any).PickUpUI
	ProximityPromptService.Enabled = true
	newCharacter:WaitForChild("Humanoid").Died:Connect(function()
		ProximityPromptService.Enabled = false
	end)
end)

-- ---------------------------------------------------------------------------
-- Pickup helpers
-- ---------------------------------------------------------------------------

local function GetPromptItemTool(prompt)
	local promptParent = prompt.Parent
	local possibleItemParent = promptParent and promptParent.Parent
	local tool = possibleItemParent and possibleItemParent:FindFirstChildWhichIsA("Tool")
	return promptParent, possibleItemParent, tool
end

-- ---------------------------------------------------------------------------
-- Shown / Hidden (config UI + pickups)
-- ---------------------------------------------------------------------------

ProximityPromptService.PromptShown:Connect(function(prompt)
	prompt:SetAttribute("Shown", true)
	local promptParent, possibleItemParent, tool = GetPromptItemTool(prompt)

	if tool and tool:FindFirstChild("SPH_Weapon") and not Config.pickupGuns then
		if possibleItemParent and possibleItemParent:FindFirstChild("PickupHighlight") then
			possibleItemParent.PickupHighlight.Enabled = false
		end
		if pickUpUI then pickUpUI.Visible = false end
		local prox = promptParent:FindFirstChildWhichIsA("ProximityPrompt")
		if prox then prox.Enabled = false end
		return
	end

	if isMobile then
		if prompt:FindFirstChild("SPH_PromptConfig") then
			local promptConfig = prompt.SPH_PromptConfig
			if promptConfig:FindFirstChild("AmmoType") then
				prompt.ObjectText = promptConfig.AmmoType.Value .. " Ammo"
				prompt.ActionText = ACTION_REFILL
				if not promptConfig.InfAmmo.Value then
					promptConfig.AmmoPool.Changed:Connect(function()
						if promptConfig.AmmoPool.Value <= 0 then
							prompt.ObjectText = promptConfig.AmmoType.Value .. " Ammo (Empty)"
						else
							prompt.ObjectText = promptConfig.AmmoType.Value .. " Ammo"
						end
					end)
				end
			elseif promptConfig:FindFirstChild("GunPool") then
				local gunTool = prompt:FindFirstChildWhichIsA("Tool")
				local gunName = gunTool and gunTool.Name or "Weapon"
				prompt.ObjectText = gunName
				prompt.ActionText = ACTION_PICK_UP
				if not promptConfig.InfGuns.Value and promptConfig.GunPool.MaxValue > 1 then
					local function updateGunText()
						if promptConfig.GunPool.Value <= 0 then
							prompt.ObjectText = gunName .. " (None Left)"
						else
							prompt.ObjectText = gunName .. " (" .. promptConfig.GunPool.Value .. " left)"
						end
					end
					updateGunText()
					promptConfig.GunPool.Changed:Connect(updateGunText)
				end
			end
			prompt.Style = Enum.ProximityPromptStyle.Default
		elseif promptParent and possibleItemParent and possibleItemParent:FindFirstChild("PickupHighlight") then
			prompt.ActionText = ACTION_PICK_UP
			local wepTool = possibleItemParent:FindFirstChildWhichIsA("Tool")
			if wepTool and wepTool:FindFirstChild("SPH_Weapon") then
				local wepStats = require(wepTool.SPH_Weapon.WeaponStats)
				prompt.ObjectText = possibleItemParent.Name .. " (" .. wepStats.ammoType .. ")"
			else
				prompt.ObjectText = possibleItemParent.Name
			end
			prompt.Style = Enum.ProximityPromptStyle.Default
		end
		return
	end

	if prompt:FindFirstChild("SPH_PromptConfig") then
		if not (prompt.Parent :: Instance):FindFirstChild("PromptUI") then
			SetupPrompt(prompt.Parent :: Instance)
		end
		ShowPrompt(prompt.Parent, prompt)
	elseif pickUpUI:FindFirstChild("ItemName") and promptParent and promptParent.Parent:FindFirstChild("PickupHighlight") then
		activePickupPrompt = prompt
		promptParent.Parent.PickupHighlight.Enabled = true
		pickUpUI.Visible = true
		pickUpUI.ItemName.Text = "[" .. string.upper(Config.pickupKey[1].Name) .. "] " .. promptParent.Parent.Name
		local wepTool = promptParent.Parent:FindFirstChildWhichIsA("Tool")
		if wepTool and wepTool:FindFirstChild("SPH_Weapon") then
			local wepStats = require(wepTool.SPH_Weapon.WeaponStats)
			pickUpUI.ItemName.Text = pickUpUI.ItemName.Text .. " " .. wepStats.ammoType
		end
	end
end)

ProximityPromptService.PromptHidden:Connect(function(prompt)
	prompt:SetAttribute("Shown", false)
	local promptParent, possibleItemParent, tool = GetPromptItemTool(prompt)

	if tool and tool:FindFirstChild("SPH_Weapon") then
		local prox = promptParent and promptParent:FindFirstChildWhichIsA("ProximityPrompt")
		if prox and Config.pickupGuns then prox.Enabled = true end
	end

	if isMobile then
		prompt.Style = Enum.ProximityPromptStyle.Default
		return
	end

	if prompt:FindFirstChild("SPH_PromptConfig") then
		if not (prompt.Parent :: Instance):FindFirstChild("PromptUI") then
			SetupPrompt(prompt.Parent :: Instance)
		end
		HidePrompt(prompt.Parent)
	elseif promptParent and promptParent.Parent:FindFirstChild("PickupHighlight") then
		if activePickupPrompt == prompt then
			activePickupPrompt = nil
			promptParent.Parent.PickupHighlight.Enabled = false
			pickUpUI.Visible = false
		end
	else
		if activePickupPrompt == prompt then
			activePickupPrompt = nil
			pickUpUI.Visible = false
		end
	end
end)

return true