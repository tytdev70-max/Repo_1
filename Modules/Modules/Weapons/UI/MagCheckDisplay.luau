local tweenService = game:GetService("TweenService")

local MagCheckDisplay = {}
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

function MagCheckDisplay.Init(config)
	player = config.player
	playAnimation = config.playAnimation
	toggleAiming = config.toggleAiming
end

function MagCheckDisplay.Hide()
	if vars.magCheckFadeOutTask then
		task.cancel(vars.magCheckFadeOutTask)
		vars.magCheckFadeOutTask = nil
	end
	local sphUI = player and player.PlayerGui and player.PlayerGui:FindFirstChild("SPH_UI")
	local magCheckFrame = sphUI and sphUI:FindFirstChild("MagCheck")
	if magCheckFrame then
		magCheckFrame.Visible = false
	end
	vars.magCheckDebounce = false
end

function MagCheckDisplay.DoMagCheck()
	local equipped = vars.equipped
	local reloading = vars.reloading
	local aiming = vars.aiming
	local wepStats = vars.wepStats
	local gunAmmo = vars.gunAmmo

	if vars.magCheckFadeOutTask then
		task.cancel(vars.magCheckFadeOutTask)
		vars.magCheckFadeOutTask = nil
	end

	local sphUI = player.PlayerGui:FindFirstChild("SPH_UI")
	local magCheckFrame = sphUI and sphUI:FindFirstChild("MagCheck")
	if magCheckFrame then
		magCheckFrame.Visible = false
	end

	if vars.magCheckDebounce and not equipped then
		vars.magCheckDebounce = false
		return
	end

	if not equipped or reloading or vars.magCheckDebounce or vars.unequipping or vars.equipping then return end

	local magAmmo = gunAmmo and gunAmmo:FindFirstChild("MagAmmo")
	if not magAmmo then return end

	if aiming then toggleAiming(false) end
	vars.magCheckDebounce = true

	if wepStats.magCheck then
		local magCheckAnim = playAnimation(wepStats.magCheck, {priority = Enum.AnimationPriority.Action2})

		local mainFrame = sphUI and sphUI:FindFirstChild("MagCheck")
		if mainFrame then
			local ammoPercent = gunAmmo.MagAmmo.Value / gunAmmo.MagAmmo.MaxValue
			local filling = mainFrame.Mag:FindFirstChild("Filling")

			local strokeInst = mainFrame:FindFirstChild("UIStroke")
			local lineInst = mainFrame:FindFirstChild("Line")
			local magInst = mainFrame:FindFirstChild("Mag")
			local magStrokeInst = magInst and magInst:FindFirstChild("UIStroke")
			local whiteBGInst = mainFrame:FindFirstChild("WhiteBackground")
			local ammoTextInst = mainFrame:FindFirstChild("AmmoLeftText")
			local magTextInst = mainFrame:FindFirstChild("MagLeftText")
			local plusAmmoInst = mainFrame:FindFirstChild("PlusAmmo")
			local shadowBGFolder = mainFrame:FindFirstChild("ShadowBG")
			local shadowBGImage = shadowBGFolder and shadowBGFolder:FindFirstChildWhichIsA("ImageLabel")

			local frameOriginal = GetOriginalValue(mainFrame, "BackgroundTransparency")
			local strokeOriginal = strokeInst and GetOriginalValue(strokeInst, "Transparency")
			local lineOriginal = lineInst and GetOriginalValue(lineInst, "BackgroundTransparency")
			local magOriginal = magInst and GetOriginalValue(magInst, "BackgroundTransparency")
			local magStrokeOriginal = magStrokeInst and GetOriginalValue(magStrokeInst, "Transparency")
			local fillingOriginal = filling and GetOriginalValue(filling, "BackgroundTransparency")
			local whiteBGOriginal = whiteBGInst and GetOriginalValue(whiteBGInst, "BackgroundTransparency")
			local ammoTextOriginal = ammoTextInst and GetOriginalValue(ammoTextInst, "TextTransparency")
			local magTextOriginal = magTextInst and GetOriginalValue(magTextInst, "TextTransparency")
			local plusAmmoOriginal = plusAmmoInst and GetOriginalValue(plusAmmoInst, "TextTransparency")
			local shadowBGOriginal = shadowBGImage and GetOriginalValue(shadowBGImage, "ImageTransparency")

			mainFrame.BackgroundTransparency = 1
			if strokeInst then strokeInst.Transparency = 1 end
			if lineInst then lineInst.BackgroundTransparency = 1 end
			if magInst then
				magInst.BackgroundTransparency = 1
				if magStrokeInst then magStrokeInst.Transparency = 1 end
			end
			if filling then filling.BackgroundTransparency = 1 end
			if whiteBGInst then whiteBGInst.BackgroundTransparency = 1 end
			if ammoTextInst then ammoTextInst.TextTransparency = 1 end
			if magTextInst then magTextInst.TextTransparency = 1 end
			if shadowBGImage then shadowBGImage.ImageTransparency = 1 end

			if ammoTextInst then
				local displayAmmo = gunAmmo.MagAmmo.Value
				local hasChamberedRound = equipped.Chambered.Value

				ammoTextInst.Text = displayAmmo .. "/" .. gunAmmo.MagAmmo.MaxValue

				if plusAmmoInst then
					plusAmmoInst.Visible = hasChamberedRound
					plusAmmoInst.TextTransparency = 1
				end
			end

			if magTextInst then
				local reserveAmmo = gunAmmo.ArcadeAmmoPool.Value
				local magCapacity = gunAmmo.MagAmmo.MaxValue

				local isShotgun = wepStats.shotgun == true
				local containerSingular = isShotgun and "Shell" or "Spare Mag"
				local containerPlural = isShotgun and "Shells" or "Spare Mags"
				local roundSingular = isShotgun and "shell" or "round"
				local roundPlural = isShotgun and "shells" or "rounds"

				if isShotgun then
					if reserveAmmo > 0 then
						magTextInst.Text = reserveAmmo .. " " .. (reserveAmmo == 1 and roundSingular or roundPlural) .. " left"
					else
						magTextInst.Text = "No Spare Ammo"
					end
				else
					local spareMags = math.floor(reserveAmmo / magCapacity)
					local looseRounds = reserveAmmo % magCapacity

					if spareMags > 0 and looseRounds > 0 then
						magTextInst.Text = spareMags .. " " .. (spareMags == 1 and containerSingular or containerPlural) .. " + " .. looseRounds .. " " .. (looseRounds == 1 and roundSingular or roundPlural)
					elseif spareMags > 0 then
						magTextInst.Text = spareMags .. " " .. (spareMags == 1 and containerSingular or containerPlural) .. " Left"
					elseif looseRounds > 0 then
						magTextInst.Text = looseRounds .. " " .. (looseRounds == 1 and roundSingular or roundPlural) .. " left"
					else
						magTextInst.Text = "No Spare Ammo"
					end
				end
			end

			mainFrame.Visible = true

			local fadeInTime = 0.15
			tweenService:Create(mainFrame, TweenInfo.new(fadeInTime), {BackgroundTransparency = frameOriginal}):Play()

			if strokeInst then
				tweenService:Create(strokeInst, TweenInfo.new(fadeInTime), {Transparency = strokeOriginal}):Play()
			end

			if lineInst then
				tweenService:Create(lineInst, TweenInfo.new(fadeInTime), {BackgroundTransparency = lineOriginal}):Play()
			end

			if magInst then
				tweenService:Create(magInst, TweenInfo.new(fadeInTime), {BackgroundTransparency = magOriginal}):Play()
				if magStrokeInst then
					tweenService:Create(magStrokeInst, TweenInfo.new(fadeInTime), {Transparency = magStrokeOriginal}):Play()
				end
			end

			if whiteBGInst then
				tweenService:Create(whiteBGInst, TweenInfo.new(fadeInTime), {BackgroundTransparency = whiteBGOriginal}):Play()
			end

			if ammoTextInst then
				tweenService:Create(ammoTextInst, TweenInfo.new(fadeInTime), {TextTransparency = ammoTextOriginal}):Play()
			end

			if magTextInst then
				tweenService:Create(magTextInst, TweenInfo.new(fadeInTime), {TextTransparency = magTextOriginal}):Play()
			end

			if plusAmmoInst and plusAmmoInst.Visible then
				tweenService:Create(plusAmmoInst, TweenInfo.new(fadeInTime), {TextTransparency = plusAmmoOriginal}):Play()
			end

			if shadowBGImage then
				tweenService:Create(shadowBGImage, TweenInfo.new(fadeInTime), {ImageTransparency = shadowBGOriginal}):Play()
			end

			if filling then
				filling.AnchorPoint = Vector2.new(0, 1)
				filling.Position = UDim2.new(0, 0, 1, 0)
				filling.Size = UDim2.new(1, 0, 1, 0)
				filling.BackgroundTransparency = 1

				task.wait(fadeInTime)

				tweenService:Create(filling, TweenInfo.new(fadeInTime), {BackgroundTransparency = fillingOriginal}):Play()
				tweenService:Create(filling, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Size = UDim2.new(1, 0, ammoPercent, 0)}):Play()
			end

			if magCheckAnim then
				local animLength = magCheckAnim.Length
				local fadeOutStart = math.max(animLength - 0.3, animLength * 0.7)

				vars.magCheckFadeOutTask = task.delay(fadeOutStart, function()
					vars.magCheckFadeOutTask = nil

					local fadeOutTime = 0.2
					tweenService:Create(mainFrame, TweenInfo.new(fadeOutTime), {BackgroundTransparency = 1}):Play()

					if strokeInst then
						tweenService:Create(strokeInst, TweenInfo.new(fadeOutTime), {Transparency = 1}):Play()
					end

					if lineInst then
						tweenService:Create(lineInst, TweenInfo.new(fadeOutTime), {BackgroundTransparency = 1}):Play()
					end

					if magInst then
						tweenService:Create(magInst, TweenInfo.new(fadeOutTime), {BackgroundTransparency = 1}):Play()
						if magStrokeInst then
							tweenService:Create(magStrokeInst, TweenInfo.new(fadeOutTime), {Transparency = 1}):Play()
						end
					end

					if filling then
						tweenService:Create(filling, TweenInfo.new(fadeOutTime), {BackgroundTransparency = 1}):Play()
					end

					if whiteBGInst then
						tweenService:Create(whiteBGInst, TweenInfo.new(fadeOutTime), {BackgroundTransparency = 1}):Play()
					end

					if ammoTextInst then
						tweenService:Create(ammoTextInst, TweenInfo.new(fadeOutTime), {TextTransparency = 1}):Play()
					end

					if magTextInst then
						tweenService:Create(magTextInst, TweenInfo.new(fadeOutTime), {TextTransparency = 1}):Play()
					end

					if plusAmmoInst and plusAmmoInst.Visible then
						tweenService:Create(plusAmmoInst, TweenInfo.new(fadeOutTime), {TextTransparency = 1}):Play()
					end

					if shadowBGImage then
						tweenService:Create(shadowBGImage, TweenInfo.new(fadeOutTime), {ImageTransparency = 1}):Play()
					end

					task.wait(fadeOutTime + 0.1)
					mainFrame.Visible = false
				end)
			end
		end

		if magCheckAnim then
			magCheckAnim.Stopped:Once(function()
				vars.magCheckDebounce = false
			end)
		else
			task.delay(1, function()
				vars.magCheckDebounce = false
			end)
		end
	else
		vars.magCheckDebounce = false
	end
end

return MagCheckDisplay