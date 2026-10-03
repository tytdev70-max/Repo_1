-- PlayerLifecycle
-- players.PlayerAdded, PlayerRemoving, CharacterAdded, humanoid.Died.

local ServiceRefs          = require(script.Parent.ServiceRefs)
local AssetRefs            = require(script.Parent.AssetRefs)
local Constants            = require(script.Parent.Constants)
local ServerState          = require(script.Parent.ServerState)
local ServerHelpers        = require(script.Parent.ServerHelpers)
local HolsterSystem        = require(script.Parent.HolsterSystem)
local CharacterRigSystem   = require(script.Parent.CharacterRigSystem)
local GunSetupSystem       = require(script.Parent.GunSetupSystem)
local GunDropSystem        = require(script.Parent.GunDropSystem)

local players        = ServiceRefs.players
local assets         = AssetRefs.assets
local config         = AssetRefs.config
local HitResolutionMod = AssetRefs.HitResolutionMod
local PlayerDeathMod   = AssetRefs.PlayerDeathMod
local Network          = AssetRefs.Network
local warnPrefix       = AssetRefs.warnPrefix

local pendingHolsterShows  = ServerState.pendingHolsterShows
local pendingGrenadeThrows = ServerState.pendingGrenadeThrows
local playerLeanStates     = ServerState.playerLeanStates
local shellEjectCooldowns  = ServerState.shellEjectCooldowns
local playerArmIgnoreUntil = ServerState.playerArmIgnoreUntil

local PlayerLifecycle = {}

local function CheckTool(player, tool)
	if tool:FindFirstChild("SPH_Weapon") and assets.WeaponModels:FindFirstChild(tool.Name) then
		HolsterSystem.CheckHolster(player, tool)
		local wepStats = require(tool.SPH_Weapon.WeaponStats)
		GunSetupSystem.SetupGun(tool, wepStats)
	end
end

function PlayerLifecycle.init()
	players.PlayerAdded:Connect(function(newPlayer: Player)
		local deaths
		if config.leaderboard then
			local leaderstats = newPlayer:FindFirstChild("leaderstats")
			if not leaderstats then
				leaderstats = Instance.new("Folder", newPlayer)
				leaderstats.Name = "leaderstats"
			end
			local kills = Instance.new("IntValue", leaderstats)
			kills.Name  = "K"
			deaths      = Instance.new("IntValue", leaderstats)
			deaths.Name = "D"
		end

		if not newPlayer.PlayerGui:FindFirstChild("SPH_UI") then
			local newGui = assets.HUD.GunGUIs.SPH_UI:Clone()
			newGui.Name         = "SPH_UI"
			newGui.ResetOnSpawn = false
			newGui.Parent       = newPlayer.PlayerGui
		end

		if config.deathScreen then
			if not newPlayer.PlayerGui:FindFirstChild("DeathScreen") then
				local deathGui = assets.HUD.DeathUIs.DeathScreen:Clone()
				deathGui.ResetOnSpawn = false
				deathGui.Parent       = newPlayer.PlayerGui
			end
		end

		-- Roblox creates a NEW Backpack instance on every respawn, so these hooks
		-- must be attached to each Backpack, not just the first one. Otherwise any
		-- tool given after the first death (GunGiver, pickups...) never gets its
		-- Ammo/Chambered/BoltReady/FireMode values created.
		local hookedBackpacks = setmetatable({}, { __mode = "k" })
		local function hookBackpack(backpack: Instance)
			if not backpack:IsA("Backpack") or hookedBackpacks[backpack] then return end
			hookedBackpacks[backpack] = true

			backpack.ChildAdded:Connect(function(child)
				if child:GetAttribute("SPH_Consumed") then child:Destroy() return end
				if child:FindFirstChild("SPH_Weapon") then CheckTool(newPlayer, child) end
			end)

			backpack.ChildRemoved:Connect(function(child)
				if child:FindFirstChild("SPH_Weapon") then
					HolsterSystem.RemoveHolster(newPlayer, child.Name)
				end
			end)

			-- Tools that landed before the hook existed
			for _, child in ipairs(backpack:GetChildren()) do
				if child:FindFirstChild("SPH_Weapon") then
					task.spawn(CheckTool, newPlayer, child)
				end
			end
		end

		local existingBackpack = newPlayer:FindFirstChildOfClass("Backpack")
		if existingBackpack then hookBackpack(existingBackpack) end
		newPlayer.ChildAdded:Connect(hookBackpack)

		newPlayer.CharacterAdded:Connect(function(newChar: Model)
			if not newPlayer.PlayerGui:FindFirstChild("SPH_UI") then
				local newGui = assets.HUD.GunGUIs.SPH_UI:Clone()
				newGui.Name         = "SPH_UI"
				newGui.ResetOnSpawn = false
				newGui.Parent       = newPlayer.PlayerGui
			end

			ServerHelpers.ResetPlayerGunReplicationState(newPlayer)
			local humanoid = newChar:WaitForChild("Humanoid", 20)
			local animator = humanoid:WaitForChild("Animator", 20)

			local newRig = CharacterRigSystem.MakeCharacterRig(newChar)
			humanoid.BreakJointsOnDeath = not config.ragdolls

			humanoid.Died:Connect(function()
				if not newChar:FindFirstChild("HumanoidRootPart") then return end
				ServerHelpers.ResetPlayerGunReplicationState(newPlayer)
				PlayerDeathMod.HandleDeath({
					Player          = newPlayer,
					Character       = newChar,
					Humanoid        = humanoid,
					Rig             = newRig,
					DeathsValue     = deaths,
					PendingThrow    = pendingGrenadeThrows[newPlayer],
					Shells          = ServerState.shells,
					SpawnGun        = GunDropSystem.SpawnGun,
					MakePickUpAble  = GunDropSystem.MakePickUpAble,
				})
				pendingGrenadeThrows[newPlayer] = nil
			end)

			for _, tool in ipairs(newPlayer.Backpack:GetChildren()) do
				if tool:FindFirstChild("SPH_Weapon") then
					CheckTool(newPlayer, tool)
				end
			end

			for _, part in ipairs(newChar:GetChildren()) do
				if part:IsA("BasePart") then
					if part.Name == "HumanoidRootPart" then
						part.CollisionGroup = "RootParts"
					else
						part.CollisionGroup = "Players"
					end
				end
			end

			local humanoidRootPart = newChar.HumanoidRootPart
			local soundOrigin      = Instance.new("Attachment", humanoidRootPart)
			soundOrigin.Name       = "FootstepSoundOrigin"
			soundOrigin.Position   = Vector3.new(0, -3, 0)

			local leftFoot = Instance.new("Sound", soundOrigin)
			leftFoot.Name              = "LeftFoot"
			leftFoot.Volume            = 1
			leftFoot.RollOffMode       = Enum.RollOffMode.InverseTapered
			leftFoot.RollOffMaxDistance= 100

			local rightFoot = Instance.new("Sound", soundOrigin)
			rightFoot.Name              = "RightFoot"
			rightFoot.Volume            = 1
			rightFoot.RollOffMode       = Enum.RollOffMode.InverseTapered
			rightFoot.RollOffMaxDistance= 100
		end)
	end)

	players.PlayerRemoving:Connect(function(player)

		local character = player.Character
		if config.dropOnLeave and character then
			local equippedTool = character:FindFirstChildWhichIsA("Tool")
			if equippedTool and equippedTool:FindFirstChild("SPH_Weapon") then
				GunDropSystem.SpawnGun(
					equippedTool,
					character.HumanoidRootPart.CFrame * ServerState.dropCFrame,
					player)
			end
			for _, tool in ipairs(player.Backpack:GetChildren()) do
				if tool:FindFirstChild("SPH_Weapon") then
					GunDropSystem.SpawnGun(
						tool,
						character.HumanoidRootPart.CFrame * ServerState.dropCFrame,
						player)
					task.wait()
				end
			end
		end

		HitResolutionMod.ClearPlayerShots(player)
		playerLeanStates[player]       = nil
		shellEjectCooldowns[player]    = nil
		pendingHolsterShows[player]    = nil
		pendingGrenadeThrows[player]   = nil
		playerArmIgnoreUntil[player]   = nil
		ServerHelpers.ResetPlayerGunReplicationState(player)
	end)
end

return PlayerLifecycle