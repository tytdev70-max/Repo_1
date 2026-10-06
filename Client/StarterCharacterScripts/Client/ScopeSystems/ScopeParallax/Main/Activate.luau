--!strict

--// Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--// Modules
local ScopeConfig = require(script.Parent:WaitForChild("ScopeConfig"))

local Assets = ReplicatedStorage:WaitForChild("SPH_Assets")
local Modules = Assets:WaitForChild("Modules")
local Attachments = require(Modules.Weapons.Attachments.SPHAttachments)
local WeaponState = require(Modules.Weapons.Core.WeaponState)

--// Types
type ScopeSettings = {
	focusSensitivity: number,
	eyeboxCurve: number,
	lightSensitivity: number,
	lightDeadzone: number,
	ocularCASensitivity: number,
	ocularCADeadzone: number,
	objectiveCASensitivity: number,
	objectiveCADeadzone: number,
	eyeReliefOffset: number,
	ocularLensScale: number,
	objectiveLensScale: number,
	useGlassEffect: boolean,
	glassOffset: number,
	glassColor: Color3,
	glassTransparency: number,
	glassZoomFactor: number,
}

type PatcherLike = {
	aimpartZOffset: number,
	cleanupParts: { Instance },
	parentingMethod: (scopeFocusPart: Instance) -> (),
}

type LensTextures = {
	ocular: Texture,
	objective: Texture,
	light: Texture,
	ocularCA: Texture,
	objectiveCA: Texture,
}

local Activate = {}

--// Functions
local function getCurrentCamera(): Camera
	local existingCamera = workspace.CurrentCamera
	if existingCamera then
		return existingCamera
	end

	RunService:GetPropertyChangedSignal("CurrentCamera"):Wait()
	return workspace.CurrentCamera :: Camera
end

local function getTexture(instance: Instance, name: string): Texture
	return instance:FindFirstChild(name) :: Texture
end

local function loadLensTextures(part: BasePart): LensTextures
	local names = ScopeConfig.lensTextureNames
	return {
		ocular = getTexture(part, names.ocular),
		objective = getTexture(part, names.objective),
		light = getTexture(part, names.light),
		ocularCA = getTexture(part, names.ocularChromaticAberration),
		objectiveCA = getTexture(part, names.objectiveChromaticAberration),
	}
end

local function resolveAimPart(gunModel: Model): BasePart?
	local vars = WeaponState.get()
	local sightIndex = (vars :: any).sightIndex or 1
	local prefix = ScopeConfig.aimPartPrefix

	local attachmentAimPart = Attachments:GetAimPart(gunModel, sightIndex)
	if attachmentAimPart and attachmentAimPart:IsA("BasePart") then
		return attachmentAimPart
	end

	local indexedAimPart = gunModel:FindFirstChild(prefix .. sightIndex)
	if indexedAimPart and indexedAimPart:IsA("BasePart") then
		return indexedAimPart
	end

	local defaultAimPart = gunModel:FindFirstChild(prefix)
	if defaultAimPart and defaultAimPart:IsA("BasePart") then
		return defaultAimPart
	end

	return nil
end

local function findZoomPresets(scopeFocusPart: Instance): (ScopeSettings?, ScopeSettings?, ScopeSettings?)
	local presetsFolder = scopeFocusPart:FindFirstChild(ScopeConfig.presetsFolderName)
	if not presetsFolder then
		return nil, nil, nil
	end

	local tiers: { [string]: ScopeSettings? } = {}

	for _, child in presetsFolder:GetChildren() do
		if not child:IsA("ModuleScript") then
			continue
		end

		local lowerName = string.lower(child.Name)
		local ok, result = pcall(require, child)

		if not ok then
			warn("[ScopeParallax] Failed to load preset " .. child:GetFullName() .. ": " .. tostring(result))
			continue
		end

		for tier, keyword in ScopeConfig.presetTierKeywords do
			if string.find(lowerName, keyword) then
				tiers[tier] = result :: ScopeSettings
				break
			end
		end
	end

	return tiers.Low, tiers.Medium, tiers.High
end

local function lerpSettings(a: ScopeSettings, b: ScopeSettings, alpha: number): ScopeSettings
	local blended = table.clone(a :: any)
	for key, value in pairs(a :: any) do
		local other = (b :: any)[key]
		if typeof(value) == "number" and typeof(other) == "number" then
			blended[key] = value + (other - value) * alpha
		end
	end
	return blended :: ScopeSettings
end

--// Variables
local camera: Camera = getCurrentCamera()

local settings: ScopeSettings? = nil
local currentGun: Model? = nil
local aimPart: BasePart? = nil
local scopeConnect: RBXScriptConnection? = nil
local watchedSourceConnect: RBXScriptConnection? = nil

local scopeFocusPart: BasePart? = nil
local lensTextures: LensTextures? = nil

local eyeReliefDistance = 0

local glassPart: Part? = nil

local activeReticleImage: GuiObject? = nil
local activeReticleBaseTransparency: number? = nil

local baseSettings: ScopeSettings? = nil
local lowPreset: ScopeSettings? = nil
local mediumPreset: ScopeSettings? = nil
local highPreset: ScopeSettings? = nil

local function getZoomAlpha(): number
	local vars = WeaponState.get()
	local wepStats = (vars :: any).wepStats
	if not wepStats or not wepStats.aimFovMin or not wepStats.aimFovMax then
		return 0
	end

	local minFOV, maxFOV = wepStats.aimFovMin, wepStats.aimFovMax
	if maxFOV <= minFOV then
		return 0
	end

	return math.clamp((maxFOV - camera.FieldOfView) / (maxFOV - minFOV), 0, 1)
end

local function refreshDynamicSettings()
	if not baseSettings then
		return
	end
	if not lowPreset and not mediumPreset and not highPreset then
		return
	end

	local alpha = getZoomAlpha()

	if lowPreset and mediumPreset and highPreset then
		if alpha <= 0.5 then
			settings = lerpSettings(lowPreset, mediumPreset, alpha * 2)
		else
			settings = lerpSettings(mediumPreset, highPreset, (alpha - 0.5) * 2)
		end
	elseif lowPreset and highPreset then
		settings = lerpSettings(lowPreset, highPreset, alpha)
	elseif mediumPreset then
		settings = mediumPreset
	elseif lowPreset then
		settings = lowPreset
	elseif highPreset then
		settings = highPreset
	end
end

local function updateFocus()
	refreshDynamicSettings()

	if not currentGun or not settings or not aimPart or not scopeFocusPart or not lensTextures then
		return
	end
	if currentGun.Parent == nil then
		return
	end

	local scopePart = scopeFocusPart
	local lens = lensTextures

	local ocuScale = (ScopeConfig.defaultOcularScale + settings.eyeReliefOffset) * settings.ocularLensScale
	local objScale = (ScopeConfig.defaultObjectiveScale - settings.eyeReliefOffset) * settings.objectiveLensScale

	local aimpartOffset = aimPart.CFrame:ToObjectSpace(scopePart.CFrame)
	local adjustedOffset = CFrame.new(aimpartOffset.Position.X, -aimpartOffset.Position.Y, 0)

	local objLensCFrame = scopePart.CFrame * CFrame.new(-scopePart.Size.X / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0)
	local ocuLensCFrame = scopePart.CFrame * CFrame.new(scopePart.Size.X / 2, 0, 0) * CFrame.Angles(0, -math.pi / 2, 0) * adjustedOffset

	local ocuLensOffset = camera.CFrame:ToObjectSpace(ocuLensCFrame)
	local objLensOffset = objLensCFrame:ToObjectSpace(camera.CFrame)

	local objRecip = 1 / eyeReliefDistance * objScale
	local ocuRecip = 1 / eyeReliefDistance * ocuScale

	local ocuRelief = eyeReliefDistance * 2 + ocuLensOffset.Position.Z
	local ocuSize = scopePart.Size.Y * ocuRelief * ocuRecip
	local ocuOffset = (scopePart.Size.Y * 0.5) * (ocuRelief * ocuRecip - 1)

	local ocuHoz = math.tan(-ocuLensOffset.Position.X * settings.focusSensitivity) / settings.eyeboxCurve
	local ocuVert = math.tan(ocuLensOffset.Position.Y * settings.focusSensitivity) / settings.eyeboxCurve

	local ocuU = ocuHoz + ocuOffset
	local ocuV = ocuVert + ocuOffset

	local objRelief = -ocuLensOffset.Position.Z
	local objSize = scopePart.Size.Y * objRelief * objRecip
	local objOffset = scopePart.Size.Y * 0.5 * (objRelief * objRecip - 1)

	local objU = objOffset + objLensOffset.Position.X
	local objV = objOffset + objLensOffset.Position.Y

	local dist = -math.abs(ocuHoz + ocuVert)
	local lensFocus = -math.abs(eyeReliefDistance - objRelief)

	lens.ocular.OffsetStudsU = ocuU
	lens.ocular.OffsetStudsV = ocuV
	lens.ocular.StudsPerTileU = ocuSize
	lens.ocular.StudsPerTileV = ocuSize

	lens.objective.OffsetStudsU = objU
	lens.objective.OffsetStudsV = objV
	lens.objective.StudsPerTileU = objSize
	lens.objective.StudsPerTileV = objSize

	local lightTransparency = math.clamp(1 + dist * settings.lightSensitivity + settings.lightDeadzone, 0, 1)
	lens.light.Transparency = lightTransparency

	if activeReticleImage and activeReticleImage.Parent then
		local baseTransparency = activeReticleBaseTransparency or 0
		local coverage = 1 - lightTransparency
		activeReticleImage.ImageTransparency = math.clamp(baseTransparency + coverage * (1 - baseTransparency), 0, 1)
	end

	lens.ocularCA.OffsetStudsU = ocuU
	lens.ocularCA.OffsetStudsV = ocuV
	lens.ocularCA.StudsPerTileU = ocuSize
	lens.ocularCA.StudsPerTileV = ocuSize
	lens.ocularCA.Transparency = math.max(0, 1 + dist * settings.ocularCASensitivity + lensFocus + settings.ocularCADeadzone)

	lens.objectiveCA.OffsetStudsU = objU
	lens.objectiveCA.OffsetStudsV = objV
	lens.objectiveCA.StudsPerTileU = objSize
	lens.objectiveCA.StudsPerTileV = objSize
	lens.objectiveCA.Transparency = 1 + dist * settings.objectiveCASensitivity + lensFocus + settings.objectiveCADeadzone

	if glassPart then
		glassPart.CFrame = scopePart.CFrame * CFrame.new(scopePart.Size.X / 2 - settings.glassOffset, 0, 0)

		local maxDist = scopePart.Size.Y
		local ocuX = -ocuLensOffset.Position.X
		local ocuY = ocuLensOffset.Position.Y

		if math.abs(ocuX) > maxDist or math.abs(ocuY) > maxDist then
			glassPart.Transparency = 1
		else
			glassPart.Transparency = settings.glassTransparency
		end
	end
end

function Activate.stop(fullReset: boolean?)
	if scopeConnect then
		scopeConnect:Disconnect()
		scopeConnect = nil
	end

	if watchedSourceConnect then
		watchedSourceConnect:Disconnect()
		watchedSourceConnect = nil
	end

	if activeReticleImage and activeReticleImage.Parent and activeReticleBaseTransparency then
		activeReticleImage.ImageTransparency = activeReticleBaseTransparency
	end
	activeReticleImage = nil
	activeReticleBaseTransparency = nil

	if glassPart and glassPart.Parent then
		glassPart:Destroy()
	end
	glassPart = nil

	if scopeFocusPart and scopeFocusPart.Parent then
		scopeFocusPart:Destroy()
	end

	scopeFocusPart = nil
	lensTextures = nil
	settings = nil
	baseSettings = nil
	lowPreset, mediumPreset, highPreset = nil, nil, nil

	if fullReset then
		currentGun = nil
		aimPart = nil
	end
end

local function findAssociatedReticleImage(part: BasePart, model: Model): (GuiObject?, number?)
	local searchRoots = {}
	if part.Parent then
		table.insert(searchRoots, part.Parent)
	end
	table.insert(searchRoots, model)

	for _, root in searchRoots do
		for _, descendant in root:GetDescendants() do
			if descendant.Name ~= ScopeConfig.reticlePartName then
				continue
			end

			local surfaceGui = descendant:FindFirstChildWhichIsA("SurfaceGui")
			local frame = surfaceGui and surfaceGui:FindFirstChild("Frame")
			if not frame then
				continue
			end

			for _, imageName in ScopeConfig.reticleImageNames do
				local image = frame:FindFirstChild(imageName)
				if image then
					return image :: GuiObject, (image :: GuiObject).ImageTransparency
				end
			end
		end
	end

	return nil, nil
end

local function ActivateScopeFocusPart(part: BasePart, model: Model, Patcher: PatcherLike): boolean
	local settingsModule = part:FindFirstChildWhichIsA("ModuleScript")
	if not settingsModule then
		return false
	end

	local activeAttachments = Attachments:GetActive(model)
	local opticsAttachment = activeAttachments and activeAttachments[ScopeConfig.opticsAttachmentSlot]
	if opticsAttachment and opticsAttachment.model then
		local preferredScope = opticsAttachment.model:FindFirstChild(ScopeConfig.scopeFocusPartName, true)
		if preferredScope and preferredScope ~= part then
			return false
		end
	end

	local ok, loadedSettings = pcall(require, settingsModule :: ModuleScript)
	if not ok then
		warn("[ScopeParallax] Failed to load SCOPE_FOCUS settings for " .. part:GetFullName() .. ": " .. tostring(loadedSettings))
		return false
	end

	Activate.stop()

	aimPart = resolveAimPart(model) or aimPart
	if not aimPart then
		return false
	end

	local aimpartPosition = (aimPart.CFrame * CFrame.new(0, 0, Patcher.aimpartZOffset)).Position

	baseSettings = loadedSettings :: ScopeSettings
	settings = baseSettings
	lowPreset, mediumPreset, highPreset = findZoomPresets(part)

	scopeFocusPart = part
	lensTextures = loadLensTextures(part)
	lensTextures.ocular.Transparency = 0
	lensTextures.objective.Transparency = 0
	part.Transparency = 1

	local offsetPosition = (part.CFrame * CFrame.new(part.Size.X / 2, 0, 0)).Position
	eyeReliefDistance = (aimpartPosition - offsetPosition).Magnitude

	local watchedSource = part.Parent
	if watchedSource then
		watchedSourceConnect = watchedSource.Destroying:Connect(function()
			if scopeFocusPart == part then
				Activate.stop()
			end
		end)
	end

	activeReticleImage, activeReticleBaseTransparency = findAssociatedReticleImage(part, model)

	Patcher.parentingMethod(part)

	if settings.useGlassEffect then
		local newGlassPart = Instance.new("Part")
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = newGlassPart

		newGlassPart.CFrame = part.CFrame * CFrame.new(part.Size.X / 2 - settings.glassOffset, 0, 0)
		newGlassPart.Material = Enum.Material.Glass
		newGlassPart.Color = settings.glassColor
		newGlassPart.Transparency = settings.glassTransparency
		newGlassPart.CanCollide = false

		local scopePos = (part.CFrame * CFrame.new(part.Size.X / 2, 0, 0)).Position

		local partDistance = (aimpartPosition - scopePos).Magnitude
		local glassDistance = (aimpartPosition - newGlassPart.Position).Magnitude

		local glassSize = part.Size.Z * (glassDistance / partDistance)
		local glassDistToScope = (newGlassPart.Position - scopePos).Magnitude

		newGlassPart.Size = Vector3.new(settings.glassZoomFactor * (1 + glassDistToScope ^ 2), glassSize, glassSize)
		newGlassPart.Parent = currentGun

		glassPart = newGlassPart
	end

	scopeConnect = RunService.PreRender:Connect(updateFocus)

	return true
end

--// Public Functions
function Activate.start(model: Model, Patcher: PatcherLike): { Instance }
	camera = getCurrentCamera()

	scopeFocusPart = nil
	lensTextures = nil
	currentGun = model
	aimPart = resolveAimPart(model)

	for _, part in model:GetDescendants() do
		if part.Name == ScopeConfig.scopeFocusPartName and part:IsA("BasePart") then
			if ActivateScopeFocusPart(part, model, Patcher) then
				table.insert(Patcher.cleanupParts, part)
			end
		end
	end

	model.DescendantAdded:Connect(function(descendant: Instance)
		if currentGun ~= model then
			return
		end
		if descendant.Name == ScopeConfig.scopeFocusPartName and descendant:IsA("BasePart") then
			if ActivateScopeFocusPart(descendant, model, Patcher) then
				table.insert(Patcher.cleanupParts, descendant)
			end
		end
	end)

	return Patcher.cleanupParts
end

return Activate