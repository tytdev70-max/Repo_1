local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local config = require(assets.GameConfig)
local fractureGlass = require(assets.Modules.Effects.Environment.FractureGlass)
local SPH_Events = require(assets.Modules.Core.Networking.SPH_Events)

local glassRestoredEvent = SPH_Events.Get("EnvironmentEvents", "SPH_GlassRestored")

local module = {}

function module.IsGlass(part)
	if not part or not part:IsA("BasePart") then return false end
	return part.Name == "Glass" or CollectionService:HasTag(part, "BreakableGlass")
end

function module.Shatter(glassPart, hitPosition, forceDirection)
	if not glassPart or not glassPart:IsA("BasePart") then return false end
	if not config.glassShatter then return false end
	if glassPart:GetAttribute("Shattered") then return false end

	glassPart:SetAttribute("Shattered", true)

	local snap = {
		Size         = glassPart.Size,
		Color        = glassPart.Color,
		Material     = glassPart.Material,
		CFrame       = glassPart.CFrame,
		Transparency = glassPart.Transparency,
		CanCollide   = glassPart.CanCollide,
		CanQuery     = glassPart.CanQuery,
		CanTouch     = glassPart.CanTouch,
		Anchored     = glassPart.Anchored,
	}

	local tempPart = glassPart:Clone()
	tempPart.Name = "TempGlass"
	tempPart.Parent = workspace

	glassPart.Transparency = 1
	glassPart.CanCollide   = false
	glassPart.CanQuery     = false
	glassPart.CanTouch     = false
	glassPart.Anchored     = true

	local respawnDelay = (type(config.glassRespawnTime) == "number" and config.glassRespawnTime > 0)
		and config.glassRespawnTime or 5

	local capturedPart = glassPart
	task.delay(respawnDelay, function()
		if not capturedPart or not capturedPart.Parent then return end
		capturedPart.Size         = snap.Size
		capturedPart.Color        = snap.Color
		capturedPart.Material     = snap.Material
		capturedPart.CFrame       = snap.CFrame
		capturedPart.Transparency = snap.Transparency
		capturedPart.CanCollide   = snap.CanCollide
		capturedPart.CanQuery     = snap.CanQuery
		capturedPart.CanTouch     = snap.CanTouch
		capturedPart.Anchored     = snap.Anchored
		capturedPart:SetAttribute("Shattered", false)
		glassRestoredEvent:FireAllClients(capturedPart, snap.Transparency)
	end)

	local safeHitPosition = hitPosition or glassPart.Position
	local safeForce = forceDirection or Vector3.new(0, 0, -10)
	if (glassPart:IsA("Part") and glassPart.Shape == Enum.PartType.Block) or glassPart:IsA("WedgePart") then
		fractureGlass(tempPart, safeHitPosition, safeForce)
	else
		tempPart:Destroy()
	end

	local soundAtt = Instance.new("Attachment", workspace.Terrain)
	soundAtt.WorldPosition = safeHitPosition
	local glassSounds = assets.Sounds.GlassBreak:GetChildren()
	local shatterSound = glassSounds[math.random(#glassSounds)]:Clone()
	shatterSound.Parent = soundAtt
	shatterSound:Play()
	Debris:AddItem(soundAtt, shatterSound.TimeLength)

	return true
end

return module