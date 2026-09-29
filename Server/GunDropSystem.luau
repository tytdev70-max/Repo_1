-- GunDropSystem
-- SpawnGun, MakePickUpAble, DropGun.

local ServiceRefs    = require(script.Parent.ServiceRefs)
local AssetRefs      = require(script.Parent.AssetRefs)
local Constants      = require(script.Parent.Constants)
local ServerState    = require(script.Parent.ServerState)
local GunSetupSystem = require(script.Parent.GunSetupSystem)

local assets            = AssetRefs.assets
local weldMod           = AssetRefs.weldMod
local attachmentSystem = AssetRefs.attachmentSystem
local config            = AssetRefs.config
local proxPromptService = ServiceRefs.proxPromptService

local dropTable    = ServerState.dropTable
local dropCFrame   = ServerState.dropCFrame

local GunDropSystem = {}

function GunDropSystem.MakePickUpAble(tool, model, mainPart)
	tool.Parent = model
	model.Name  = tool.Name

	local proxPrompt = Instance.new("ProximityPrompt")
	proxPrompt.MaxActivationDistance = config.pickupDistance
	proxPrompt.Style                 = Enum.ProximityPromptStyle.Custom
	proxPrompt.RequiresLineOfSight   = false
	proxPrompt.KeyboardKeyCode       = config.pickupKey[1]
	proxPrompt.HoldDuration          = 0
	proxPrompt.Parent                = mainPart

	local promptListener
	promptListener = proxPrompt.Triggered:Connect(function(player)
		if player.Character.Humanoid.Health <= 0 then return else promptListener:Disconnect() end
		tool.Parent = player.Backpack
		model:Destroy()
		local newSound = assets.Sounds.Misc.WeaponPickup:Clone()
		newSound.Parent = player.Character.HumanoidRootPart
		newSound:Play()
		newSound.PlayOnRemove = true
		newSound:Destroy()
	end)

	local highlight = Instance.new("Highlight")
	highlight.Name               = "PickupHighlight"
	highlight.FillTransparency   = 0.4
	highlight.OutlineTransparency= 0.15
	highlight.OutlineColor       = Color3.new(1, 1, 1)
	highlight.FillColor          = Color3.new(0.584314, 0.584314, 0.584314)
	highlight.Parent             = model
	highlight.Enabled            = false
end

function GunDropSystem.SpawnGun(tool, gunPosition, dropPlayer)
	local wepStats   = require(tool.SPH_Weapon.WeaponStats)
	local dropModel  = assets.WeaponModels:FindFirstChild(tool.Name)
	if not dropModel then return end
	dropModel = dropModel:Clone()
	dropModel.Grip.Anchored  = false
	dropModel.Grip.CanTouch  = true

	task.delay(config.dropGunAnchorTime, function()
		for _, desc in dropModel:GetDescendants() do
			if desc:IsA("BasePart") then
				desc.Anchored    = true
				desc.CanCollide  = false
			end
		end
	end)

	dropModel.PrimaryPart    = dropModel.Grip
	dropModel.Grip.Size      = dropModel:GetExtentsSize()
	if #dropModel:GetChildren() < 2 then
		dropModel.Grip.CanCollide = true
	else
		dropModel.Grip.CanCollide = false
	end

	local fireMoveParts = {}
	if wepStats.fireMoveParts then
		for _, name in ipairs(wepStats.fireMoveParts) do
			fireMoveParts[name] = true
		end
	end
	local boltWelds = {}

	for _, part in ipairs(dropModel:GetDescendants()) do
		if part:IsA("BasePart") then
			if string.find(part.Name, "AimPart") then
				part:Destroy()
			elseif part.Name ~= "Grip" then
				local newWeld       = weldMod.Weld(dropModel.Grip, part)
				newWeld.Parent      = dropModel.Grip
				part.Anchored       = false
				part.CanCollide     = true
				part.CanTouch       = false
				part.CollisionGroup = "Guns"
				if fireMoveParts[part.Name] then
					boltWelds[part.Name] = newWeld
				end
			end
		end
	end

	local boltReadyVal = tool:FindFirstChild("BoltReady")
	if boltReadyVal and wepStats.boltDist and next(boltWelds) then
		local function ApplyBoltWeldState()
			local locked = not boltReadyVal.Value
			for _, weld in pairs(boltWelds) do
				weld.C1 = locked and wepStats.boltDist or CFrame.new()
			end
		end
		ApplyBoltWeldState()
		local boltConn
		boltConn = boltReadyVal.Changed:Connect(ApplyBoltWeldState)
		dropModel.Destroying:Connect(function()
			if boltConn then boltConn:Disconnect(); boltConn = nil end
		end)
	end

	if not tool then
		warn("[SpawnGun] No tool instance provided for dropped gun '" .. tostring(dropModel.Name) .. "'.")
		dropModel:Destroy()
		return
	end

	GunDropSystem.MakePickUpAble(tool, dropModel, dropModel.Grip)

	-- Keep the dropped gun's attachments, so a picked-up weapon looks the same
	-- as it did when it left the previous owner's hands.
	local _fitted, failed = attachmentSystem.ApplySavedLoadout(nil, tool, dropModel)
	if failed and failed > 0 then
		warn(string.format("[Server] %d attachment(s) failed to preserve on dropped gun",
			failed))
	end

	local projectile    = dropModel:FindFirstChild(wepStats.projectile)
	local chamberedVal  = tool:FindFirstChild("Chambered")
	if (wepStats.openBolt or not (chamberedVal and chamberedVal.Value))
		and projectile
		and wepStats.projectile ~= "Bullet"
		and projectile.Name ~= "Mag" then
		projectile.Transparency = 1
		for _, child in ipairs(projectile:GetDescendants()) do
			if child:IsA("BasePart") then child.Transparency = 1 end
		end
	end

	dropModel.Parent = ServerState.drops
	dropModel.Grip.Touched:Connect(function()
		if dropModel.Grip.AssemblyLinearVelocity.Magnitude > 7 then
			local DropSounds = assets.Sounds.GunDrop
			local NewSound   = DropSounds["GunDrop" .. math.random(#DropSounds:GetChildren())]:Clone()
			NewSound.Parent        = dropModel.Grip
			NewSound.PlaybackSpeed = math.random(30, 50) / 40
			NewSound:Play()
			NewSound.PlayOnRemove  = true
			NewSound:Destroy()
		end
	end)

	if dropPlayer then dropModel.Grip:SetNetworkOwner(dropPlayer) end
	dropModel:SetPrimaryPartCFrame(gunPosition)

	local position = #dropTable + 1
	table.insert(dropTable, position, dropModel)
	if #dropTable > config.maxDroppedGuns then
		local objectToDestroy = dropTable[1]
		table.remove(dropTable, 1)
		objectToDestroy:Destroy()
	end
	task.delay(config.dropDespawnTime, function()
		table.remove(dropTable, position)
		dropModel:Destroy()
	end)

	return dropModel
end

function GunDropSystem.DropGun(player, tool)
	if not tool then tool = player.Character:FindFirstChildWhichIsA("Tool") end
	if not config.gunDropping then return end
	if tool and tool:FindFirstChild("SPH_Weapon") then
		GunDropSystem.SpawnGun(tool, player.Character.HumanoidRootPart.CFrame * dropCFrame, player)
	else
		return
	end
	local newSound = assets.Sounds.Misc.WeaponDrop:Clone()
	newSound.Parent = player.Character.HumanoidRootPart
	newSound:Play()
	newSound.PlayOnRemove = true
	newSound:Destroy()
end

return GunDropSystem