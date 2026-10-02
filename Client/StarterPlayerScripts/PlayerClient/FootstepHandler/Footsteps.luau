--!strict

local ReplicatedStorage: ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService: RunService = game:GetService("RunService")
local Players: Players = game:GetService("Players")

local assets: any = ReplicatedStorage.SPH_Assets
local Config: any = require(assets.GameConfig)
local Network: any = require(assets.Modules.Core.Networking.SPH_Network)
local MaterialCodec: any = require(assets.Modules.Core.Networking.MaterialCodec)

--// Player & Character State

local player: Player = Players.LocalPlayer
local character: Model? = nil

local leftFoot: Sound?, rightFoot: Sound?, stepLeftFoot: boolean?, humanoidRootPart: BasePart?, humanoid: Humanoid?

--// Footstep Tuning

local BASE_SPEED_REF: number = 10
local MIN_STRIDE: number = 1.0
local MAX_STRIDE: number = 4.0
local lastPosition: Vector3? = nil

--// Sound Sets

local soundSets: any = assets.Sounds.WalkSounds
local defaultSoundSet: any = soundSets.Concrete

local MATERIAL_SOUND_GROUPS: { [string]: { string } } = {
	Metal = { "Metal", "CorrodedMetal", "DiamondPlate", "Neon" },
	Grass = { "Grass", "LeafyGrass" },
	Ground = { "Ground", "Glacier", "Pebble", "Salt" },
	Sand = { "Sand", "Fabric", "Snow" },
	Mud = { "Mud" },
	Wood = { "Wood", "WoodPlanks" },
}

local materialSounds: { [string]: any } = {}
for setName, materialNames in pairs(MATERIAL_SOUND_GROUPS) do
	local soundSet = soundSets:FindFirstChild(setName)
	if soundSet then
		for _, materialName in ipairs(materialNames) do
			materialSounds[materialName] = soundSet
		end
	else
		warn("[Footsteps] Missing sound set folder: " .. setName)
	end
end

--// Sound Playback

local cachedSoundChildren: { [any]: { Sound } } = {}

local function GetSoundChildren(soundSet: any): { Sound }
	local cached = cachedSoundChildren[soundSet]
	if not cached then
		cached = soundSet:GetChildren()
		cachedSoundChildren[soundSet] = cached
	end
	return cached
end

local function GetSound(materialName: string): (string, number)
	local soundSet: any = materialSounds[materialName] or defaultSoundSet
	local sounds = GetSoundChildren(soundSet)
	local randomSound: any = sounds[math.random(#sounds)]
	return randomSound.SoundId, randomSound.PlaybackSpeed
end

local function Footstep(material: Enum.Material, foot: Sound?, volume: number?): ()
	if not foot or not foot.Parent then
		return
	end

	local newId: string, playSpeed: number = GetSound(material.Name)
	foot.SoundId = newId
	foot.PlaybackSpeed = playSpeed + (math.random(-100, 100) / 1000)
	foot.Volume = volume or 0.4
	foot:Play()
end

--// Foot References

local function ensureFeet(): ()
	if not humanoidRootPart then
		return
	end

	local soundOrigin: Instance? = humanoidRootPart:WaitForChild("FootstepSoundOrigin", 5)
	if not soundOrigin then
		return
	end

	leftFoot = (soundOrigin:FindFirstChild("LeftFoot") :: Sound?) or leftFoot
	rightFoot = (soundOrigin:FindFirstChild("RightFoot") :: Sound?) or rightFoot
end

--// Default Footstep Sound Removal

local function StripDefaultFootsteps(hrp: BasePart?): ()
	if not hrp then
		return
	end

	local existing: Instance? = hrp:FindFirstChild("Running")
	if existing then
		existing:Destroy()
	end

	hrp.ChildAdded:Connect(function(child: Instance)
		if child.Name == "Running" and child:IsA("Sound") then
			child:Destroy()
		end
	end)
end

local function OnCharacterAdded(char: Model): ()
	local hrp: BasePart? = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	StripDefaultFootsteps(hrp)
end

local function OnPlayerAdded(plr: Player): ()
	if plr.Character then
		OnCharacterAdded(plr.Character)
	end
	plr.CharacterAdded:Connect(OnCharacterAdded)
end

for _, plr: Player in ipairs(Players:GetPlayers()) do
	OnPlayerAdded(plr)
end
Players.PlayerAdded:Connect(OnPlayerAdded)

--// Local Character Setup

local function SetupSoundsForCharacter(newCharacter: Model): ()
	character = newCharacter

	humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoidRootPart = character:WaitForChild("HumanoidRootPart") :: BasePart

	local soundOrigin: Instance = humanoidRootPart:WaitForChild("FootstepSoundOrigin", 5) :: Instance
	leftFoot = soundOrigin:WaitForChild("LeftFoot", 5) :: Sound
	rightFoot = soundOrigin:WaitForChild("RightFoot", 5) :: Sound

	stepLeftFoot = true
	lastPosition = humanoidRootPart.Position
end

if player.Character then
	SetupSoundsForCharacter(player.Character)
end
player.CharacterAdded:Connect(SetupSoundsForCharacter)

--// Remote Footstep Replication

Network.packets.FootstepReplicate.listen(function(Data: any): ()
	if Data.Player == player then
		return
	end

	local foot: Sound? = Data.Foot
	if not foot or not foot.Parent then
		return
	end

	local material: Enum.Material = MaterialCodec.Decode(Data.MaterialCode)
	foot.Volume = Data.Volume or foot.Volume
	Footstep(material, foot, Data.Volume)
end)

--// Grounded Check

local function IsGrounded(hum: Humanoid?): boolean
	if not hum or hum.Health <= 0 then
		return false
	end

	if hum.FloorMaterial == Enum.Material.Air then
		return false
	end

	local state: Enum.HumanoidStateType = hum:GetState()
	if state == Enum.HumanoidStateType.Freefall
		or state == Enum.HumanoidStateType.Jumping
		or state == Enum.HumanoidStateType.FallingDown
		or state == Enum.HumanoidStateType.Seated
		or state == Enum.HumanoidStateType.Swimming then
		return false
	end

	return true
end

--// Local Footstep Loop

if Config.footstepSounds then
	RunService.Heartbeat:Connect(function(dt: number): ()
		if not humanoid or not humanoidRootPart or humanoid.Health <= 0 then
			return
		end

		ensureFeet()

		local velMag: number = humanoidRootPart.AssemblyLinearVelocity.Magnitude
		if velMag < (humanoid.WalkSpeed * 0.1) then
			lastPosition = humanoidRootPart.Position
			return
		end

		if not IsGrounded(humanoid) then
			lastPosition = humanoidRootPart.Position
			return
		end

		local stride: number = math.clamp(humanoid.WalkSpeed * 0.45, MIN_STRIDE, MAX_STRIDE)

		if lastPosition == nil then
			lastPosition = humanoidRootPart.Position
		end

		local curPos2: Vector3 = Vector3.new(humanoidRootPart.Position.X, 0, humanoidRootPart.Position.Z)
		local lastPos2: Vector3 = Vector3.new((lastPosition :: Vector3).X, 0, (lastPosition :: Vector3).Z)
		local moved: number = (curPos2 - lastPos2).Magnitude

		if moved >= stride then
			local curFoot: Sound? = rightFoot
			if stepLeftFoot then
				curFoot = leftFoot
			end
			stepLeftFoot = not stepLeftFoot

			if not curFoot or not curFoot.Parent then
				ensureFeet()
				if stepLeftFoot then
					curFoot = leftFoot
				else
					curFoot = rightFoot
				end
			end

			if not curFoot then
				lastPosition = humanoidRootPart.Position
				return
			end

			local volume: number = math.clamp(0.4 * (velMag / BASE_SPEED_REF), 0.12, 1)

			Footstep(humanoid.FloorMaterial, curFoot, volume)
			Network.packets.FootstepRequest.send({
				MaterialCode = MaterialCodec.Encode(humanoid.FloorMaterial),
				Foot = curFoot,
				Volume = volume,
			})

			lastPosition = humanoidRootPart.Position
		end
	end)
end

return true