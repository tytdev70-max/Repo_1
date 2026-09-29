local tweenService = game:GetService("TweenService")
local FireModeCheckDisplay = {}
local Modules = script:FindFirstAncestor("Modules")
local vars = require(Modules.Weapons.Core.WeaponState).get()
local player
local playAnimation
local toggleAiming

local function GetOriginalValue(instance, propertyName)
	local attrName = "SPH_Orig_" .. propertyName
	local existing = instance:GetAttribute(attrName)
	if existing == nil then
		existing = instance[propertyName]
		instance:SetAttribute(attrName, existing)
	end
	return existing
end

function FireModeCheckDisplay.Init(config)
	player = config.player
	playAnimation = config.playAnimation
	toggleAiming = config.toggleAiming
end

function FireModeCheckDisplay.DoFireModeCheck()
	local equipped = vars.equipped
	local reloading = vars.reloading
	local wepStats = vars.wepStats
	local aiming = vars.aiming
	local curFireMode = vars.curFireMode
	local loadedAnims = vars.loadedAnims

	if vars.fireModeCheckFadeOutTask then
		task.cancel(vars.fireModeCheckFadeOutTask)
		vars.fireModeCheckFadeOutTask = nil
	end

	local sphUI = player.PlayerGui:FindFirstChild("SPH_UI")
	local firemodeFrame = sphUI and sphUI:FindFirstChild("FiremodeCheck")
	if firemodeFrame then
		firemodeFrame.Visible = false
	end

	if vars.fireModeCheckDebounce and not equipped then
		vars.fireModeCheckDebounce = false
		return
	end

	if not equipped or vars.fireModeCheckDebounce or reloading or vars.chambering or vars.magCheckDebounce then return end

	if aiming then toggleAiming(false) end
	vars.fireModeCheckDebounce = true

	local animName = wepStats.firemodeCheck or wepStats.switchAnim
	if animName then
		local track = playAnimation(animName, {priority = Enum.AnimationPriority.Action2})
		if track then
			track.Stopped:Once(function()
				vars.fireModeCheckDebounce = false
			end)
		else
			task.delay(1, function() vars.fireModeCheckDebounce = false end)
		end
	else
		vars.fireModeCheckDebounce = false
		return
	end

	local mainFrame = sphUI and sphUI:FindFirstChild("FiremodeCheck")
	if not mainFrame then
		vars.fireModeCheckDebounce = false
		return
	end

	local uiStroke = mainFrame:FindFirstChild("UIStroke")
	local firemodeText = mainFrame:FindFirstChild("FiremodeText")

	local frameOriginal = GetOriginalValue(mainFrame, "BackgroundTransparency")
	local strokeOriginal = uiStroke and GetOriginalValue(uiStroke, "Transparency")
	local textOriginal = firemodeText and GetOriginalValue(firemodeText, "TextTransparency")

	mainFrame.BackgroundTransparency = 1
	if uiStroke then uiStroke.Transparency = 1 end
	if firemodeText then firemodeText.TextTransparency = 1 end
	mainFrame.Visible = true

	local modeNames = {"SAFE", "SEMI", "AUTO", "BURST", "MANUAL"}
	if firemodeText then
		firemodeText.Text = modeNames[curFireMode + 1] or "Unknown"
	end

	local fadeTime = 0.18
	tweenService:Create(mainFrame, TweenInfo.new(fadeTime), {BackgroundTransparency = frameOriginal}):Play()
	if uiStroke then
		tweenService:Create(uiStroke, TweenInfo.new(fadeTime), {Transparency = strokeOriginal}):Play()
	end
	if firemodeText then
		tweenService:Create(firemodeText, TweenInfo.new(fadeTime), {TextTransparency = textOriginal}):Play()
	end

	if animName then
		local animLength = loadedAnims[animName] and loadedAnims[animName].Length or 1.2
		local fadeOutStart = math.max(animLength - 0.35, animLength * 0.65)
		vars.fireModeCheckFadeOutTask = task.delay(fadeOutStart, function()
			vars.fireModeCheckFadeOutTask = nil
			tweenService:Create(mainFrame, TweenInfo.new(0.25), {BackgroundTransparency = 1}):Play()
			if uiStroke then
				tweenService:Create(uiStroke, TweenInfo.new(0.25), {Transparency = 1}):Play()
			end
			if firemodeText then
				tweenService:Create(firemodeText, TweenInfo.new(0.25), {TextTransparency = 1}):Play()
			end
			task.delay(0.3, function()
				mainFrame.Visible = false
			end)
		end)
	end
end

return FireModeCheckDisplay