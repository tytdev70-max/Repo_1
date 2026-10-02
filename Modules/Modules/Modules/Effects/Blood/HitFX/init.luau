local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.SPH_Assets.GameConfig)

local Glass = {"1565824613", "1565825075"}
local Metal = {"282954522", "282954538", "282954576", "1565756607", "1565756818"}
local Grass = {"1565830611", "1565831129", "1565831468", "1565832329"}
local Wood = {"287772625", "287772674", "287772718", "287772829", "287772902"}
local Concrete = {"287769261", "287769348", "287769483", "287769538"}
local Hits = {"363818432", "363818488", "363818567", "363818611", "363818653"}
local Headshots = {"4459572527", "4459573786", "3739364168"}
local Water = {"9119478398", "6569949256", "6569930140"}

local MaterialHole = nil
local MaterialFolder = script.BulletHoleDecals

local DEFAULT_BULLET_HOLE_TEXTURE = "rbxassetid://11645179630"

local MATERIAL_TEXTURES = {
	["Stone"] = {"rbxassetid://11645179630"},
	["Wood"] = {"rbxassetid://15342524923", "rbxassetid://6552016340"},
	["Metal"] = {"rbxassetid://16694817754", "rbxassetid://132388872936037"},
	["Glass"] = {"rbxassetid://70982280930836", "rbxassetid://15968984662", "rbxassetid://16480287689"},
	["Concrete"] = {"rbxassetid://11645179630"},
	["Plastic"] = {"rbxassetid://11645179630"},
	["Sand"] = {"rbxassetid://11645179630"},
	["Grass"] = {"rbxassetid://11645179630"},
	["Fabric"] = {"rbxassetid://11645179630"},
	["Snow"] = {"rbxassetid://11645179630"},
	["Ground"] = {"rbxassetid://11645179630"},
	["Foil"] = {"rbxassetid://11645179630"},
	["Neon"] = {"rbxassetid://11645179630"},
	["Default"] = {"rbxassetid://11645179630"},
}

local Effects = script
local WorldToGui = script:WaitForChild("WorldToGui")
if typeof(WorldToGui) == "Instance" then
	WorldToGui = require(WorldToGui)
end

local GetMaterialType = require(script.MaterialTypes)
local OverrideSurfaceGUIBulletHoles = script:WaitForChild("EnablePartBasedBulletHoles").Value

local textureCache = {}
local effectTypeFolderCache = {}
local characterCache = {}
local CACHE_LIFETIME = 5

local cachedIgnoreList = {}
local lastIgnoreListUpdate = 0
local IGNORE_LIST_UPDATE_INTERVAL = 1

local lastBloodSplatTime = 0

local Hitmarker = {}

local random = math.random
local function RandF(low, top)
	return low + random() * (top - low)
end

local function NormalToNormalId(normal)
	local ax, ay, az = math.abs(normal.X), math.abs(normal.Y), math.abs(normal.Z)
	if ax >= ay and ax >= az then
		return normal.X > 0 and Enum.NormalId.Right or Enum.NormalId.Left
	elseif ay >= ax and ay >= az then
		return normal.Y > 0 and Enum.NormalId.Top or Enum.NormalId.Bottom
	else
		return normal.Z > 0 and Enum.NormalId.Back or Enum.NormalId.Front
	end
end

local function RList(tbl)
	return tbl[random(1, #tbl)]
end

local function CheckColor(color, add)
	return math.clamp(color + add, 0, 1)
end

local function UpdateIgnoreList()
	local currentTime = tick()
	if currentTime - lastIgnoreListUpdate < IGNORE_LIST_UPDATE_INTERVAL then
		return cachedIgnoreList
	end

	local ignoreList = {}

	local stuffFolder = workspace:FindFirstChild("Stuff")
	if stuffFolder and stuffFolder:FindFirstChild("ignore") then
		table.insert(ignoreList, stuffFolder.ignore)
	end

	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			table.insert(ignoreList, player.Character)
		end
	end

	local npcFolder = workspace:FindFirstChild("NPCs") or workspace:FindFirstChild("Enemies")
	if npcFolder then
		for _, npc in ipairs(npcFolder:GetChildren()) do
			if npc:FindFirstChildOfClass("Humanoid") then
				table.insert(ignoreList, npc)
			end
		end
	end

	cachedIgnoreList = ignoreList
	lastIgnoreListUpdate = currentTime
	return ignoreList
end

local function CreateBloodSoak(surfaceGui, containerFrame, startX, startY, part)
	if not GameConfig.bloodEnabled or not GameConfig.bloodSoakEnabled then return end

	task.spawn(function()
		task.wait(GameConfig.bloodSoakDelay)
		if not surfaceGui or not surfaceGui.Parent then return end

		local startSizePixels = GameConfig.bloodSoakStartSize * surfaceGui.PixelsPerStud
		local endSizePixels = GameConfig.bloodSoakEndSize * surfaceGui.PixelsPerStud

		local soakFrame = Instance.new("Frame")
		soakFrame.Name = "BloodSoak_" .. tick()
		soakFrame.Parent = containerFrame
		soakFrame.BackgroundTransparency = 1
		soakFrame.BorderSizePixel = 0
		soakFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		soakFrame.Position = UDim2.new(startX, 0, startY, 0)
		soakFrame.Size = UDim2.new(0, startSizePixels, 0, startSizePixels)
		soakFrame.ZIndex = 1

		local soakImage = Instance.new("ImageLabel")
		soakImage.Name = "SoakImage"
		soakImage.Parent = soakFrame
		soakImage.BackgroundTransparency = 1
		soakImage.ImageTransparency = 0
		soakImage.SizeConstraint = Enum.SizeConstraint.RelativeXY
		soakImage.Size = UDim2.fromScale(1, 1)
		soakImage.Position = UDim2.fromScale(0.5, 0.5)
		soakImage.AnchorPoint = Vector2.new(0.5, 0.5)
		soakImage.Image = GameConfig.bloodSoakTexture
		soakImage.ImageColor3 = GameConfig.bloodSoakColor
		soakImage.ScaleType = Enum.ScaleType.Stretch

		local tween = TweenService:Create(
			soakFrame,
			TweenInfo.new(GameConfig.bloodSoakSpeed, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
			{ Size = UDim2.new(0, endSizePixels, 0, endSizePixels) }
		)
		tween:Play()

		Debris:AddItem(soakFrame, 60)
	end)
end

local function CreateBloodDrip(surfaceGui, containerFrame, startX, startY, hitPart)
	if not GameConfig.bloodEnabled or not GameConfig.bloodDripEnabled then return end

	local numDrips = math.random(GameConfig.bloodDripMin, GameConfig.bloodDripMax)

	task.spawn(function()
		for i = 1, numDrips do
			if i > 1 then
				task.wait(GameConfig.bloodDripDelay)
			end

			if not surfaceGui or not surfaceGui.Parent then return end

			local dripX = startX + math.random(-10, 10) / 1000
			local maxDripLength = random() * GameConfig.bloodDripMaxDistance
			local targetLength = math.min(maxDripLength, GameConfig.bloodDripMaxDistance)

			local dripFrame = Instance.new("Frame")
			dripFrame.Name = "BloodDrip_" .. tick()
			dripFrame.Parent = containerFrame
			dripFrame.BackgroundTransparency = 1
			dripFrame.BorderSizePixel = 0
			dripFrame.AnchorPoint = Vector2.new(0.5, 0)
			dripFrame.Position = UDim2.new(dripX, 0, startY, 0)
			dripFrame.Size = UDim2.new(0, GameConfig.bloodDripWidth * surfaceGui.PixelsPerStud, 0, 0)
			dripFrame.ZIndex = 2

			local dripImage = Instance.new("ImageLabel")
			dripImage.Name = "DripImage"
			dripImage.Parent = dripFrame
			dripImage.BackgroundTransparency = 1
			dripImage.ImageTransparency = 0
			dripImage.Size = UDim2.fromScale(1, 1)
			dripImage.Position = UDim2.fromScale(0.5, 0)
			dripImage.AnchorPoint = Vector2.new(0.5, 0)
			dripImage.Image = GameConfig.bloodDripTexture
			dripImage.ImageColor3 = Color3.fromRGB(120, 0, 0)
			dripImage.ScaleType = Enum.ScaleType.Stretch

			local tweenInfo = TweenInfo.new(
				GameConfig.bloodDripSpeed * (targetLength / GameConfig.bloodDripLength),
				Enum.EasingStyle.Sine,
				Enum.EasingDirection.Out
			)
			local targetSize = targetLength * surfaceGui.PixelsPerStud
			local dripUsesGravity = GameConfig.bloodDripGravity ~= false
			local tween
			if dripUsesGravity then
				tween = TweenService:Create(dripFrame, tweenInfo, {
					Size = UDim2.new(0, GameConfig.bloodDripWidth * surfaceGui.PixelsPerStud, 0, targetSize)
				})
			else
				dripFrame.Size = UDim2.new(0, GameConfig.bloodDripWidth * surfaceGui.PixelsPerStud, 0, targetSize)
				tween = TweenService:Create(dripFrame, tweenInfo, {})
			end
			tween:Play()

			Debris:AddItem(dripFrame, 60)
		end
	end)
end

local function SaveBulletHoleGuis(part)
	local saved = {}

	for _, child in ipairs(part:GetChildren()) do
		if child:IsA("SurfaceGui") and (child.Name:match("^BulletHoleGui_") or child.Name:match("^BulletHolePartGui_") or child.Name:match("^WoundGui_")) then
			local sg = child
			local data = {
				Name = sg.Name,
				Face = tostring(sg.Face and sg.Face.Name or ""),
				CanvasSize = sg.CanvasSize,
				PixelsPerStud = sg.PixelsPerStud,
				AlwaysOnTop = sg.AlwaysOnTop,
				LightInfluence = sg.LightInfluence,
				Children = {}
			}

			local container = sg:FindFirstChild("Container")
			if container then
				for _, frame in ipairs(container:GetChildren()) do
					if frame:IsA("Frame") then
						local img = frame:FindFirstChildWhichIsA("ImageLabel") or frame:FindFirstChildWhichIsA("ImageButton")
						local entry = {
							Position = frame.Position,
							Size = frame.Size,
							Name = frame.Name,
							CreationTime = frame:GetAttribute("CreationTime") or tick(),
							Image = img and img.Image or nil,
							ImageTransparency = img and img.ImageTransparency or nil,
							ImageColor3 = img and img.ImageColor3 or nil,
							ImageRotation = img and img.Rotation or 0,
							ImageAnchorPoint = img and img.AnchorPoint or nil
						}
						table.insert(data.Children, entry)
					end
				end
			end

			table.insert(saved, data)
		end
	end

	return saved
end

local function ResolveTextureEntry(entry)
	if not entry then return nil end
	local t = type(entry)
	if t == "string" then
		return entry
	elseif t == "table" then
		if #entry == 0 then return nil end
		return entry[random(1, #entry)]
	end
	return nil
end

local function GetBulletHoleTextureForMaterial(materialType)
	if textureCache[materialType] then
		return textureCache[materialType]
	end

	local entry = MATERIAL_TEXTURES[materialType]
	local tex = ResolveTextureEntry(entry)
	if tex then
		textureCache[materialType] = tex
		return tex
	end

	local defaultEntry = MATERIAL_TEXTURES["Default"]
	tex = ResolveTextureEntry(defaultEntry)
	if tex then
		textureCache[materialType] = tex
		return tex
	end

	tex = ResolveTextureEntry(DEFAULT_BULLET_HOLE_TEXTURE) or "rbxassetid://11645179630"
	textureCache[materialType] = tex
	return tex
end

local function PlayMaterialSoundAtPosition(position, soundList, volume)
	volume = volume or 0.7
	if not soundList or #soundList == 0 then return end
	local soundId = "rbxassetid://" .. RList(soundList)
	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2,0.2,0.2)
	part.CFrame = CFrame.new(position)
	part.Parent = workspace

	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.PlaybackSpeed = RandF(0.85, 1.05)
	s.MaxDistance = 500
	s.EmitterSize = 8
	s.Parent = part
	s:Play()

	s.Ended:Connect(function()
		if s then s:Destroy() end
		if part then part:Destroy() end
	end)

	Debris:AddItem(part, 6)
end

local function CollectTransparencyTargets(instance)
	local list = {}
	local function tryAdd(inst)
		if inst == nil then return end
		local ok, _ = pcall(function() return inst.Transparency end)
		if ok then
			table.insert(list, {inst = inst, prop = "Transparency", orig = inst.Transparency})
			return
		end
		ok, _ = pcall(function() return inst.ImageTransparency end)
		if ok then
			table.insert(list, {inst = inst, prop = "ImageTransparency", orig = inst.ImageTransparency})
			return
		end
	end
	tryAdd(instance)
	for _, d in ipairs(instance:GetDescendants()) do
		tryAdd(d)
	end
	return list
end

local function TweenTransparencyTargets(targets, fadeTime, completeCallback)
	local tweens = {}
	for _, t in ipairs(targets) do
		local instance = t.inst
		local prop = t.prop
		local orig = t.orig
		if instance and instance.Parent then
			local info = TweenInfo.new(math.max(0.01, fadeTime), Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			local goal = {}
			goal[prop] = orig
			local tween = TweenService:Create(instance, info, goal)
			table.insert(tweens, tween)
			tween:Play()
		end
	end

	if #tweens > 0 and completeCallback then
		tweens[1].Completed:Connect(function() completeCallback() end)
	elseif completeCallback then
		completeCallback()
	end
end

local function CleanupOldBulletHoles(container, maxCount)
	local children = container:GetChildren()
	local count = #children

	if count > maxCount then
		table.sort(children, function(a, b)
			return (a:GetAttribute("CreationTime") or 0) < (b:GetAttribute("CreationTime") or 0)
		end)

		local toRemove = count - maxCount
		for i = 1, toRemove do
			if children[i] then
				children[i]:Destroy()
			end
		end
	end
end

local woundDeathBound = setmetatable({}, { __mode = "k" })
local trackedWounds = {}

local function IsWoundSurfaceGui(inst)
	return inst ~= nil and inst:IsA("SurfaceGui") and string.sub(inst.Name, 1, 9) == "WoundGui_"
end

local function DestroyTrackedGui(surfaceGui)
	if not surfaceGui then
		return
	end
	trackedWounds[surfaceGui] = nil
	if surfaceGui.Parent then
		surfaceGui:Destroy()
	end
end

local function DestroyWoundSurfaceGuis(root)
	if not root then return end
	local toDestroy = {}
	for _, inst in ipairs(root:GetDescendants()) do
		if IsWoundSurfaceGui(inst) then
			table.insert(toDestroy, inst)
		end
	end
	for _, inst in ipairs(toDestroy) do
		DestroyTrackedGui(inst)
	end
end

local function DestroyWoundsForCharacter(character)
	DestroyWoundSurfaceGuis(character)
	for gui, boundCharacter in pairs(trackedWounds) do
		if boundCharacter == character then
			DestroyTrackedGui(gui)
		elseif character and gui.Adornee and gui.Adornee:IsDescendantOf(character) then
			DestroyTrackedGui(gui)
		elseif not gui.Parent then
			trackedWounds[gui] = nil
		end
	end
end

local function GetHumanoidFromPart(part)
	local current = part
	while current and current ~= game do
		local humanoid = current:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid, current
		end
		current = current.Parent
	end
	return nil, nil
end

local function BindWoundCleanup(hitPart, surfaceGui)
	if not hitPart or not surfaceGui then
		return false
	end

	local humanoid, character = GetHumanoidFromPart(hitPart)
	if character and (character.Name == "DeadBody" or (humanoid and humanoid.Health <= 0)) then
		DestroyTrackedGui(surfaceGui)
		DestroyWoundsForCharacter(character)
		return false
	end

	if surfaceGui:GetAttribute("WoundCleanupBound") then
		return surfaceGui.Parent ~= nil
	end
	surfaceGui:SetAttribute("WoundCleanupBound", true)
	trackedWounds[surfaceGui] = character or true

	local function destroyGui()
		DestroyTrackedGui(surfaceGui)
	end

	surfaceGui.Destroying:Connect(function()
		trackedWounds[surfaceGui] = nil
	end)

	hitPart.Destroying:Connect(destroyGui)

	hitPart:GetPropertyChangedSignal("Transparency"):Connect(function()
		if hitPart.Transparency >= 1 then
			destroyGui()
		end
	end)

	hitPart.AncestryChanged:Connect(function(_, parent)
		if not parent then
			destroyGui()
		end
	end)

	if not humanoid then
		return true
	end

	if not woundDeathBound[humanoid] then
		woundDeathBound[humanoid] = true
		humanoid.Died:Connect(function()
			DestroyWoundsForCharacter(character)
		end)
		humanoid.HealthChanged:Connect(function(health)
			if health <= 0 then
				DestroyWoundsForCharacter(character)
			end
		end)
		if character then
			character.AncestryChanged:Connect(function(_, parent)
				if not parent then
					DestroyWoundsForCharacter(character)
				end
			end)
		end
	end

	return true
end

local function stripWoundsFromModel(model)
	DestroyWoundSurfaceGuis(model)
	model.DescendantAdded:Connect(function(desc)
		if IsWoundSurfaceGui(desc) then
			task.defer(function()
				if desc.Parent then
					desc:Destroy()
				end
			end)
		end
	end)
end

workspace.ChildAdded:Connect(function(child)
	if child.Name == "DeadBody" then
		stripWoundsFromModel(child)
	end
end)

for _, child in ipairs(workspace:GetChildren()) do
	if child.Name == "DeadBody" then
		stripWoundsFromModel(child)
	end
end

local function ApplyWoundDecal(Position, Normal, HitPart, ForcedWound)
	if not GameConfig.bloodEnabled or not GameConfig.woundDecalsEnabled then return ForcedWound end
	if HitPart.Name == "Head" or HitPart.Name:lower():find("head") then return ForcedWound end

	local humanoid, character = GetHumanoidFromPart(HitPart)
	if character and character.Name == "DeadBody" then return ForcedWound end
	if humanoid and humanoid.Health <= 0 then return ForcedWound end

	local folder = MaterialFolder:FindFirstChild("Flesh")
	if not folder then return ForcedWound end
	local hitFolder = folder:FindFirstChild("Hit")
	if not hitFolder then return ForcedWound end

	local options = hitFolder:GetChildren()
	if #options == 0 then return ForcedWound end

	local wound = ForcedWound and hitFolder:FindFirstChild(ForcedWound)
	if not wound then
		wound = options[random(1, #options)]
	end
	if not wound:IsA("Decal") then return ForcedWound end

	local Surface, _, _, RelX, RelY = WorldToGui:WorldPositionToGuiPosition(HitPart, Position)
	if not Surface then return wound.Name end

	local function createWoundOnFace(surface, x, y, hitPart)
		local GuiName = string.format("WoundGui_%s", surface.Name)
		local SurfaceGui = HitPart:FindFirstChild(GuiName)
		local ContainerFrame

		if SurfaceGui then
			ContainerFrame = SurfaceGui:FindFirstChild("Container")
			if not ContainerFrame then
				SurfaceGui:Destroy()
				SurfaceGui = nil
			end
		end

		if not SurfaceGui then
			SurfaceGui = Instance.new("SurfaceGui")
			SurfaceGui.Name = GuiName
			SurfaceGui.Parent = HitPart
			SurfaceGui.Face = surface
			SurfaceGui.Adornee = HitPart
			SurfaceGui.CanvasSize = Vector2.new(2048, 2048)
			SurfaceGui.LightInfluence = 1
			SurfaceGui.AlwaysOnTop = false
			SurfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
			SurfaceGui.ClipsDescendants = true
			SurfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
			SurfaceGui.PixelsPerStud = 50

			ContainerFrame = Instance.new("Frame")
			ContainerFrame.Name = "Container"
			ContainerFrame.Parent = SurfaceGui
			ContainerFrame.BackgroundTransparency = 1
			ContainerFrame.Size = UDim2.fromScale(1, 1)
			ContainerFrame.ClipsDescendants = true
		end

		if not BindWoundCleanup(HitPart, SurfaceGui) then
			return
		end

		local WoundFrame = Instance.new("Frame")
		WoundFrame.Name = "WoundFrame"
		WoundFrame.Parent = ContainerFrame
		WoundFrame.BackgroundTransparency = 1
		WoundFrame.BorderSizePixel = 0
		WoundFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		WoundFrame.Position = UDim2.new(x, 0, y, 0)
		WoundFrame.Size = UDim2.new(0, 22, 0, 22)
		WoundFrame:SetAttribute("CreationTime", tick())

		local WoundImage = Instance.new("ImageLabel")
		WoundImage.Name = "WoundImage"
		WoundImage.Parent = WoundFrame
		WoundImage.BackgroundTransparency = 1
		WoundImage.Size = UDim2.fromScale(1, 1)
		WoundImage.SizeConstraint = Enum.SizeConstraint.RelativeXY
		WoundImage.Position = UDim2.fromScale(0.5, 0.5)
		WoundImage.AnchorPoint = Vector2.new(0.5, 0.5)
		WoundImage.Image = wound.Texture
		WoundImage.ImageColor3 = wound.Color3
		WoundImage.ImageTransparency = wound.Transparency

		Debris:AddItem(WoundFrame, 8)

		CreateBloodDrip(SurfaceGui, ContainerFrame, x, y, hitPart)
		CreateBloodSoak(SurfaceGui, ContainerFrame, x, y, hitPart)

		CleanupOldBulletHoles(ContainerFrame, GameConfig.maxBulletHolesPerSurface)
	end

	createWoundOnFace(Surface, RelX, RelY, HitPart)

	local oppositeFaceMap = {
		[Enum.NormalId.Left] = Enum.NormalId.Right,
		[Enum.NormalId.Right] = Enum.NormalId.Left,
		[Enum.NormalId.Top] = Enum.NormalId.Bottom,
		[Enum.NormalId.Bottom] = Enum.NormalId.Top,
		[Enum.NormalId.Front] = Enum.NormalId.Back,
		[Enum.NormalId.Back] = Enum.NormalId.Front,
	}

	local oppositeFace = oppositeFaceMap[Surface]
	if not oppositeFace then return wound.Name end

	local EDGE_THRESHOLD = 0.05
	local nearEdgeXLow = RelX <= EDGE_THRESHOLD
	local nearEdgeXHigh = RelX >= 1 - EDGE_THRESHOLD
	local nearEdgeYLow = RelY <= EDGE_THRESHOLD
	local nearEdgeYHigh = RelY >= 1 - EDGE_THRESHOLD

	if not (nearEdgeXLow or nearEdgeXHigh or nearEdgeYLow or nearEdgeYHigh) then return wound.Name end

	local OFFSET_DISTANCE = 0.1
	local offsetVector = Vector3.FromNormalId(oppositeFace) * OFFSET_DISTANCE
	local newPos = Position + offsetVector

	local oppSurface, _, _, oppRelX, oppRelY = WorldToGui:WorldPositionToGuiPosition(HitPart, newPos)
	if not oppSurface or oppSurface ~= oppositeFace then return wound.Name end

	if nearEdgeXLow or nearEdgeXHigh then
		oppRelX = 1 - oppRelX
	end

	if nearEdgeYLow or nearEdgeYHigh then
		oppRelY = 1 - oppRelY
	end

	createWoundOnFace(oppSurface, oppRelX, oppRelY, HitPart)

	return wound.Name
end

local function IsCharacterPart(Part)
	if not Part or not Part.Parent then return false end

	local parent = Part.Parent
	local cacheKey = parent
	local currentTime = tick()

	local cached = characterCache[cacheKey]
	if cached and (currentTime - cached.time) < CACHE_LIFETIME then
		return cached.value
	end

	local player = Players:GetPlayerFromCharacter(parent)
	if player then
		characterCache[cacheKey] = {value = true, time = currentTime}
		return true
	end

	if parent:FindFirstChildOfClass("Humanoid") then
		characterCache[cacheKey] = {value = true, time = currentTime}
		return true
	end

	local grandparent = parent.Parent
	if grandparent then
		if grandparent:FindFirstChildOfClass("Humanoid") then
			characterCache[cacheKey] = {value = true, time = currentTime}
			return true
		end

		player = Players:GetPlayerFromCharacter(grandparent)
		if player then
			characterCache[cacheKey] = {value = true, time = currentTime}
			return true
		end
	end

	if grandparent and grandparent.Parent then
		if grandparent.Parent:FindFirstChildOfClass("Humanoid") then
			characterCache[cacheKey] = {value = true, time = currentTime}
			return true
		end
	end

	characterCache[cacheKey] = {value = false, time = currentTime}
	return false
end

task.spawn(function()
	while true do
		task.wait(60) 
		local currentTime = tick()
		for key, value in pairs(characterCache) do
			if currentTime - value.time > CACHE_LIFETIME * 2 then
				characterCache[key] = nil
			end
		end
	end
end)

local function SpawnBloodGibEffect(Position, Normal)
	local DecalSurface = require(script:WaitForChild("DecalSurface"))

	local tempPart = Instance.new("Part")
	tempPart.Anchored = true
	tempPart.CanCollide = false
	tempPart.Transparency = 1
	tempPart.Size = Vector3.new(0.1, 0.1, 0.1)
	tempPart.CFrame = CFrame.new(Position)
	tempPart.Parent = workspace

	local Attachment = Instance.new("Attachment")
	Attachment.CFrame = CFrame.new(Position, Position + Normal)
	Attachment.Parent = tempPart

	local HitSound = Instance.new("Sound")
	HitSound.Parent = Attachment
	HitSound.Volume = random(5, 10) / 10
	HitSound.MaxDistance = 500
	HitSound.EmitterSize = 10
	HitSound.PlaybackSpeed = random(34, 50) / 40
	HitSound.SoundId = "rbxassetid://" .. Hits[random(1, #Hits)]
	HitSound:Play()

	Debris:AddItem(tempPart, 6)

	return DecalSurface
end

function BloodSplat(Position, HitPart, Normal, isReplay, ForcedDecal)
	if not GameConfig.bloodEnabled or not GameConfig.bloodSplatEnabled then
		return isReplay and ForcedDecal or nil
	end

	if isReplay then
		local DecalSurface = SpawnBloodGibEffect(Position, Normal)

		if ForcedDecal
			and ForcedDecal.Instance
			and ForcedDecal.Instance.Parent
			and ForcedDecal.Instance:IsA("BasePart")
			and ForcedDecal.SurfacePosition
			and ForcedDecal.SurfaceNormal
			and not IsCharacterPart(ForcedDecal.Instance) then
			pcall(function()
				DecalSurface.MakeDecalOnSurface(
					"Blood", ForcedDecal.SurfaceNormal, ForcedDecal.Instance, ForcedDecal.SurfacePosition,
					"Big", ForcedDecal.ImageId, ForcedDecal.Chance
				)
			end)
		end

		return ForcedDecal
	end

	local currentTime = tick()
	if currentTime - lastBloodSplatTime < GameConfig.bloodSplatCooldown then
		return nil
	end
	lastBloodSplatTime = currentTime

	local DecalSurface = SpawnBloodGibEffect(Position, Normal)

	local spreadDir = -Normal + Vector3.new(0, -0.15, 0)
	if spreadDir.Magnitude > 0 then
		spreadDir = spreadDir.Unit
	else
		spreadDir = -Normal
	end
	local sprayDistance = GameConfig.bloodSplatSprayDistance

	local baseIgnoreList = UpdateIgnoreList()
	local ignoreList = {}
	for _, inst in ipairs(baseIgnoreList) do
		table.insert(ignoreList, inst)
	end

	local splatRayParams = RaycastParams.new()
	splatRayParams.FilterType = Enum.RaycastFilterType.Exclude
	splatRayParams.FilterDescendantsInstances = ignoreList
	splatRayParams.RespectCanCollide = true
	splatRayParams.IgnoreWater = true

	local rayResult = workspace:Raycast(Position, spreadDir * sprayDistance, splatRayParams)

	if rayResult and rayResult.Instance and rayResult.Instance:IsA("BasePart") and not IsCharacterPart(rayResult.Instance) then
		local usedImageId, usedChance
		local ok, err = pcall(function()
			usedImageId, usedChance = DecalSurface.MakeDecalOnSurface(
				"Blood", rayResult.Normal, rayResult.Instance, rayResult.Position, "Big", nil, nil
			)
		end)
		if ok then
			return {
				ImageId = usedImageId,
				Chance = usedChance,
				Instance = rayResult.Instance,
				SurfacePosition = rayResult.Position,
				SurfaceNormal = rayResult.Normal,
			}
		else
			warn("[BLOOD DEBUG] Failed to place blood decal -", err)
		end
	end

	return nil
end

function CreateEffect(Type, Attachment, HitPart)
	local NewType = effectTypeFolderCache[Type]
	if not NewType then
		NewType = Effects:FindFirstChild(Type) or Effects.Stone
		effectTypeFolderCache[Type] = NewType
	end
	local effectChildren = NewType:GetChildren()
	if #effectChildren == 0 then return end

	local NewEffect = effectChildren[random(1, #effectChildren)]:Clone()
	local MaxTime = 3

	for _, Effect in ipairs(NewEffect:GetChildren()) do
		if not Effect:IsA("ParticleEmitter") then continue end

		Effect.Parent = Attachment
		Effect.Enabled = false

		if Type == "Sand" and HitPart then
			local NewColor = HitPart.Color
			local Add = HitPart.Material == Enum.Material.Fabric and -0.2 or 0.3
			NewColor = Color3.new(
				CheckColor(NewColor.R, Add),
				CheckColor(NewColor.G, Add),
				CheckColor(NewColor.B, Add)
			)

			Effect.Color = ColorSequence.new(NewColor)
		end

		if Effect.Rate > 10 then
			Effect:Emit(Effect.Rate / 10)
		else
			Effect:Emit(1)
		end
		MaxTime = math.max(MaxTime, Effect.Lifetime.Max)
	end

	local soundMap = {
		Headshot = Headshots, Hit = Hits, Glass = Glass, Metal = Metal,
		Ground = Grass, Grass = Grass, Wood = Wood, Stone = Concrete,
		Water = Water
	}
	local SoundType = soundMap[Type] or Concrete

	local HitSound = Instance.new("Sound")
	HitSound.Parent = Attachment
	HitSound.Volume = random(5, 10) / 10
	HitSound.MaxDistance = 500
	HitSound.EmitterSize = 10
	HitSound.PlaybackSpeed = random(34, 50) / 40
	HitSound.SoundId = "rbxassetid://" .. SoundType[random(1, #SoundType)]
	HitSound:Play()

	MaxTime = math.max(MaxTime, HitSound.TimeLength)
	Debris:AddItem(Attachment, MaxTime)
end

local function CreateSurfaceGuiBulletHole(Part, Position, Material)
	local Surface, _, _, RelX, RelY = WorldToGui:WorldPositionToGuiPosition(Part, Position)
	if not Surface then return end

	local MaterialType = GetMaterialType(Material)
	local GuiName = string.format("BulletHoleGui_%s", Surface.Name)
	local SurfaceGui = Part:FindFirstChild(GuiName)
	local ContainerFrame

	if SurfaceGui then
		ContainerFrame = SurfaceGui:FindFirstChild("Container")
		if not ContainerFrame then
			SurfaceGui:Destroy()
			SurfaceGui = nil
		end
	end

	if not SurfaceGui then
		SurfaceGui = Instance.new("SurfaceGui")
		SurfaceGui.Name = GuiName
		SurfaceGui.Parent = Part
		SurfaceGui.Face = Surface
		SurfaceGui.Adornee = Part
		SurfaceGui.CanvasSize = Vector2.new(2048, 2048)
		SurfaceGui.LightInfluence = 1
		SurfaceGui.AlwaysOnTop = false
		SurfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		SurfaceGui.ClipsDescendants = true
		SurfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		SurfaceGui.PixelsPerStud = 50

		ContainerFrame = Instance.new("Frame")
		ContainerFrame.Name = "Container"
		ContainerFrame.Parent = SurfaceGui
		ContainerFrame.BackgroundTransparency = 1
		ContainerFrame.Size = UDim2.fromScale(1, 1)
		ContainerFrame.ClipsDescendants = true
	end

	local BulletHoleFrame = Instance.new("Frame")
	BulletHoleFrame.Name = "BulletHoleFrame"
	BulletHoleFrame.Parent = ContainerFrame
	BulletHoleFrame.BackgroundTransparency = 1
	BulletHoleFrame.BorderSizePixel = 0
	BulletHoleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	BulletHoleFrame.Position = UDim2.new(RelX, 0, RelY, 0)
	BulletHoleFrame.Size = UDim2.new(0, GameConfig.bulletHoleSize * SurfaceGui.PixelsPerStud, 0, GameConfig.bulletHoleSize * SurfaceGui.PixelsPerStud)
	BulletHoleFrame:SetAttribute("CreationTime", tick())

	local BulletHoleImage = Instance.new("ImageLabel")
	BulletHoleImage.Name = "BulletHoleImage"
	BulletHoleImage.Parent = BulletHoleFrame
	BulletHoleImage.BackgroundTransparency = 1
	BulletHoleImage.ImageTransparency = 0
	BulletHoleImage.SizeConstraint = Enum.SizeConstraint.RelativeXY
	BulletHoleImage.Size = UDim2.fromScale(1, 1)
	BulletHoleImage.Position = UDim2.fromScale(0.5, 0.5)
	BulletHoleImage.AnchorPoint = Vector2.new(0.5, 0.5)
	BulletHoleImage.Image = GetBulletHoleTextureForMaterial(MaterialType)

	CleanupOldBulletHoles(ContainerFrame, GameConfig.maxBulletHolesPerSurface)

	task.spawn(function()
		task.wait(GameConfig.bulletHoleFadeDelay)
		if not BulletHoleImage or not BulletHoleImage.Parent then return end

		local tween = TweenService:Create(
			BulletHoleImage,
			TweenInfo.new(GameConfig.bulletHoleFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ImageTransparency = 1}
		)
		tween:Play()
		tween.Completed:Wait()

		if BulletHoleFrame and BulletHoleFrame.Parent then
			BulletHoleFrame:Destroy()
		end
	end)
end

local function CreatePartBasedBulletHole(HitPart, MaterialHole, Attachment, Position, Normal)
	local MaterialHit = MaterialFolder:FindFirstChild(MaterialHole)
	if not MaterialHit then return end

	local HoleSize = MaterialHit:FindFirstChild("HoleSize")
	local Size = HoleSize and RandF(HoleSize.MinValue, HoleSize.MaxValue) or RandF(0.2, 0.8)
	local HitPartColor = HitPart.Color

	local face = NormalToNormalId(Normal)

	local Surface, _, _, RelX, RelY = WorldToGui:WorldPositionToGuiPosition(HitPart, Position)
	if not Surface then return end
	if Surface ~= face then
		face = Surface
	end

	local GuiName = string.format("BulletHolePartGui_%s", tostring(face.Name))

	local SurfaceGui = HitPart:FindFirstChild(GuiName)
	local ContainerFrame

	if SurfaceGui then
		ContainerFrame = SurfaceGui:FindFirstChild("Container")
		if not ContainerFrame then
			SurfaceGui:Destroy()
			SurfaceGui = nil
		end
	end

	if not SurfaceGui then
		SurfaceGui = Instance.new("SurfaceGui")
		SurfaceGui.Name = GuiName
		SurfaceGui.Parent = HitPart
		SurfaceGui.Face = face
		SurfaceGui.Adornee = HitPart
		SurfaceGui.CanvasSize = Vector2.new(2048, 2048)
		SurfaceGui.LightInfluence = 1
		SurfaceGui.AlwaysOnTop = false
		SurfaceGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		SurfaceGui.ClipsDescendants = true
		SurfaceGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		SurfaceGui.PixelsPerStud = 50

		ContainerFrame = Instance.new("Frame")
		ContainerFrame.Name = "Container"
		ContainerFrame.Parent = SurfaceGui
		ContainerFrame.BackgroundTransparency = 1
		ContainerFrame.Size = UDim2.fromScale(1, 1)
		ContainerFrame.ClipsDescendants = true
	end

	local pixelSize = math.max(2, math.floor(Size * SurfaceGui.PixelsPerStud))
	local BulletHoleFrame = Instance.new("Frame")
	BulletHoleFrame.Name = "BulletHoleFrame"
	BulletHoleFrame.Parent = ContainerFrame
	BulletHoleFrame.BackgroundTransparency = 1
	BulletHoleFrame.BorderSizePixel = 0
	BulletHoleFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	BulletHoleFrame.Position = UDim2.new(RelX, 0, RelY, 0)
	BulletHoleFrame.Size = UDim2.new(0, pixelSize, 0, pixelSize)
	BulletHoleFrame:SetAttribute("CreationTime", tick())

	local BulletHoleImage = Instance.new("ImageLabel")
	BulletHoleImage.Name = "BulletHoleImage"
	BulletHoleImage.Parent = BulletHoleFrame
	BulletHoleImage.BackgroundTransparency = 1
	BulletHoleImage.SizeConstraint = Enum.SizeConstraint.RelativeXY
	BulletHoleImage.Size = UDim2.fromScale(1, 1)
	BulletHoleImage.Position = UDim2.fromScale(0.5, 0.5)
	BulletHoleImage.AnchorPoint = Vector2.new(0.5, 0.5)

	local Decals = MaterialHit:FindFirstChild("Hit") and MaterialHit.Hit:GetChildren() or {}
	if #Decals > 0 then
		local Dec = RList(Decals)
		BulletHoleImage.Image = Dec.Texture or Dec.Image or GetBulletHoleTextureForMaterial(MaterialHole)
		if not MaterialHit:FindFirstChild("DontRecolor") then
			BulletHoleImage.ImageColor3 = HitPartColor
		end
		BulletHoleImage.ImageTransparency = Dec.Transparency or 0
	else
		BulletHoleImage.Image = GetBulletHoleTextureForMaterial(MaterialHole)
	end

	if MaterialHit:FindFirstChild("FlashDecals") then
		local bg = Instance.new("BillboardGui")
		bg.Adornee = Attachment
		bg.Parent = Attachment

		local FlashDecals = MaterialHit.FlashDecals.Hit:GetChildren()
		local flash = RList(FlashDecals):Clone()

		local sizeValue = flash:FindFirstChild("Size")
		local flashsize = sizeValue and RandF(sizeValue.MinValue, sizeValue.MaxValue) or RandF(0.8, 1.25)
		bg.Size = UDim2.new(flashsize, 0, flashsize, 0)

		local trans = flash:FindFirstChild("Trans")
		if trans then
			flash.ImageTransparency = RandF(trans.MinValue, trans.MaxValue)
		end

		flash.Visible = true
		flash.Rotation = random(0, 360)
		flash.Size = UDim2.new(0.05, 0, 0.05, 0)

		local dur = flash:FindFirstChild("Duration") and flash.Duration.Value or 0.07
		flash.Parent = bg
		flash:TweenSize(UDim2.new(1, 0, 1, 0), "Out", "Quad", dur * 2)
		Debris:AddItem(bg, dur)
	end

	CleanupOldBulletHoles(ContainerFrame, GameConfig.maxBulletHolesPerSurface)

	task.spawn(function()
		task.wait(GameConfig.partBulletHoleFadeDelay)
		if not BulletHoleImage or not BulletHoleImage.Parent then return end

		local tween = TweenService:Create(
			BulletHoleImage,
			TweenInfo.new(GameConfig.partBulletHoleFadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ImageTransparency = 1}
		)
		tween:Play()
		tween.Completed:Wait()

		if BulletHoleFrame and BulletHoleFrame.Parent then
			BulletHoleFrame:Destroy()
		end
	end)
end

local function IsHeadPart(HitPart)
	if not HitPart then return false end

	local parentModel = HitPart.Parent
	if parentModel then
		local humanoid = parentModel:FindFirstChildOfClass("Humanoid")
		if humanoid then
			local head = parentModel:FindFirstChild("Head")
			if head then
				return HitPart == head
			end
		end
	end

	return HitPart.Name == "Head"
end

function Hitmarker.HitEffect(Position, HitPart, Normal, TerrainMaterial, BloodParams)
	if not HitPart then
		warn("HitPart is nil. Skipping HitEffect.")
		return
	end

	if not HitPart:IsA("BasePart") and not HitPart:IsA("Terrain") then
		warn(string.format("HitPart is a %s, not a BasePart/Terrain. Skipping HitEffect.", HitPart.ClassName))
		return
	end

	local isTerrain = HitPart:IsA("Terrain")
	local Material = isTerrain and (TerrainMaterial or Enum.Material.Grass) or HitPart.Material

	local Attachment = Instance.new("Attachment")
	Attachment.CFrame = CFrame.new(Position, Position + Normal)
	Attachment.Parent = workspace.Terrain

	local EffectType = "Stone"
	local MaterialHole = "Concrete"

	if not isTerrain then
		local isHead = IsHeadPart(HitPart)
		local isCharacter = IsCharacterPart(HitPart) or (HitPart.Parent and HitPart.Parent:IsA("Accessory"))

		if isHead or isCharacter then
			local isReplay = (BloodParams ~= nil)
			local usedSplat = BloodSplat(Position, HitPart, Normal, isReplay, BloodParams and BloodParams.Splat)
			local usedWound = ApplyWoundDecal(Position, Normal, HitPart, BloodParams and BloodParams.Wound)
			local Attachment2 = Instance.new("Attachment")
			Attachment2.CFrame = CFrame.new(Position, Position + Normal)
			Attachment2.Parent = workspace.Terrain
			CreateEffect(isHead and "Headshot" or "Hit", Attachment2, HitPart)
			return BloodParams or { Splat = usedSplat, Wound = usedWound }
		end
	end

	if Material == Enum.Material.Wood or Material == Enum.Material.WoodPlanks then
		EffectType = "Wood"
		MaterialHole = "Wood"
	elseif Material == Enum.Material.Metal or Material == Enum.Material.CorrodedMetal
		or Material == Enum.Material.DiamondPlate or Material == Enum.Material.Neon
		or Material == Enum.Material.Salt then
		EffectType = "Metal"
		MaterialHole = "Metal"
	elseif Material == Enum.Material.Concrete or Material == Enum.Material.Plastic
		or Material == Enum.Material.SmoothPlastic then
		EffectType = "Stone"
		MaterialHole = "Concrete"
	elseif Material == Enum.Material.Grass or Material == Enum.Material.Ground
		or Material == Enum.Material.LeafyGrass or Material == Enum.Material.Mud then
		EffectType = "Ground"
		MaterialHole = "Grass"
	elseif Material == Enum.Material.Sand or Material == Enum.Material.Fabric
		or Material == Enum.Material.Snow then
		EffectType = "Sand"
		MaterialHole = "Sand"
	elseif Material == Enum.Material.Foil or Material == Enum.Material.Ice
		or Material == Enum.Material.Glass or Material == Enum.Material.ForceField then
		EffectType = "Glass"
		MaterialHole = "Glass"
	elseif Material == Enum.Material.Water then
		EffectType = "Water"
		MaterialHole = "Water"
	elseif Material == Enum.Material.Rock or Material == Enum.Material.Sandstone
		or Material == Enum.Material.Limestone or Material == Enum.Material.Basalt then
		EffectType = "Stone"
		MaterialHole = "Concrete"
	end

	if not isTerrain and HitPart.Name == "Glass" then
		EffectType = "Glass"
	end

	CreateEffect(EffectType, Attachment, HitPart)

	if isTerrain then return end

	if MaterialFolder then
		if HitPart.Name == "Glass" or CollectionService:HasTag(HitPart, "BreakableGlass") then
			return
		end

		if OverrideSurfaceGUIBulletHoles then
			CreatePartBasedBulletHole(HitPart, MaterialHole, Attachment, Position, Normal)
		else
			CreateSurfaceGuiBulletHole(HitPart, Position + Normal * 0.05, Material)
		end
	end
end

return Hitmarker