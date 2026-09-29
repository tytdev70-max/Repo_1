local replicatedStorage = game:GetService("ReplicatedStorage")
local config = require(replicatedStorage.SPH_Assets.GameConfig)
local destructionSounds = replicatedStorage.SPH_Assets.Sounds.Destruction
local module = {}

local function PlaySoundAtLocation(position, soundName)
	local sound = destructionSounds:FindFirstChild(soundName)
	if sound then
		local newAttachment = Instance.new("Attachment", workspace.Terrain)
		newAttachment.Name = "TempDestructionSound"
		newAttachment.WorldPosition = position
		
		local newSound = sound:Clone()
		newSound.Parent = newAttachment
		newSound:Play()
		
		task.delay(newSound.TimeLength, function()
			newAttachment:Destroy()
		end)
	end
end

local function GetObjectWorldPosition(object: Instance): Vector3
	if object:IsA("Model") then
		if object.PrimaryPart then
			return object.PrimaryPart.Position
		end
		local bbCF = object:GetBoundingBox()
		return bbCF.Position
	end
	return (object :: BasePart).Position
end

module.DestroyObject = function(object: Model, player)
	object:SetAttribute("Destroyed", true)
	
	local destructionType = object:GetAttribute("DestructionType")
	local model = object:IsA("Model")
	local destructionSound = object:GetAttribute("DestructionSound")
	
	if model then
		for _, desc in object:GetDescendants() do
			if desc:IsA("BasePart") then
				local part = desc
				part.Anchored = false
				part.CollisionGroup = "Debris"

				for _, joint: JointInstance in part:GetJoints() do
					joint.Enabled = false
				end

				for _, child in part:GetChildren() do
					if child:IsA("Constraint") then
						child.Enabled = false
					end
				end
				
				if player then
					part:SetNetworkOwner(player)
				end
			elseif desc:IsA("Constraint") or desc:IsA("JointInstance") then
				desc.Enabled = false
			end
		end
		
		if destructionSound then
			local soundPosition
			if object.PrimaryPart then
				soundPosition = object.PrimaryPart.Position
			else
				soundPosition = object.WorldPivot.Position
			end
			PlaySoundAtLocation(soundPosition, destructionSound)
		end
	else
		local part: BasePart = object
		part.Anchored = false
		part.CollisionGroup = "Debris"
		
		for _, joint: JointInstance in part:GetJoints() do
			joint.Enabled = false
		end
		
		for _, child in part:GetChildren() do
			if child:IsA("Constraint") then
				child.Enabled = false
			end
		end
		
		if player then
			part:SetNetworkOwner(player)
		end
		
		if destructionSound then
			PlaySoundAtLocation(part.Position, destructionSound)
		end
	end
	
	if destructionType == "Instant" then
		object:Destroy()
	elseif destructionType == "Explosion" then
		local explosionType = object:GetAttribute("ExplosionType") or "BarrelExplosion"
		local explosionOrigin = GetObjectWorldPosition(object)
		local explosionRadius = object:GetAttribute("ExplosionRadius") or 20
		local CreateExplosion = require(replicatedStorage.SPH_Assets.Modules.Effects.Explosions.ExplosionFX)
		object:Destroy()
		CreateExplosion(explosionOrigin, explosionRadius, explosionType, player)
	else
		task.delay(config.destructibleDespawnTime, function()
			object:Destroy()
		end)
	end
end

return module