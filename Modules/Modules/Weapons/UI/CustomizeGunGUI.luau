local CustomizeGunGUI = {}
local Modules = script:FindFirstAncestor("Modules")

-- Init runs once per character; keep a single live connection per event.
local confirmedConnection: RBXScriptConnection? = nil
local reloadStatsConnection: RBXScriptConnection? = nil
local Attachments = require(Modules.Weapons.Attachments.SPHAttachments)

function CustomizeGunGUI.Init(config)
	local vars = require(Modules.Weapons.Core.WeaponState).get()
	local SPH_Events = require(Modules.Core.Networking.SPH_Events)
	local player = config.player
	local replicatedStorage = config.replicatedStorage
	local assets = config.assets
	local character = config.character
	local humanoid = config.humanoid
	local mobileSupport = config.mobileSupport
	local aimingSystemMod = config.aimingSystemMod
	local recoilSpring = config.recoilSpring
	local gunRecoilSpring = config.gunRecoilSpring
	local aimFOVTargetRef = config.aimFOVTargetRef
	local gameConfig = config.gameConfig
	local defaultFOV = config.defaultFOV
	local playerToggleAttachment = config.playerToggleAttachment
	local collectAndManageSights = config.collectAndManageSights
	local glareMod = config.glareMod
	local getThirdPersonGunModel = config.getThirdPersonGunModel

	-- Put the menu ScreenGui into PlayerGui. The CustomizeGunGUI LocalScript that starts
	-- the menu lives INSIDE this template, so without this clone it never runs.
	if not player.PlayerGui:FindFirstChild("CustomizeGunGUI") then
		local hud = assets:FindFirstChild("HUD")
		local gunGUIs = hud and hud:FindFirstChild("GunGUIs")
		local template = gunGUIs and gunGUIs:FindFirstChild("CustomizeGunGUI")
		if template then
			local customizeGUI = template:Clone()
			customizeGUI.ResetOnSpawn = false
			customizeGUI.Enabled = false
			customizeGUI.Parent = player.PlayerGui
		else
			warn("[Customization] SPH_Assets.HUD.GunGUIs.CustomizeGunGUI not found - menu won't start")
		end
	end

	-- Viewmodel refresh after the Customize menu confirms. The menu (Weapons/UI/Customize)
	-- sends the loadout to the server itself and then fires GunEvents.CustomizeConfirmed
	-- with (tool, loadout). This replaces the old hook on the legacy template's
	-- ConfirmButton (found by path) and its duplicate FireServer.
	local confirmedEvent = SPH_Events.GetOrCreate("GunEvents", "CustomizeConfirmed", "BindableEvent")
	if confirmedConnection then
		confirmedConnection:Disconnect()
	end
	confirmedConnection = confirmedEvent.Event:Connect(function(tool, confirmedLoadout)
		local equipped = vars.equipped
		local gunModel = vars.gunModel

		if not equipped or not gunModel or tool ~= equipped then
			return
		end
		local localLoadout = Attachments:SanitizeLoadout(confirmedLoadout or {}, equipped)

		-- Rebuild the viewmodel gun with the confirmed loadout (sanitizing again is idempotent).
		Attachments:ApplyLoadout(gunModel, equipped, player, localLoadout)

		collectAndManageSights(gunModel)

		mobileSupport.UpdateMobileButtonVisibility()

		if vars.laserEnabled then
			local laserSource = Attachments:GetLaserSource(gunModel)
			local tpLaserSource
			if getThirdPersonGunModel then
				local tpGunModel = getThirdPersonGunModel()
				tpLaserSource = tpGunModel and Attachments:GetLaserSource(tpGunModel)
			end
			if laserSource or tpLaserSource then
				local laserColor = Color3.fromRGB(255, 30, 30)
				local colorSource = laserSource or tpLaserSource
				if colorSource:FindFirstChild("Color") then
					laserColor = colorSource.Color.Value
				end
				if glareMod then
					glareMod.SetLaserModelActive(laserSource, tpLaserSource, vars.firstPerson, true, laserColor, vars.wepStats)
				end
			end

			task.spawn(function()
				task.wait(0.2)
				playerToggleAttachment.send({ AttachmentType = 1, Enabled = false })
				task.wait(0.05)
				playerToggleAttachment.send({ AttachmentType = 1, Enabled = true })
			end)
		end

		if vars.flashlightEnabled then
			local flashlightPart = Attachments:GetFlashlightSource(gunModel)
			if flashlightPart then
				vars.flashFX.mod.SetEnabled(flashlightPart, true, vars.wepStats)
			end

			local tpFlashlightPart
			if getThirdPersonGunModel then
				local tpGunModel = getThirdPersonGunModel()
				if tpGunModel then
					tpFlashlightPart = Attachments:GetFlashlightSource(tpGunModel)
					if tpFlashlightPart then
						vars.flashFX.mod.SetEnabled(tpFlashlightPart, not vars.firstPerson, vars.wepStats)
					end
				end
			end

			if glareMod and (flashlightPart or tpFlashlightPart) then
				local flashColor = glareMod.ResolveFlashlightColor(flashlightPart or tpFlashlightPart, vars.wepStats)
				glareMod.SetFlashlightModelActive(flashlightPart, tpFlashlightPart, vars.firstPerson, true, flashColor, vars.wepStats)
			end

			task.spawn(function()
				task.wait(0.2)
				playerToggleAttachment.send({ AttachmentType = 0, Enabled = false })
				task.wait(0.05)
				playerToggleAttachment.send({ AttachmentType = 0, Enabled = true })
			end)
		end

		local baseStats = require(equipped.SPH_Weapon.WeaponStats)
		Attachments:SetBaseStats(equipped, baseStats)
		local newWepStats = Attachments:ComputeStats(equipped, gunModel)

		local baseWalkSpeed = gameConfig.walkSpeed or 16
		humanoid.WalkSpeed = baseWalkSpeed * (newWepStats.walkSpeedMultiplier or 1.0)
		character:SetAttribute("SprintSpeedMultiplier", newWepStats.sprintSpeedMultiplier or 1.0)

		local newAimFOVTarget = newWepStats.aimFovDefault or newWepStats.aimFov or defaultFOV
		vars.aimFOVTarget = newAimFOVTarget
		aimFOVTargetRef.value = newAimFOVTarget
		newWepStats.aimFovMin = newWepStats.aimFovMin or 30
		newWepStats.aimFovMax = newWepStats.aimFovMax or defaultFOV

		recoilSpring.Damping = newWepStats.recoil.damping
		recoilSpring.Speed = newWepStats.recoil.speed
		gunRecoilSpring.Damping = newWepStats.gunRecoil.damping
		gunRecoilSpring.Speed = newWepStats.gunRecoil.speed

		vars.wepStats = newWepStats

		if aimingSystemMod then
			aimingSystemMod.UpdateADSVisual(gunModel, newWepStats, vars.sightIndex, vars.aiming == true)
		end

		print("[Customization] All stats reloaded successfully")
	end)

	local events = assets:WaitForChild("Events")
	local gunEvents = events:WaitForChild("GunEvents")
	local reloadStatsEvent = gunEvents:FindFirstChild("ReloadWeaponStats")
	if reloadStatsEvent then
		if reloadStatsConnection then
			reloadStatsConnection:Disconnect()
		end
		reloadStatsConnection = reloadStatsEvent.OnClientEvent:Connect(function(weapon)
			local equipped = vars.equipped
			local wepStats = vars.wepStats

			if weapon == equipped and wepStats then
				print("[Gun Client] Reloading weapon stats after customization")

				local baseStats = require(equipped.SPH_Weapon.WeaponStats)
				Attachments:SetBaseStats(equipped, baseStats)
				local newWepStats = Attachments:ComputeStats(equipped, vars.gunModel)

				mobileSupport.UpdateMobileButtonVisibility()

				local baseWalkSpeed = gameConfig.walkSpeed or 16
				humanoid.WalkSpeed = baseWalkSpeed * (newWepStats.walkSpeedMultiplier or 1.0)
				character:SetAttribute("SprintSpeedMultiplier", newWepStats.sprintSpeedMultiplier or 1.0)

				local newAimFOVTarget = newWepStats.aimFovDefault or newWepStats.aimFov or defaultFOV
				vars.aimFOVTarget = newAimFOVTarget
				aimFOVTargetRef.value = newAimFOVTarget
				if not newWepStats.aimFovMin then newWepStats.aimFovMin = 30 end
				if not newWepStats.aimFovMax then newWepStats.aimFovMax = defaultFOV end

				vars.wepStats = newWepStats

				print("[Gun Client] Weapon stats successfully reloaded!")
			end
		end)
	else
		warn("[Gun Client] ReloadWeaponStats event not found - stats won't update on customization")
	end
end

return CustomizeGunGUI