-- ProximityPromptHandlers
-- HandleAmmoGiverPrompt, HandleGunGiverPrompt, PromptTriggered connection.

local ServiceRefs = require(script.Parent.ServiceRefs)
local AssetRefs   = require(script.Parent.AssetRefs)

local proxPromptService = ServiceRefs.proxPromptService
local assets            = AssetRefs.assets
local config            = AssetRefs.config

local ProximityPromptHandlers = {}

local function HandleAmmoGiverPrompt(prompt: Instance, player: Player)
	local ammoTaken    = false
	local promptConfig = prompt.SPH_PromptConfig
	local ammoPool     = promptConfig.AmmoPool
	if ammoPool.Value < 1 and not promptConfig.InfAmmo.Value then return end
	local ammoType = promptConfig.AmmoType.Value
	local tools    = player.Backpack:GetChildren()
	local equippedTool = player.Character:FindFirstChildWhichIsA("Tool")
	if equippedTool then table.insert(tools, equippedTool) end

	for _, tool in ipairs(tools) do
		if tool:FindFirstChild("SPH_Weapon") then
			local wepStats      = require(tool.SPH_Weapon.WeaponStats)
			local arcadeAmmoPool= tool.Ammo.ArcadeAmmoPool
			if wepStats.infiniteAmmo then
				continue
			elseif arcadeAmmoPool.Value < arcadeAmmoPool.MaxValue
				and (wepStats.ammoType == ammoType or ammoType == "Universal") then
				ammoTaken = true
				local ammoNeeded = arcadeAmmoPool.MaxValue - arcadeAmmoPool.Value
				if ammoPool.Value > ammoNeeded then
					arcadeAmmoPool.Value = arcadeAmmoPool.MaxValue
					ammoPool.Value -= ammoNeeded
				else
					arcadeAmmoPool.Value += ammoPool.Value
					ammoPool.Value = 0
				end
				if ammoPool.Value <= 0 and config.despawnEmptyAmmoBoxes then
					prompt.Enabled = false
					task.delay(config.ammoBoxDespawnTime, function()
						if ammoPool.Value <= 0 then
							prompt.Parent.Parent:Destroy()
						end
					end)
				end
			elseif arcadeAmmoPool.Value <= 0 then
				break
			end
		end
	end

	if ammoTaken and prompt.Parent:FindFirstChild("Ammo") then
		prompt.Parent.Ammo:Play()
	end
end

local function HandleGunGiverPrompt(prompt: Instance, player: Player)
	local promptConfig = prompt.SPH_PromptConfig
	local gunName      = prompt:GetAttribute("ToolToGive") or prompt:FindFirstChildWhichIsA("Tool").Name
	local gunPool      = promptConfig.GunPool

	if not promptConfig.AllowDupes.Value
		and (player.Character:FindFirstChild(gunName) or player.Backpack:FindFirstChild(gunName)) then
		return
	end

	if gunPool.Value > 0 or promptConfig.InfGuns.Value then
		local newGun = prompt:FindFirstChildWhichIsA("Tool")
		if not newGun then
			warn(("[GunGiver] No tool found under prompt '%s'."):format(prompt:GetFullName()))
			return
		end
		newGun        = newGun:Clone()
		newGun.Parent = player.Backpack
		gunPool.Value -= 1

		if gunPool.Value < 1 then
			prompt.Enabled = false
			local listener
			listener = gunPool.Changed:Connect(function()
				if gunPool.Value > 0 then
					listener:Disconnect()
					prompt.Enabled = true
				end
			end)
		end

		local gunModels = prompt.Parent.Parent:FindFirstChild("GunModels")
		if not promptConfig.InfGuns.Value
			and promptConfig.RemoveModels.Value
			and gunModels
			and #gunModels:GetChildren() > gunPool.Value then
			gunModels:GetChildren()[1]:Destroy()
		end

		if prompt.Parent:FindFirstChild("TakeGun") then
			prompt.Parent.TakeGun:Play()
		end
	end
end

local PROMPT_HANDLERS: { [string]: (Instance, Player) -> () } = {
	AmmoGiver = HandleAmmoGiverPrompt,
	GunGiver  = HandleGunGiverPrompt,
}

function ProximityPromptHandlers.init()
	proxPromptService.PromptTriggered:Connect(function(prompt, player)
		local handler = PROMPT_HANDLERS[prompt.Name]
		if handler and prompt:FindFirstChild("SPH_PromptConfig") then
			handler(prompt, player)
		end
	end)
end

return ProximityPromptHandlers