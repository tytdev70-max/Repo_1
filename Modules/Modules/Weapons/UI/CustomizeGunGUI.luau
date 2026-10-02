local CustomizeGunGUI = {}
local Modules = script:FindFirstAncestor("Modules")

function CustomizeGunGUI.Init(config)
	local vars = require(Modules.Weapons.Core.WeaponState).get()
	local SPH_Events = require(Modules.Core.Networking.SPH_Events)
	local player = config.player
	local replicatedStorage = config.replicatedStorage
	local assets = config.assets
	local character = config.character
	local humanoid = config.humanoid
	local attachmentManager = config.attachmentManager
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

	local customizeGUI = player.PlayerGui:FindFirstChild("CustomizeGunGUI")
	if not customizeGUI then
		local hud = assets:FindFirstChild("HUD")
		local gunGUIs = hud and hud:FindFirstChild("GunGUIs")
		local customizeGUITemplate = gunGUIs and gunGUIs:FindFirstChild("CustomizeGunGUI")
		if customizeGUITemplate then
			customizeGUI = customizeGUITemplate:Clone()
			customizeGUI.Parent = player.PlayerGui
			customizeGUI.ResetOnSpawn = false
		end
	end
	if customizeGUI then
		local mainDisplayFrame = customizeGUI:FindFirstChild("MainDisplayFrame")
		if not mainDisplayFrame then
			warn("[Customization] MainDisplayFrame not found!")
			return
		end

		local content = mainDisplayFrame:FindFirstChild("content")
		if not content then
			warn("[Customization] content frame not found!")
			return
		end

		local confirmButton = content:FindFirstChild("ConfirmButton")

		if confirmButton then
			confirmButton.MouseButton1Click:Connect(function()
				local equipped = vars.equipped
				local gunModel = vars.gunModel

				if not equipped or not gunModel then
					warn("No weapon equipped!")
					return
				end

				local getSelectedFunction = SPH_Events.Find("GunEvents", "GetSelectedAttachments")
				if not getSelectedFunction then
					warn("[Customization] GetSelectedAttachments function not found!")
					return
				end

				local selectedAttachments = getSelectedFunction:Invoke()

				local gunEvents = assets.Events:WaitForChild("GunEvents")
				local applyEvent = gunEvents:FindFirstChild("ApplyWeaponAttachments")
				if applyEvent then
					applyEvent:FireServer(selectedAttachments)
					print("[Client] Sent attachments to server:", selectedAttachments)
				end

				attachmentManager.ClearAllAttachments(gunModel)

				for category, attachmentName in pairs(selectedAttachments) do
					if attachmentName and attachmentName ~= "" then
						attachmentManager.EquipAttachment(player, equipped, gunModel, attachmentName, category)
					end
				end

				collectAndManageSights(gunModel)

				mobileSupport.UpdateMobileButtonVisibility()

				if vars.laserEnabled then
					local laserSource = attachmentManager.GetLaserSource(gunModel)
					local tpLaserSource
					if getThirdPersonGunModel then
						local tpGunModel = getThirdPersonGunModel()
						tpLaserSource = tpGunModel and attachmentManager.GetLaserSource(tpGunModel)
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
					local flashlightPart = attachmentManager.GetFlashlightSource(gunModel)
					if flashlightPart then
						vars.flashFX.mod.SetEnabled(flashlightPart, true, vars.wepStats)
					end

					local tpFlashlightPart
					if getThirdPersonGunModel then
						local tpGunModel = getThirdPersonGunModel()
						if tpGunModel then
							tpFlashlightPart = attachmentManager.GetFlashlightSource(tpGunModel)
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
				attachmentManager.StoreOriginalStats(equipped, baseStats)
				local newWepStats = attachmentManager.ApplyAttachmentStats(equipped, gunModel)

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
					aimingSystemMod.UpdateADSVisual(gunModel, newWepStats, vars.sightIndex, vars.aiming == true, attachmentManager)
				end

				print("[Customization] All stats reloaded successfully")

				customizeGUI.Enabled = false
			end)
		end
	end

	local events = assets:WaitForChild("Events")
	local gunEvents = events:WaitForChild("GunEvents")
	local reloadStatsEvent = gunEvents:FindFirstChild("ReloadWeaponStats")
	if reloadStatsEvent then
		reloadStatsEvent.OnClientEvent:Connect(function(weapon)
			local equipped = vars.equipped
			local wepStats = vars.wepStats

			if weapon == equipped and wepStats then
				print("[Gun Client] Reloading weapon stats after customization")

				local baseStats = require(equipped.SPH_Weapon.WeaponStats)
				attachmentManager.StoreOriginalStats(equipped, baseStats)
				local newWepStats = attachmentManager.ApplyAttachmentStats(equipped, vars.gunModel)

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