--[[
	LightingBillboards
	Templates live in SPH_Assets.HUD.Billboards.{Flashlight,Laser}.{Blind,Indicator}.
	The .rbxmx assets in HUD/Billboards are editable in Studio. Matching defaults
	are created only when an older place has not imported them; art is never overwritten.
]]

local LightingBillboards = {}

--------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------

local KINDS = { "Flashlight", "Laser" }
local ROLES = { "Blind", "Indicator" }

local IMAGES = {
	Blind = "rbxassetid://105715385829652",
	Indicator = "rbxassetid://17640078650",
}

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function createTemplate(parent, role)
	local isBlind = role == "Blind"

	local gui = Instance.new("BillboardGui")
	gui.Name = role
	gui.Enabled = false
	gui.AlwaysOnTop = isBlind
	gui.LightInfluence = 0
	gui.MaxDistance = 250
	gui.Size = if isBlind then UDim2.fromOffset(600, 600) else UDim2.fromScale(0.6, 0.6)

	local glow = Instance.new("ImageLabel")
	glow.Name = "Glow"
	glow.BackgroundTransparency = 1
	glow.Image = IMAGES[role]
	glow.ImageTransparency = 0
	glow.ScaleType = Enum.ScaleType.Stretch
	glow.Size = UDim2.fromScale(1, 1)
	glow.Parent = gui

	gui.Parent = parent
	return gui
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function LightingBillboards.Ensure(assets)
	local root = getOrCreateFolder(getOrCreateFolder(assets, "HUD"), "Billboards")
	for _, kind in ipairs(KINDS) do
		local folder = getOrCreateFolder(root, kind)
		for _, role in ipairs(ROLES) do
			if not folder:FindFirstChild(role) then
				createTemplate(folder, role)
			end
		end
	end
	return root
end

function LightingBillboards.Clone(assets, kind, role)
	local root = LightingBillboards.Ensure(assets)
	local template = root[kind]:FindFirstChild(role)
	assert(
		template and template:IsA("BillboardGui"),
		("SPH_Assets.HUD.Billboards.%s.%s must be a BillboardGui"):format(kind, role)
	)
	return template:Clone()
end

return LightingBillboards