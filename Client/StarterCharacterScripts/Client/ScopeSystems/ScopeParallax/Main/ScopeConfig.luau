--!strict

--// Scope Rendering Configuration

local ScopeConfig = {}

-- Prefix used to detect a weapon's aim part(s). Supports either a single "AimPart" or
-- indexed variants ("AimPart1", "AimPart2", ...) for weapons with multiple sights.
ScopeConfig.aimPartPrefix = "AimPart"

-- Name of the part that marks where a scope's parallax focus should render.
ScopeConfig.scopeFocusPartName = "SCOPE_FOCUS"

-- Name of the attachment slot optics live in on a weapon's attachment system.
ScopeConfig.opticsAttachmentSlot = "Optics"

-- Folder (parented under a SCOPE_FOCUS part) holding per-zoom-tier setting modules.
-- Any subset of tiers can be present; Activate blends between whichever ones exist.
ScopeConfig.presetsFolderName = "Scope Presets"

-- Keyword used to match a preset module's name against a zoom tier, case-insensitive.
-- Add an entry here to support a new tier without touching the matching logic.
ScopeConfig.presetTierKeywords = {
	Low = "low",
	Medium = "med",
	High = "high",
}

-- Name used to locate a sight's reticle image under its SurfaceGui, and the possible
-- names of the image itself (different reticle styles use different image names).
ScopeConfig.reticlePartName = "SightReticle"
ScopeConfig.reticleImageNames = { "Reticle", "Holo" }

-- Base lens scale multipliers, tuned against the default ocular/objective mesh sizes.
ScopeConfig.defaultOcularScale = 3.75
ScopeConfig.defaultObjectiveScale = 3.45

-- Texture object names expected on a SCOPE_FOCUS part, one per rendered lens channel.
ScopeConfig.lensTextureNames = {
	ocular = "OcularLens",
	objective = "ObjectiveLens",
	light = "Light",
	ocularChromaticAberration = "OcularCA",
	objectiveChromaticAberration = "ObjectiveCA",
}

return ScopeConfig