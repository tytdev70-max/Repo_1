local module = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local GameConfig = require(ReplicatedStorage.SPH_Assets.GameConfig)

local AID = "http://www.roblox.com/asset/?id="

local function ResolveAssetId(valueObj)
	if not valueObj then return nil end
	if valueObj:IsA("StringValue") then
		local v = valueObj.Value
		if v == "" then return nil end
		if v:match("^rbxassetid://") then
			return v
		else
			return "rbxassetid://" .. v
		end
	elseif valueObj:IsA("IntValue") or valueObj:IsA("NumberValue") then
		return "rbxassetid://" .. tostring(math.floor(valueObj.Value))
	end
	return nil
end

local function CreateTerrainBloodDecal(pos, normal, size)
	if not GameConfig.bloodEnabled or not GameConfig.bloodSplatEnabled then return end

	local chance = math.random(GameConfig.bloodSplatSizeMin, GameConfig.bloodSplatSizeMax)

	local ImageFolder = script:FindFirstChild("Blood")
	if not ImageFolder then return end

	local Images = ImageFolder:GetChildren()
	local validImages = {}
	for _, img in ipairs(Images) do
		local id = ResolveAssetId(img)
		if id then
			table.insert(validImages, id)
		end
	end
	if #validImages == 0 then return end

	local randomImage = validImages[math.random(1, #validImages)]

	local decalPart = Instance.new("Part")
	decalPart.Name = "TerrainBloodDecal"

	local decalSize = chance / 10
	decalPart.Size = Vector3.new(decalSize, decalSize, 0.1)
	local centeredPos = pos - normal * 0.05
	decalPart.CFrame = CFrame.lookAt(centeredPos, centeredPos + normal)

	decalPart.Anchored = true
	decalPart.CanCollide = false
	decalPart.Transparency = 1
	decalPart.Material = Enum.Material.SmoothPlastic
	decalPart.Parent = workspace

	local decal = Instance.new("Decal")
	decal.Face = Enum.NormalId.Front
	decal.Texture = randomImage
	decal.Color3 = GameConfig.bloodDecalColor
	decal.Transparency = 0
	decal.Parent = decalPart

	decalPart.CFrame = decalPart.CFrame * CFrame.Angles(0, 0, math.rad(math.random(0, 360)))

	if GameConfig.decalSurfaceRemoveDelay > 0 then
		task.spawn(function()
			task.wait(GameConfig.decalSurfaceRemoveDelay)
			if GameConfig.decalSurfaceFadeTime > 0 and decalPart and decalPart.Parent then
				local tweenInfo = TweenInfo.new(GameConfig.decalSurfaceFadeTime, Enum.EasingStyle.Linear)
				local tween = TweenService:Create(decal, tweenInfo, {Transparency = 1})
				tween:Play()
				tween.Completed:Wait()
			end
			if decalPart and decalPart.Parent then
				decalPart:Destroy()
			end
		end)
	end
end

local function FadeThenRemove(guiInstance, delay)
	if not guiInstance then return end
	local startDelay = math.max(0, delay or 0)
	task.spawn(function()
		if startDelay > 0 then
			wait(startDelay)
		end
		if not guiInstance or not guiInstance.Parent then return end
		if GameConfig.decalSurfaceFadeTime <= 0 then
			if guiInstance and guiInstance.Parent then
				guiInstance:Destroy()
			end
			return
		end
		local tweenInfo = TweenInfo.new(GameConfig.decalSurfaceFadeTime, Enum.EasingStyle.Linear, Enum.EasingDirection.Out)
		if guiInstance:IsA("ImageLabel") or guiInstance:IsA("ImageButton") then
			local success, err = pcall(function()
				local tw = TweenService:Create(guiInstance, tweenInfo, {ImageTransparency = 1})
				tw:Play()
				tw.Completed:Wait()
			end)
		else
			local images = {}
			for _, child in ipairs(guiInstance:GetDescendants()) do
				if child:IsA("ImageLabel") or child:IsA("ImageButton") then
					table.insert(images, child)
				end
			end
			if #images > 0 then
				local tweens = {}
				for _, img in ipairs(images) do
					local ok, _ = pcall(function()
						local tw = TweenService:Create(img, tweenInfo, {ImageTransparency = 1})
						tw:Play()
						table.insert(tweens, tw)
					end)
				end
				for _, tw in ipairs(tweens) do
					pcall(function()
						tw.Completed:Wait()
					end)
				end
			else
				wait(GameConfig.decalSurfaceFadeTime)
			end
		end
		if guiInstance and guiInstance.Parent then
			guiInstance:Destroy()
		end
	end)
end

function ReturnNormal(PartCF, RayNorm)
	local localNorm = PartCF:VectorToObjectSpace(RayNorm).Unit
	local absX, absY, absZ = math.abs(localNorm.X), math.abs(localNorm.Y), math.abs(localNorm.Z)

	if absX >= absY and absX >= absZ then
		if localNorm.X > 0 then
			return "Right", Enum.NormalId.Right.Value
		else
			return "Left", Enum.NormalId.Left.Value
		end
	elseif absY >= absX and absY >= absZ then
		if localNorm.Y > 0 then
			return "Top", Enum.NormalId.Top.Value
		else
			return "Bottom", Enum.NormalId.Bottom.Value
		end
	else
		if localNorm.Z > 0 then
			return "Back", Enum.NormalId.Back.Value
		else
			return "Front", Enum.NormalId.Front.Value
		end
	end
end

function SecondaryTex(OldFace, LastPos, Dir, part, pos, lastABSS, lastABSP, chance, Texture, size)
	local Face, Val
	if Dir == 1 then
		if OldFace == "Front" then
			Face, Val = "Right", Enum.NormalId.Right.Value
		elseif OldFace == "Right" then
			Face, Val = "Back", Enum.NormalId.Back.Value
		elseif OldFace == "Left" then
			Face, Val = "Front", Enum.NormalId.Front.Value
		elseif OldFace == "Back" then
			Face, Val = "Left", Enum.NormalId.Left.Value
		end
	else
		if OldFace == "Front" then
			Face, Val = "Left", Enum.NormalId.Left.Value
		elseif OldFace == "Right" then
			Face, Val = "Front", Enum.NormalId.Front.Value
		elseif OldFace == "Left" then
			Face, Val = "Back", Enum.NormalId.Back.Value
		elseif OldFace == "Back" then
			Face, Val = "Right", Enum.NormalId.Right.Value
		end
	end

	if not Face then
		return
	end

	local GuiName = string.format("BloodDecalGui_%s", Face)
	local surface = part:FindFirstChild(GuiName)
	local frame

	if surface then
		frame = surface:FindFirstChild("Framey")
	end

	if not surface then
		surface = Instance.new("SurfaceGui", part)
		surface.Name = GuiName
		surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		surface.Face = Val

		local SizeWidth, SizeHeight = part.Size.X, part.Size.Y
		if Face == "Top" or Face == "Bottom" then
			SizeWidth, SizeHeight = part.Size.Z, part.Size.X
		elseif Face == "Right" or Face == "Left" then
			SizeWidth, SizeHeight = part.Size.Z, part.Size.Y
		end

		surface.CanvasSize = Vector2.new(SizeWidth * GameConfig.bloodSplatCanvasSize, SizeHeight * GameConfig.bloodSplatCanvasSize)

		frame = Instance.new("Frame", surface)
		frame.Name = "Framey"
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.BackgroundTransparency = 1
		frame.ClipsDescendants = true
	end

	if not frame then return end

	local Tex = Instance.new("ImageLabel", frame)
	Tex.Image = Texture
	Tex.Size = UDim2.new(0, chance, 0, chance)
	Tex.BackgroundTransparency = 1
	Tex.ImageColor3 = GameConfig.bloodDecalColor

	if Dir == 0 then
		Tex.Position = UDim2.new(1, lastABSP, LastPos.Y.Scale, LastPos.Y.Offset)
	else
		Tex.Position = UDim2.new(0, -(lastABSS - lastABSP), LastPos.Y.Scale, LastPos.Y.Offset)
	end

	if GameConfig.decalSurfaceRemoveDelay > 0 then
		FadeThenRemove(Tex, GameConfig.decalSurfaceRemoveDelay)
	end
end

function module.MakeDecalOnSurface(package, normal, part, pos, size, forcedImageId, forcedChance)
	if not part or not package then return end

	if package == "Blood" and (not GameConfig.bloodEnabled or not GameConfig.bloodSplatEnabled) then
		return
	end

	if part:IsA("Terrain") or part.ClassName == "Terrain" then
		CreateTerrainBloodDecal(pos, normal, size)
		return
	end

	if not part:IsDescendantOf(workspace) then return end

	local function isCharPart(p)
		if not p or not p.Parent then return false end

		local player = game.Players:GetPlayerFromCharacter(p.Parent)
		if player then return true end

		local parent = p.Parent
		for i = 1, 3 do
			if not parent then break end
			if parent:FindFirstChildOfClass("Humanoid") then return true end

			player = game.Players:GetPlayerFromCharacter(parent)
			if player then return true end

			parent = parent.Parent
		end

		return false
	end

	if isCharPart(part) then
		return
	end

	local ImageFolder = script:FindFirstChild(package)
	if not ImageFolder then
		warn("[BLOOD] Invalid package path:", package)
		return
	end

	local Images = ImageFolder:GetChildren()
	if #Images == 0 then
		warn("[BLOOD] No images in", ImageFolder:GetFullName())
		return
	end

	local validImages = {}
	for _, Image in ipairs(Images) do
		local id = ResolveAssetId(Image)
		if id then
			table.insert(validImages, id)
		end
	end
	if #validImages == 0 then
		warn("[BLOOD] No valid images in", ImageFolder:GetFullName())
		return
	end

	local ImageId = forcedImageId or validImages[math.random(1, #validImages)]
	local chance = forcedChance or math.random(GameConfig.bloodSplatSizeMin, GameConfig.bloodSplatSizeMax)

	local Face, Val
	local ok, r1, r2 = pcall(function() return ReturnNormal(part.CFrame, normal) end)
	if ok and r1 then
		Face, Val = r1, r2
	else
		local n = normal or Vector3.new(0, 0, 1)
		local ax, ay, az = math.abs(n.X), math.abs(n.Y), math.abs(n.Z)
		if ax >= ay and ax >= az then
			if n.X > 0 then Face, Val = "Right", Enum.NormalId.Right.Value else Face, Val = "Left", Enum.NormalId.Left.Value end
		elseif ay >= ax and ay >= az then
			if n.Y > 0 then Face, Val = "Top", Enum.NormalId.Top.Value else Face, Val = "Bottom", Enum.NormalId.Bottom.Value end
		else
			if n.Z > 0 then Face, Val = "Back", Enum.NormalId.Back.Value else Face, Val = "Front", Enum.NormalId.Front.Value end
		end
	end

	if not Face or not Val then
		Face, Val = "Front", Enum.NormalId.Front.Value
	end

	local SizeWidth = math.max(0.1, part.Size.X)
	local SizeHeight = math.max(0.1, part.Size.Y)
	if Face == "Top" or Face == "Bottom" then
		SizeWidth, SizeHeight = math.max(0.1, part.Size.Z), math.max(0.1, part.Size.X)
	elseif Face == "Right" or Face == "Left" then
		SizeWidth, SizeHeight = math.max(0.1, part.Size.Z), math.max(0.1, part.Size.Y)
	end

	local GuiName = string.format("BloodDecalGui_%s", Face)
	local surface = part:FindFirstChild(GuiName)
	local frame

	if surface then
		frame = surface:FindFirstChild("Framey")
	end

	if not surface then
		surface = Instance.new("SurfaceGui")
		surface.Name = GuiName
		surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		surface.Parent = part
		surface.CanvasSize = Vector2.new(SizeWidth * GameConfig.bloodSplatCanvasSize, SizeHeight * GameConfig.bloodSplatCanvasSize)
		surface.Face = Val

		frame = Instance.new("Frame")
		frame.Name = "Framey"
		frame.Parent = surface
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.BackgroundTransparency = 1
		frame.ClipsDescendants = true
	elseif not frame then
		frame = Instance.new("Frame")
		frame.Name = "Framey"
		frame.Parent = surface
		frame.Size = UDim2.new(1, 0, 1, 0)
		frame.BackgroundTransparency = 1
		frame.ClipsDescendants = true
	end

	if not frame then 
		warn("[BLOOD] Failed to create frame on part:", part.Name, "- Surface exists:", surface ~= nil)
		return 
	end

	local Tex = Instance.new("ImageLabel")
	Tex.Parent = frame
	Tex.Image = ImageId
	Tex.Size = UDim2.new(0, chance, 0, chance)
	Tex.BackgroundTransparency = 1
	Tex.ImageColor3 = GameConfig.bloodDecalColor
	Tex.ImageTransparency = 0

	pos = pos + normal * 0.01
	local Size = -(part.CFrame:ToObjectSpace(CFrame.new(pos))).Position

	if Face == "Front" then
		Tex.Position = UDim2.new(.5 + (Size.X / SizeWidth), -chance/2, .5 + (Size.Y / SizeHeight), -chance/2)
	elseif Face == "Back" then
		Tex.Position = UDim2.new(.5 - (Size.X / SizeWidth), -chance/2, .5 + (Size.Y / SizeHeight), -chance/2)
	elseif Face == "Right" then
		Tex.Position = UDim2.new(.5 + (Size.Z / SizeWidth), -chance/2, .5 + (Size.Y / SizeHeight), -chance/2)
	elseif Face == "Left" then
		Tex.Position = UDim2.new(.5 - (Size.Z / SizeWidth), -chance/2, .5 + (Size.Y / SizeHeight), -chance/2)
	elseif Face == "Top" then
		Tex.Position = UDim2.new(.5 + (Size.Z / SizeWidth), -chance/2, .5 - (Size.X / SizeHeight), -chance/2)
	elseif Face == "Bottom" then
		Tex.Position = UDim2.new(.5 + (Size.Z / SizeWidth), -chance/2, .5 + (Size.X / SizeHeight), -chance/2)
	end

	if Tex.AbsolutePosition.X > (surface.AbsoluteSize.X - chance) then
		SecondaryTex(Face, Tex.Position, 1, part, pos, surface.AbsoluteSize.X, Tex.AbsolutePosition.X, chance, ImageId, size)
	elseif Tex.AbsolutePosition.X < (chance / 2) then
		SecondaryTex(Face, Tex.Position, 0, part, pos, surface.AbsoluteSize.X, Tex.AbsolutePosition.X, chance, ImageId, size)
	end

	if GameConfig.decalSurfaceRemoveDelay > 0 then
		FadeThenRemove(Tex, GameConfig.decalSurfaceRemoveDelay)
	end

	return ImageId, chance
end

return module