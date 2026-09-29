--[[
	AttachmentSystem.Visuals
	────────────────────────
	Presentation concerns that belong to the attachment system rather than to
	the host: fading attachments in and out with the aim animation, and
	keeping the muzzle override marker in sync.

	These are separated from `Queries` because they *mutate* the world, while
	queries never do.
]]

local TweenService = game:GetService("TweenService")

local Config   = require(script.Parent.Config)
local Registry = require(script.Parent.Registry)
local Queries  = require(script.Parent.Queries)

local Visuals = {}

--[[
	Apply an ADS transparency change to every attachment that declares it.

	  • `TransparentOnADS` — fades these parts out while aiming (housings that
	    would otherwise block the sight picture)
	  • `VisibleOnADS`     — inverse: hidden normally, revealed while aiming
	  • `LPVOZoom.leverRingName` — a magnified optic's actuator is only
	    meaningful while aiming

	The tween duration tracks the weapon's `aimTime` so the fade never
	outlasts or lags the actual ADS transition.
]]
function Visuals.ApplyADSVisibility(weaponModel: Instance?, aiming: boolean, weaponStats: any?)
	if not weaponModel then
		return
	end

	local active = Registry.GetAll(weaponModel)
	if not active or next(active) == nil then
		return
	end

	local tweenTime = 0.2
	if type(weaponStats) == "table" and weaponStats.aimTime then
		tweenTime = weaponStats.aimTime / 20
	end
	local tweenInfo = TweenInfo.new(
		tweenTime,
		Enum.EasingStyle.Linear,
		Enum.EasingDirection.Out,
		0,
		false,
		tweenTime
	)

	local function fade(node: Instance, partName: string, transparency: number)
		local part = node:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			TweenService:Create(part, tweenInfo, { Transparency = transparency }):Play()
		end
	end

	for _, category in ipairs(Registry.GetOccupiedCategories(weaponModel)) do
		local entry = Registry.Get(weaponModel, category)
		local config = entry and entry.config
		local node = entry and entry.model
		if not config or not node then
			continue
		end

		if config.TransparentOnADS then
			for _, partName in ipairs(config.TransparentOnADS) do
				fade(node, partName, aiming and 1 or 0)
			end
		end

		if config.VisibleOnADS then
			for _, partName in ipairs(config.VisibleOnADS) do
				fade(node, partName, aiming and 0 or 1)
			end
		end

		local lpvo = config.LPVOZoom
		if type(lpvo) == "table" and lpvo.Enabled and type(lpvo.leverRingName) == "string" then
			fade(node, lpvo.leverRingName, aiming and 0 or 1)
		end
	end
end

--[[
	Make every reticle surface GUI on a model (and its attachments) visible or
	not. Third-person models always stay off.

	@param isThirdPerson true when the model being scanned is the TP copy
]]
function Visuals.SetSightVisibility(weaponModel: Instance?, enabled: boolean, isThirdPerson: boolean?)
	Queries.ForEachSightSurfaceGui(weaponModel, function(gui)
		gui.Enabled = if isThirdPerson then false else enabled
	end)
end

--[[
	Mark an attachment as owned by the weapon model, so other systems can tell
	a fitted part from a leftover node without walking the registry.
]]
function Visuals.MarkEquipped(weaponModel: Instance?, attachmentName: string)
	if not weaponModel or not attachmentName then
		return
	end
	weaponModel:SetAttribute(Config.Naming.activeCustomMuzzle, attachmentName)
end

return Visuals
