--!strict

-- Fully server-authoritative ragdoll system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris            = game:GetService("Debris")
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")

local Config        = require(ReplicatedStorage.SPH_Assets.GameConfig) :: any

local SPH_Assets    = ReplicatedStorage:WaitForChild("SPH_Assets") :: Folder
local ContentFolder = SPH_Assets:WaitForChild("RagdollContent") :: Folder
local SoundsFolder  = SPH_Assets:WaitForChild("Sounds") :: Folder
local RagdollSounds = SoundsFolder:WaitForChild("RagdollSounds") :: Folder
local DeathEvents   = SPH_Assets:WaitForChild("Events"):WaitForChild("DeathEvents") :: Folder
local RagdollEvent  = DeathEvents:WaitForChild("RagdollEvent") :: RemoteEvent
local UnragdollEvent= DeathEvents:WaitForChild("UnragdollEvent") :: RemoteEvent

local RagdollServerMod = {}

local BODIES_GROUP       = "Bodies"
local RAGDOLL_LIFETIME   = tonumber(Config.ragdollLifetime)
if RAGDOLL_LIFETIME == nil then
	RAGDOLL_LIFETIME = 12
end
if RAGDOLL_LIFETIME < 0 then
	RAGDOLL_LIFETIME = 0
end

-- Impact-sound tuning
local IMPACT_MIN_SPEED   = 5      -- studs/sec, below this we ignore the touch
local IMPACT_GLOBAL_CD   = 0.08   -- per-corpse cooldown
local IMPACT_PART_CD     = 0.2    -- per-part cooldown
local IMPACT_VOLUME_MIN  = 0.25
local IMPACT_VOLUME_MAX  = 1.0
local IMPACT_VOLUME_REF  = 40     -- speed at which volume saturates

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

local function SetCustomPhysicalProperties(part: BasePart?, density: number?, friction: number?, elasticity: number?, frictionWeight: number?, elasticityWeight: number?)
	if not part then return end
	part.CustomPhysicalProperties = PhysicalProperties.new(
		density or 0.35,
		friction or 1,
		frictionWeight or 1,
		elasticity or 0.3,
		elasticityWeight or 0.5
	)
end

local function ForceBodiesGroup(part: BasePart?)
	if part and part:IsA("BasePart") then
		part.CollisionGroup = BODIES_GROUP
	end
end

local function SweepBodiesGroup(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") and descendant.CollisionGroup ~= BODIES_GROUP then
			descendant.CollisionGroup = BODIES_GROUP
		end
	end
end

local function NoCollide(a: BasePart?, b: BasePart?)
	if not a or not b then return end
	local ncc = Instance.new("NoCollisionConstraint")
	ncc.Name   = a.Name .. "_NCC_" .. b.Name
	ncc.Part0  = a
	ncc.Part1  = b
	ncc.Enabled = true
	ncc.Parent = a
end

local function CreateAttachment(parent: Instance, name: string, position: Vector3, orientation: Vector3?): Attachment
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position
	if orientation then attachment.Orientation = orientation end
	attachment.Parent = parent
	return attachment
end

local function CreateBallSocket(parent: Instance, name: string, a0: Attachment, a1: Attachment, upperAngle: number, twistUpper: number, twistLower: number, maxFriction: number): BallSocketConstraint
	local socket = Instance.new("BallSocketConstraint")
	socket.Name = name
	socket.Attachment0 = a0
	socket.Attachment1 = a1
	socket.Enabled = true
	socket.LimitsEnabled = true
	socket.UpperAngle = upperAngle
	socket.TwistLimitsEnabled = true
	socket.TwistUpperAngle = twistUpper
	socket.TwistLowerAngle = twistLower
	socket.Restitution = 0
	socket.MaxFrictionTorque = maxFriction
	socket.Parent = parent
	return socket
end

-- ---------------------------------------------------------------------------
-- Collider / Knee construction
-- ---------------------------------------------------------------------------

local function FetchColliderPart(limb: BasePart?, partName: string): BasePart?
	if not limb then return nil end
	local existing = limb:FindFirstChild("ColliderPart")
	if existing then return existing :: BasePart end
	local template = ContentFolder:FindFirstChild(partName)
	if not template then return nil end

	local collider = template:Clone() :: BasePart
	collider.Name             = "ColliderPart"
	collider.Transparency     = 1
	collider.CanCollide       = false
	collider.CanQuery         = false
	collider.CanTouch         = true
	collider.Anchored         = false
	collider.Massless         = true
	collider.CollisionGroup   = BODIES_GROUP
	collider.CFrame           = limb.CFrame
	collider.Parent           = limb

	local weld = Instance.new("Weld")
	weld.Part0 = limb
	weld.Part1 = collider
	weld.C1    = (partName == "Head") and CFrame.new(0, -0.2, 0) or CFrame.new()
	weld.Parent = collider

	return collider
end

local function SetupKnee(character: Model, torso: BasePart, leg: BasePart, kneeName: string, upperName: string, lowerName: string, legAttachName: string, torsoLegAttachment: Attachment)
	local kneeTemplate = ContentFolder:FindFirstChild(kneeName)
	if not kneeTemplate then return nil, nil, nil, nil end

	local kneePart = kneeTemplate:Clone() :: BasePart
	kneePart.Name            = kneeName
	kneePart.CollisionGroup  = BODIES_GROUP
	kneePart.CanCollide      = false
	kneePart.CanQuery        = false
	kneePart.CanTouch        = false
	kneePart.Anchored        = false
	kneePart.Transparency    = 1
	kneePart.CFrame          = torso.CFrame * CFrame.new(torsoLegAttachment.Position)
	kneePart.Parent          = character

	local upperAttachment = kneePart:FindFirstChild(upperName) :: Attachment?
	local lowerAttachment = kneePart:FindFirstChild(lowerName) :: Attachment?
	if not upperAttachment or not lowerAttachment then
		kneePart:Destroy()
		return nil, nil, nil, nil
	end

	local legAttachment = Instance.new("Attachment")
	legAttachment.Name = legAttachName
	legAttachment.Position = Vector3.zero
	legAttachment.Parent = leg

	return kneePart, upperAttachment, lowerAttachment, legAttachment
end

-- ---------------------------------------------------------------------------
-- Rig construction
-- ---------------------------------------------------------------------------

local function SetupRagdoll(character: Model, colliderCache: {[BasePart]: BasePart?})
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.RigType ~= Enum.HumanoidRigType.R6 then return false end

	local torso    = character:FindFirstChild("Torso")       :: BasePart?
	local head     = character:FindFirstChild("Head")        :: BasePart?
	local leftArm  = character:FindFirstChild("Left Arm")    :: BasePart?
	local rightArm = character:FindFirstChild("Right Arm")   :: BasePart?
	local leftLeg  = character:FindFirstChild("Left Leg")    :: BasePart?
	local rightLeg = character:FindFirstChild("Right Leg")   :: BasePart?
	local root     = character:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not (torso and head and leftArm and rightArm and leftLeg and rightLeg and root) then
		return false
	end

	local torsoLeftArmA  = CreateAttachment(torso, "TorsoLeftArmA",  Vector3.new(-1, 1, 0), Vector3.new(0, 0, 180))
	local torsoRightArmA = CreateAttachment(torso, "TorsoRightArmA", Vector3.new(1, 1, 0))
	local torsoHeadA     = CreateAttachment(torso, "RagdollAttachment", Vector3.new(0, 1, 0))
	local torsoRightLegA = CreateAttachment(torso, "TorsoRightLegA", Vector3.new(0.5, -1, 0))
	local torsoLeftLegA  = CreateAttachment(torso, "TorsoLeftLegA",  Vector3.new(-0.5, -1, 0))
	local torsoRootA     = CreateAttachment(torso, "TorsoRootA", Vector3.zero)
	local rootA          = CreateAttachment(root,  "RootA", Vector3.zero)
	local leftArmA       = CreateAttachment(leftArm,  "RagdollAttachment", Vector3.new(0.5, 1, 0))
	local rightArmA      = CreateAttachment(rightArm, "RagdollAttachment", Vector3.new(-0.5, 1, 0))
	local headA          = CreateAttachment(head,     "RagdollAttachment", Vector3.new(0, -0.5, 0))

	local rightKnee, rk, rkk, rightLegAttach = SetupKnee(character, torso, rightLeg, "RightKnee", "RK",  "RKK", "Right Leg", torsoRightLegA)
	local leftKnee,  lk, lkk, leftLegAttach  = SetupKnee(character, torso, leftLeg,  "LeftKnee",  "LK",  "LKK", "Left Leg",  torsoLeftLegA)

	CreateBallSocket(torso, "HeadBSC",     headA,             torsoHeadA,     45,  90,   -90,  0.8)
	CreateBallSocket(torso, "LeftArmBSC",  torsoLeftArmA,     leftArmA,       180, 180,  -180, 0)
	CreateBallSocket(torso, "RightArmBSC", torsoRightArmA,    rightArmA,      180, 180,  -180, 0)

	if rightKnee and rk and rkk and rightLegAttach then
		CreateBallSocket(torso,    "RLball",  torsoRightLegA, rk,  60, 75, -45, 0)
		CreateBallSocket(rightKnee,"RLBALL",  rkk,            rightLegAttach, 0, 0, -65, 0)
	end
	if leftKnee and lk and lkk and leftLegAttach then
		CreateBallSocket(torso,   "LLball",  torsoLeftLegA, lk, 60, 75, -45, 0)
		CreateBallSocket(leftKnee,"LLBALL",  lkk,           leftLegAttach, 0, 0, -65, 0)
	end

	CreateBallSocket(root, "RootBSC", rootA, torsoRootA, 0, 0, 0, 0)

	local function colliderOf(part: BasePart?): BasePart?
		if not part then return nil end
		return (part :: any):FindFirstChild("ColliderPart") :: BasePart?
	end

	local torsoCollider  = colliderOf(torso)
	local headCollider   = colliderOf(head)
	local lArmCollider   = colliderOf(leftArm)
	local rArmCollider   = colliderOf(rightArm)
	local lLegCollider   = colliderOf(leftLeg)
	local rLegCollider   = colliderOf(rightLeg)

	if torsoCollider and headCollider then NoCollide(torsoCollider, headCollider) end
	if torsoCollider and lArmCollider then NoCollide(torsoCollider, lArmCollider) end
	if torsoCollider and rArmCollider then NoCollide(torsoCollider, rArmCollider) end
	if torsoCollider and lLegCollider then NoCollide(torsoCollider, lLegCollider) end
	if torsoCollider and rLegCollider then NoCollide(torsoCollider, rLegCollider) end
	if lArmCollider and rArmCollider then NoCollide(lArmCollider, rArmCollider) end
	if lLegCollider and rLegCollider then NoCollide(lLegCollider, rLegCollider) end

	return true
end

-- ---------------------------------------------------------------------------
-- Impact sounds
-- ---------------------------------------------------------------------------

local function PlayImpactSoundOnPart(part: BasePart, speed: number)
	if not part or not part.Parent then return end
	if speed < IMPACT_MIN_SPEED then return end

	local lastPart = part:GetAttribute("SPH_LastImpactSound")
	local now = os.clock()
	if lastPart and (now - lastPart) < IMPACT_PART_CD then return end
	part:SetAttribute("SPH_LastImpactSound", now)

	local ragdoll = part:FindFirstAncestorWhichIsA("Model")
	if ragdoll then
		local lastCorpse = ragdoll:GetAttribute("SPH_LastImpactSound")
		if lastCorpse and (now - lastCorpse) < IMPACT_GLOBAL_CD then return end
		ragdoll:SetAttribute("SPH_LastImpactSound", now)
	end

	local sounds = RagdollSounds:GetChildren()
	if #sounds == 0 then return end

	local template = sounds[math.random(1, #sounds)]
	if not template:IsA("Sound") then return end

	local snd = template:Clone()
	local t   = math.clamp(speed / IMPACT_VOLUME_REF, 0, 1)
	snd.Volume         = IMPACT_VOLUME_MIN + (IMPACT_VOLUME_MAX - IMPACT_VOLUME_MIN) * t
	snd.PlaybackSpeed  = 0.9 + math.random() * 0.2
	snd.Parent         = part
	snd:Play()
	Debris:AddItem(snd, math.max(1, snd.TimeLength + 0.25))
end

local function HookImpactSounds(root: Instance)
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("BasePart") then
			local part = descendant
			part.Touched:Connect(function(other)
				if not other or not other:IsA("BasePart") then return end
				if other:IsDescendantOf(root) then return end
				if other.CollisionGroup == BODIES_GROUP then return end
				local speed = part.AssemblyLinearVelocity.Magnitude
				if speed < IMPACT_MIN_SPEED then
					speed = other.AssemblyLinearVelocity.Magnitude
				end
				PlayImpactSoundOnPart(part, speed)
			end)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Activation
-- ---------------------------------------------------------------------------

local function RagdollCharacter(character: Model, ownerOverride: Player?)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root     = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then return end

	local owner = ownerOverride or Players:GetPlayerFromCharacter(character)

	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("Motor6D") and descendant.Parent and descendant.Parent.Parent == character then
			descendant.Enabled = false
		end
	end

	for _, limbName in ipairs({ "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
		local limb = character:FindFirstChild(limbName) :: BasePart?
		if limb then
			local collider = limb:FindFirstChild("ColliderPart") :: BasePart?
			if collider then
				collider.CanCollide = true
			end
			limb.CanCollide = false
		end
	end

	local torso = character:FindFirstChild("Torso") :: BasePart?
	local head  = character:FindFirstChild("Head")  :: BasePart?
	if torso then torso.CanCollide = false end
	if head  then head.CanCollide  = false end

	if root then
		root.CanCollide = false
		root.CanQuery   = false
		root.CanTouch   = false
		root.Transparency = 1
	end

	humanoid.WalkSpeed  = 0
	humanoid.AutoRotate = false
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	humanoid.PlatformStand = true

	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("BodyMover") then obj:Destroy() end
	end

	if owner then
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				pcall(function() part:SetNetworkOwner(owner) end)
			end
		end
	else
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				pcall(function() part:SetNetworkOwner(nil) end)
			end
		end
	end

	SweepBodiesGroup(character)

	HookImpactSounds(character)
end

function RagdollServerMod.HandleDeath(character: Model, owner: Player?): Model?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health > 0 then return nil end

	local colliderCache: {[BasePart]: BasePart?} = {}
	local head     = character:FindFirstChild("Head")        :: BasePart?
	local torso    = character:FindFirstChild("Torso")       :: BasePart?
	local leftArm  = character:FindFirstChild("Left Arm")    :: BasePart?
	local rightArm = character:FindFirstChild("Right Arm")   :: BasePart?
	local leftLeg  = character:FindFirstChild("Left Leg")    :: BasePart?
	local rightLeg = character:FindFirstChild("Right Leg")   :: BasePart?

	if head     then colliderCache[head]     = FetchColliderPart(head,     "Head")     end
	if leftArm  then colliderCache[leftArm]  = FetchColliderPart(leftArm,  "LeftArm")  end
	if rightArm then colliderCache[rightArm] = FetchColliderPart(rightArm, "RightArm") end
	if leftLeg  then colliderCache[leftLeg]  = FetchColliderPart(leftLeg,  "LeftLeg")  end
	if rightLeg then colliderCache[rightLeg] = FetchColliderPart(rightLeg, "RightLeg") end
	if torso    then colliderCache[torso]    = FetchColliderPart(torso,    "Torso")    end

	SetCustomPhysicalProperties(torso, 1, 0.5, 1, 0.4, 1)
	SetCustomPhysicalProperties(head,  0.35, 0.5, 1, 0.3, 0)

	for _, limb in ipairs({ leftArm, rightArm, leftLeg, rightLeg }) do
		if limb then limb.Massless = true end
	end

	character.Archivable = true

	for _, obj in ipairs(character:GetDescendants()) do
		if obj:IsA("SurfaceGui") and string.sub(obj.Name, 1, 9) == "WoundGui_" then
			obj:Destroy()
		end
	end

	SetupRagdoll(character, colliderCache)

	local deadBody = character:Clone()
	deadBody.Name  = "DeadBody"

	local deadHumanoid = deadBody:FindFirstChildOfClass("Humanoid")
	if deadHumanoid then
		deadHumanoid.HealthDisplayDistance = 0
		deadHumanoid.HealthDisplayType     = Enum.HumanoidHealthDisplayType.AlwaysOff
		deadHumanoid.NameDisplayDistance   = 0
		deadHumanoid.DisplayDistanceType   = Enum.HumanoidDisplayDistanceType.None
		deadHumanoid.Sit                   = false
	end

	local deadRoot = deadBody:FindFirstChild("HumanoidRootPart") :: BasePart?
	if deadRoot then
		deadRoot.Anchored = false
		local seatWeld = deadRoot:FindFirstChild("SeatWeld")
		if seatWeld then seatWeld:Destroy() end
	end

	for _, obj in ipairs(deadBody:GetDescendants()) do
		if obj:IsA("LuaSourceContainer") or obj:IsA("BodyMover") or obj:IsA("SpringConstraint") then
			obj:Destroy()
		elseif obj:IsA("Sound") then
			obj:Destroy()
		elseif obj:IsA("SurfaceGui") then
			if string.sub(obj.Name, 1, 9) == "WoundGui_" then
				obj:Destroy()
			else
				local parent = obj.Parent
				if parent and parent:IsA("BasePart") then
					obj.Adornee = parent
				end
			end
		end
	end

	local clonedRig = deadBody:FindFirstChild("WeaponRig")
	if clonedRig then clonedRig:Destroy() end

	if owner then
		deadBody:SetAttribute("OwnerUserId", owner.UserId)
	end

	deadBody.Parent = workspace

	RagdollCharacter(deadBody, owner)

	if RAGDOLL_LIFETIME > 0 then
		Debris:AddItem(deadBody, RAGDOLL_LIFETIME)
	end

	return deadBody
end

-- ---------------------------------------------------------------------------
-- Manual toggle
-- ---------------------------------------------------------------------------

function RagdollServerMod.ToggleManual(character: Model, state: boolean): boolean
	if not Config.ragdollAllowManualToggle then return false end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then return false end

	if state then
		RagdollCharacter(character, Players:GetPlayerFromCharacter(character))
	else
		for _, descendant in ipairs(character:GetDescendants()) do
			if descendant:IsA("Motor6D") and descendant.Parent and descendant.Parent.Parent == character then
				descendant.Enabled = true
			end
		end
		local humanoid2 = character:FindFirstChildOfClass("Humanoid")
		if humanoid2 then
			humanoid2.PlatformStand = false
			humanoid2:ChangeState(Enum.HumanoidStateType.Running)
		end
	end
	return true
end

function RagdollServerMod.Init(): ()
	if not RunService:IsServer() then return end
	RagdollEvent.OnServerEvent:Connect(function(plr: Player)
		local character = plr.Character
		if not character then return end
		RagdollServerMod.ToggleManual(character, true)
	end)
	UnragdollEvent.OnServerEvent:Connect(function(plr: Player)
		local character = plr.Character
		if not character then return end
		RagdollServerMod.ToggleManual(character, false)
	end)
end

return RagdollServerMod