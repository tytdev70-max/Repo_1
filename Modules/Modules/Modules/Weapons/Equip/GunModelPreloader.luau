local ContentProvider = game:GetService("ContentProvider")

local GunModelPreloader = {}

local preRiggedCache = {}

local hasPreloaded = false
function GunModelPreloader.PreloadAllGunModels(assets, camera, storageCFrame, weldMod)
	if hasPreloaded then return end
	hasPreloaded = true
	
	local weaponModels = assets:FindFirstChild("WeaponModels")
	if not weaponModels then return end

	local BATCH_SIZE  = 4
	local BATCH_DELAY = 0.1

	task.spawn(function()
		local allModels = {}
		for _, modelTemplate in ipairs(weaponModels:GetChildren()) do
			if modelTemplate:IsA("Model") then
				table.insert(allModels, modelTemplate)
			end
		end

		local totalBatches = math.ceil(#allModels / BATCH_SIZE)
		local totalAssets  = 0

		for batchStart = 1, #allModels, BATCH_SIZE do
			local batchIndex  = math.ceil(batchStart / BATCH_SIZE)
			local batchAssets = {}
			local tempClones  = {}

			for i = batchStart, math.min(batchStart + BATCH_SIZE - 1, #allModels) do
				local modelTemplate = allModels[i]

				local tempClone = modelTemplate:Clone()
				for _, part in ipairs(tempClone:GetDescendants()) do
					if part:IsA("BasePart") then
						part.CFrame     = storageCFrame
						part.CanCollide = false
						part.CastShadow = false
						part.Anchored   = true
					end
				end
				tempClone.Parent = camera
				table.insert(tempClones, tempClone)

				for _, desc in ipairs(tempClone:GetDescendants()) do
					if desc:IsA("SurfaceAppearance")
						or desc:IsA("SpecialMesh")
						or (desc:IsA("MeshPart") and desc.MeshId  ~= "")
						or (desc:IsA("Decal")    and desc.Texture ~= "")
						or (desc:IsA("Texture")  and desc.Texture ~= "") then
						table.insert(batchAssets, desc)
					end
				end

				do
					local starterPack = game:GetService("StarterPack")
					local tool = starterPack:FindFirstChild(modelTemplate.Name)
					local weaponModule = tool
						and tool:FindFirstChild("SPH_Weapon")
						and tool.SPH_Weapon:FindFirstChild("WeaponStats")

					if weaponModule then
						local ok, stats = pcall(require, weaponModule)
						if ok and stats and not stats.disableAutoRigging then
							local riggedClone = modelTemplate:Clone()
							pcall(function()
								weldMod.WeldModel(riggedClone, riggedClone.Grip, false)
								for _, partName in ipairs(stats.rigParts or {}) do
									if riggedClone:FindFirstChild(partName) then
										local existing = riggedClone.Grip:FindFirstChild("Grip_" .. partName)
										if existing then existing:Destroy() end
										local motor  = weldMod.M6D(riggedClone.Grip, riggedClone[partName])
										motor.Name   = partName
										motor.Parent = riggedClone.Grip
									end
								end
								for _, desc in ipairs(riggedClone:GetDescendants()) do
									if desc:IsA("BasePart") then
										desc.CanCollide = false
										desc.Anchored   = true
										desc.CFrame     = storageCFrame
									end
								end
							end)
							riggedClone.Parent = camera
							preRiggedCache[modelTemplate.Name] = riggedClone
						end
					end
				end
			end

			if #batchAssets > 0 then
				local ok, err = pcall(function()
					ContentProvider:PreloadAsync(batchAssets)
				end)

				if ok then
					totalAssets += #batchAssets
				end
			end

			for _, clone in ipairs(tempClones) do
				clone:Destroy()
			end

			if batchStart + BATCH_SIZE <= #allModels then
				task.wait(BATCH_DELAY)
			end
		end	
	end)
end

function GunModelPreloader.GetRiggedClone(modelName)
	return preRiggedCache[modelName]
end

return GunModelPreloader