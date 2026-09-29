local Debris       = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local assets        = game:GetService("ReplicatedStorage").SPH_Assets
local config        = require(assets.GameConfig)
local ammoTypes     = assets.Ammo

local cachedStorageFolder: Folder? = nil

local function GetStorageFolder(): Folder?
	if cachedStorageFolder and cachedStorageFolder.Parent then
		return cachedStorageFolder
	end

	local sphWorkspace = workspace:FindFirstChild("SPH_Workspace")
	if not sphWorkspace then
		return nil
	end

	cachedStorageFolder = sphWorkspace:FindFirstChild("Shells") :: Folder?
	return cachedStorageFolder
end

local shellCount = 0
local module     = {}

local BRASS_PHYSICS = PhysicalProperties.new(
	10,   -- Density
	0.35,  -- Friction
	0.25,  -- Elasticity
	0.5,   -- FrictionWeight
	0.5    -- ElasticityWeight
)

local SPIN_TUMBLE = 25   -- X / Z axes tumble)
local SPIN_YAW    = 8    -- Y axis (yaw)

local function setupPart(part)
	part.Anchored                 = false
	part.CanCollide               = true
	part.CanTouch                 = true
	part.CastShadow               = false
	part.CollisionGroup           = "Casings"
	part.CustomPhysicalProperties = BRASS_PHYSICS
	part.Transparency             = 1
end

module.ejectShell = function(player, tool, gunModel)
	if not tool or not gunModel or not gunModel:FindFirstChild("Grip") then return end

	local weaponFolder = tool:FindFirstChild("SPH_Weapon")
	local statsModule = weaponFolder and weaponFolder:FindFirstChild("WeaponStats")
	if not statsModule then return end

	local storageFolder = GetStorageFolder()
	if not storageFolder then return end

	local wepStats = require(statsModule)

	local chamberAttachment = gunModel.Grip:FindFirstChild("Chamber")
	if not chamberAttachment then
		warn(tool.Name .. " does not have a 'Chamber' attachment on its Grip.")
		return
	end

	local chamberCFrame = chamberAttachment.WorldCFrame
	if player:DistanceFromCharacter(chamberCFrame.Position) > config.shellDistance then
		return
	end

	local ejectionVelocity = chamberCFrame:VectorToWorldSpace(wepStats.calcEjectionForce())

	local originCFrame = CFrame.new(chamberCFrame.Position)
		* CFrame.fromMatrix(Vector3.zero, chamberCFrame.XVector, chamberCFrame.YVector)
		* CFrame.Angles(
			math.rad(math.random(-20, 20)),
			math.rad(math.random(-20, 20)),
			math.rad(math.random(0, 360))
		)

	local shellModelFolder = ammoTypes:FindFirstChild(wepStats.ammoType) or ammoTypes.Default
	local newShell         = shellModelFolder.Casing:Clone()

	local primaryPart = nil

	if newShell:IsA("BasePart") then
		primaryPart     = newShell
		newShell.CFrame = originCFrame
		setupPart(newShell)
	else
		newShell:PivotTo(originCFrame)
		primaryPart = newShell.PrimaryPart or newShell:FindFirstChildWhichIsA("BasePart")
		for _, part in ipairs(newShell:GetDescendants()) do
			if part:IsA("BasePart") then
				setupPart(part)
			end
		end
	end

	newShell.Parent = storageFolder

	if primaryPart then
		primaryPart.AssemblyLinearVelocity = ejectionVelocity

		primaryPart.AssemblyAngularVelocity = Vector3.new(
			math.random(-SPIN_TUMBLE, SPIN_TUMBLE),
			math.random(-SPIN_YAW,    SPIN_YAW),
			math.random(-SPIN_TUMBLE, SPIN_TUMBLE)
		)
	end

	task.delay(0.01, function()
		if not newShell or not newShell.Parent then return end
		if newShell:IsA("BasePart") then
			newShell.Transparency = 0
		else
			for _, d in ipairs(newShell:GetDescendants()) do
				if d:IsA("BasePart") then d.Transparency = 0 end
			end
		end
	end)

	local dropSound = newShell:FindFirstChild("Drop")
	if dropSound and primaryPart then
		local soundPlayed = false
		local touchConn

		task.delay(0.08, function()
			if not primaryPart or not primaryPart.Parent then return end

			touchConn = primaryPart.Touched:Connect(function()
				if soundPlayed then
					touchConn:Disconnect()
					return
				end

				if primaryPart.AssemblyLinearVelocity.Magnitude > 1.5 then
					soundPlayed = true
					touchConn:Disconnect()
					local s = dropSound:Clone()
					s.Parent        = primaryPart
					s.PlaybackSpeed = math.random(30, 50) / 40
					s:Play()
					Debris:AddItem(s, 2)
				end
			end)
		end)
	end

	shellCount += 1
	if shellCount > config.shellMaxCount then
		local oldest = storageFolder:FindFirstChildWhichIsA("BasePart")
			or storageFolder:FindFirstChildWhichIsA("Model")
		if oldest then
			shellCount = math.max(0, shellCount - 1)
			oldest:Destroy()
		end
	end

	local despawnTime    = config.shellDespawn or 10
	local fadeDuration   = config.shellFadeDuration or 0.6
	local fadeStartDelay = math.max(0, despawnTime - fadeDuration)

	task.delay(fadeStartDelay, function()
		if not newShell or not newShell.Parent then return end

		for _, d in ipairs(newShell:GetDescendants()) do
			if d:IsA("ParticleEmitter") then d.Enabled = false end
		end

		local targets = {}
		local function collect(inst)
			if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
				table.insert(targets, inst)
			end
		end
		if newShell:IsA("Model") then
			for _, d in ipairs(newShell:GetDescendants()) do collect(d) end
		else
			collect(newShell)
			for _, d in ipairs(newShell:GetDescendants()) do collect(d) end
		end

		local tweenInfo = TweenInfo.new(fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		for _, inst in ipairs(targets) do
			if inst and inst.Parent then
				pcall(function()
					TweenService:Create(inst, tweenInfo, { Transparency = 1 }):Play()
				end)
			end
		end
	end)

	task.delay(despawnTime, function()
		if newShell and newShell.Parent then
			shellCount = math.max(0, shellCount - 1)
			newShell:Destroy()
		end
	end)
end

return module