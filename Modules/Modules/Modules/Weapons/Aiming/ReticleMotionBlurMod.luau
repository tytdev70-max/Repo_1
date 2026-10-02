--!strict

local ReticleMotionBlurMod = {}

local DEFAULT_TRAIL_COUNT = 3

export type BlurHandle = {
	sourceImage: GuiObject,
	trailImages: { GuiObject },
	lastScreenPos: Vector2?,
}

local function SetGhostTransparency(ghost: GuiObject, value: number)
	if ghost:IsA("ImageLabel") or ghost:IsA("ImageButton") then
		ghost.ImageTransparency = value
	else
		ghost.BackgroundTransparency = value
	end
end

function ReticleMotionBlurMod.Create(sightUI: GuiObject, trailCount: number?): BlurHandle
	local count = trailCount or DEFAULT_TRAIL_COUNT
	local trailImages = {}

	for i = 1, count do
		local ghost = sightUI:Clone()
		ghost.Name = sightUI.Name .. "_BlurGhost" .. i
		ghost.ZIndex = sightUI.ZIndex - i
		ghost.Active = false
		SetGhostTransparency(ghost, 1)
		ghost.Parent = sightUI.Parent
		table.insert(trailImages, ghost)
	end

	return {
		sourceImage = sightUI,
		trailImages = trailImages,
		lastScreenPos = nil,
	}
end

function ReticleMotionBlurMod.Update(
	handle: BlurHandle,
	screenPos: Vector2,
	dt: number,
	sensitivity: number,
	maxOffset: number,
	maxAlpha: number
)
	if not handle or not handle.sourceImage or not handle.sourceImage.Parent then return end
	if dt <= 0 then return end

	local lastScreenPos = handle.lastScreenPos
	handle.lastScreenPos = screenPos

	if not lastScreenPos then
		for _, ghost in ipairs(handle.trailImages) do
			SetGhostTransparency(ghost, 1)
		end
		return
	end

	local delta = screenPos - lastScreenPos
	local speed = delta.Magnitude / dt
	local intensity = math.clamp(speed * (sensitivity or 4), 0, 1)

	if intensity <= 0.001 then
		for _, ghost in ipairs(handle.trailImages) do
			SetGhostTransparency(ghost, 1)
		end
		return
	end

	local dir = delta.Magnitude > 1e-6 and delta.Unit or Vector2.zero
	local count = #handle.trailImages
	local resolvedMaxOffset = maxOffset or 0.05
	local resolvedMaxAlpha = maxAlpha or 0.55

	for i, ghost in ipairs(handle.trailImages) do
		local t = i / count
		local offset = -dir * resolvedMaxOffset * intensity * t
		ghost.Position = UDim2.fromScale(screenPos.X + offset.X, screenPos.Y + offset.Y)
		ghost.Size = handle.sourceImage.Size
		ghost.Rotation = handle.sourceImage.Rotation
		SetGhostTransparency(ghost, 1 - (resolvedMaxAlpha * intensity * (1 - t)))
	end
end

function ReticleMotionBlurMod.Reset(handle: BlurHandle?)
	if not handle then return end
	handle.lastScreenPos = nil
	for _, ghost in ipairs(handle.trailImages) do
		SetGhostTransparency(ghost, 1)
	end
end

function ReticleMotionBlurMod.Destroy(handle: BlurHandle?)
	if not handle then return end
	for _, ghost in ipairs(handle.trailImages) do
		if ghost and ghost.Parent then
			ghost:Destroy()
		end
	end
	handle.trailImages = {}
end

return ReticleMotionBlurMod