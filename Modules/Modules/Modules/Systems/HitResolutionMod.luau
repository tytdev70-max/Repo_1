-- // Services
local replicatedStorage = game:GetService("ReplicatedStorage")
local players           = game:GetService("Players")
local collectionService = game:GetService("CollectionService")
local debris            = game:GetService("Debris")

-- // Assets & Modules
local assets  = replicatedStorage:WaitForChild("SPH_Assets")
local modules = assets.Modules
local config  = require(assets.GameConfig)

local NetworkRangeUtil  = require(modules.Core.Networking.NetworkRangeUtil)
local Network           = require(modules.Core.Networking.SPH_Network)
local MaterialCodec     = require(modules.Core.Networking.MaterialCodec)
local glassShatterMod   = require(modules.Effects.Environment.GlassShatterMod)
local objectDestruction = require(modules.Effects.Environment.ObjectDestruction)
local damageFalloff     = require(modules.Weapons.Core.DamageFalloff)
local explosionMod      = require(modules.Effects.Explosions.ExplosionFX)
local ubglHandler       = require(modules.Weapons.Attachments.UBGLSystemMod)
local SPH_Events        = require(modules.Core.Networking.SPH_Events)

local npcHitEvent = SPH_Events.Get("CombatEvents", "NPC_HitEvent")

local warnPrefix = "[Open-Ballistics] "

local HitResolutionMod = {}

-- // Shot Dedup State
local processedShots = {}

-- // Team Kill Check
local function TeamKillCheck(player1: Player, player2: Player)
	if not config.teamKill and not player1.Neutral and not player2.Neutral then
		if player1.Team == player2.Team then
			return false
		end
	end
	return true
end

-- // Bullet Force
local function applyBulletForce(hitPart, bulletCFrame, forceAmount, shooterPlayer, humanoid, hitPosition)
	if not hitPart or not hitPart:IsA("BasePart") then return end

	task.delay(0.01, function()
		if hitPart and hitPart.Parent and not hitPart.Anchored then
			if not humanoid or humanoid.Health <= 0 then
				if humanoid and humanoid.Health <= 0 then
					local direction = bulletCFrame.LookVector.Unit
					local velocity = direction * math.clamp(forceAmount * 0.1, 1.5, 12)
					local bodyVel = Instance.new("BodyVelocity")
					bodyVel.MaxForce = Vector3.new(1e9, 1e9, 1e9)
					bodyVel.Velocity = velocity
					bodyVel.Name = "BulletImpulse"
					bodyVel.Parent = hitPart
					debris:AddItem(bodyVel, 0.1)
				else
					local tempAtt = Instance.new("Attachment", hitPart)
					tempAtt.WorldCFrame = CFrame.new(hitPosition) * (bulletCFrame - bulletCFrame.Position)
					local vectorForce = Instance.new("VectorForce", tempAtt)
					vectorForce.Attachment0 = tempAtt
					vectorForce.Force = Vector3.new(0, 0, -forceAmount)
					debris:AddItem(tempAtt, 0.1)
					local isPlayerCharacter = hitPart:FindFirstAncestorWhichIsA("Model") and players:GetPlayerFromCharacter(hitPart:FindFirstAncestorWhichIsA("Model"))
					if not isPlayerCharacter then
						pcall(function()
							hitPart:SetNetworkOwner(shooterPlayer)
						end)
					end
				end
			end
		end
	end)
end

-- // Bullet Hit Handler
function HitResolutionMod.HandleBulletHit(Data, player: Player)
	if Data.BulletId then
		local shotKey = player.UserId .. "_" .. tostring(Data.BulletId) .. "_" .. tostring(Data.HitIndex or 1)
		if processedShots[shotKey] then
			return
		end
		processedShots[shotKey] = true
		task.delay(5, function()
			processedShots[shotKey] = nil
		end)
	end

	local tool = Data.Tool
	if Data.TurretModel then
		tool = { model = Data.TurretModel, index = Data.TurretIndex }
	end
	local bulletCFrame = Data.BulletCFrame
	local bloodParams = Data.BloodParams
	local isUBGL = Data.IsUBGL
	local raycastResult = {
		Position = Data.RaycastPosition,
		Normal = Data.RaycastNormal,
		Instance = Data.RaycastInstance,
		Material = MaterialCodec.Decode(Data.RaycastMaterial),
	}

	if not tool then
		return
	elseif tool and typeof(tool) ~= "Instance" then
		warn(warnPrefix .. player.Name .. " attempted to call bulletHit without a tool.")
		return
	elseif tool.Parent ~= player.Character and tool.Parent ~= player.Backpack then
		if tool.Parent ~= nil then
			local shooterHumanoid = player.Character and player.Character:FindFirstChild("Humanoid")
			if not shooterHumanoid or shooterHumanoid.Health > 0 then
				return
			end
		end
	end

	local wepStats
	if typeof(tool) == "table" then
		wepStats = require(tool.model.Parent.TurretModule).guns[tool.index]
	elseif tool:IsA("Tool") then
		wepStats = require(tool.SPH_Weapon.WeaponStats)
	end

	if isUBGL and wepStats.UBGL then
		ubglHandler.Explode(raycastResult.Position, player, tool)
		return
	end

	if wepStats.explosiveAmmo then
		explosionMod(raycastResult.Position, wepStats.explosionRadius, wepStats.explosionEffect, player)
	else
		local position = raycastResult.Position
		local targets = NetworkRangeUtil.GetPlayersInRange(position, config.maxHitDistance, player)
		Network.packets.ReplicateHit.sendToList({
			Tool = tool,
			RaycastPosition = raycastResult.Position,
			RaycastNormal = raycastResult.Normal,
			RaycastInstance = raycastResult.Instance,
			RaycastMaterial = MaterialCodec.Encode(raycastResult.Material),
			BloodParams = bloodParams,
		}, targets)
	end

	local hitPart: BasePart = raycastResult.Instance
	if not hitPart or not hitPart.Parent then return end
	local humanoid: Humanoid = hitPart.Parent:FindFirstChildWhichIsA("Humanoid")
	local otherPlayer
	if humanoid then otherPlayer = players:GetPlayerFromCharacter(humanoid.Parent) end
	local damage = wepStats.damage[hitPart.Name] or wepStats.damage.Other

	local shooterRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	local straightLineDistance = shooterRoot and (raycastResult.Position - shooterRoot.Position).Magnitude or 0
	local travelDistance = damageFalloff.ResolveDistance(Data.TravelDistance, straightLineDistance)
	damage = damageFalloff.Apply(damage, wepStats.damageFalloff, travelDistance)

	if humanoid and humanoid.Health > 0 and ((otherPlayer and TeamKillCheck(player, otherPlayer)) or not otherPlayer) then
		if humanoid.Health > 0 and humanoid.Health - damage <= 0 then
			if config.leaderboard then player.leaderstats.K.Value += 1 end
			local killer = Instance.new("ObjectValue", humanoid.Parent)
			killer.Name = "Killer"
			killer.Value = player
			if player and otherPlayer then
				print(warnPrefix .. " " .. player.Name .. " killed " .. otherPlayer.Name)
			end
		end

		local creator = Instance.new("ObjectValue")
		creator.Name = "creator"
		creator.Value = player
		creator.Parent = humanoid
		debris:AddItem(creator, 0.5)
		local npcFolder = workspace:FindFirstChild("NPCS")
		if npcFolder and humanoid and humanoid.Parent and humanoid.Parent:IsDescendantOf(npcFolder) then
			npcHitEvent:Fire(humanoid.Parent, player, hitPart.Name, damage)
		end
		humanoid:TakeDamage(damage)
	elseif glassShatterMod.IsGlass(hitPart) and config.glassShatter and not hitPart:GetAttribute("Shattered") then
		glassShatterMod.Shatter(hitPart, raycastResult.Position, bulletCFrame.LookVector * 10)
	end

	local hitObject: Instance
	local isGlass = hitPart.Name == "Glass" or collectionService:HasTag(hitPart, "BreakableGlass")
	if not isGlass then
		if hitPart.Parent:HasTag("SPH_Destructible") then
			hitObject = hitPart.Parent
		elseif hitPart:HasTag("SPH_Destructible") then
			hitObject = hitPart
		end
	end
	if hitObject and not hitObject:GetAttribute("Destroyed") then
		local objectHealth = hitObject:GetAttribute("HP")
		hitObject:SetAttribute("HP", objectHealth - damage)
		objectHealth -= damage
		if objectHealth <= 0 then
			objectDestruction.DestroyObject(hitObject)
		end
	end

	if config.useBulletForce then
		applyBulletForce(hitPart, bulletCFrame, wepStats.bulletForce or 20, player, humanoid, raycastResult.Position)
	end
end

-- // Per-Player Cleanup
function HitResolutionMod.ClearPlayerShots(player: Player)
	for key in pairs(processedShots) do
		if key:match("^" .. player.UserId .. "_") then
			processedShots[key] = nil
		end
	end
end

return HitResolutionMod