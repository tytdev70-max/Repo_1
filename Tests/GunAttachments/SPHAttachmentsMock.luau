-- Test stand-in for Weapons/Attachments/SPHAttachments: same option shape, but backed
-- by Roblox doubles so the AttachmentManager shim can be exercised in the Luau CLI.
local Mocks = require("./mocks")
local GunAttachments = require("./GunAttachments")
local make = Mocks.make

local root = make("Folder", { Name = "GunAttachments" })
local function content(slot, name, config, parts)
	local slotFolder = root:FindFirstChild(slot) or make("Folder", { Name = slot, Parent = root })
	local folder = make("Folder", { Name = name, Parent = slotFolder })
	for _, part in ipairs(parts) do part.Parent = folder end
	local module = make("ModuleScript", { Name = "Customization", Parent = folder })
	rawset(module, "_value", config)
end

content("Optics", "RedDot", {
	Tag = "reddot", IsCompatible = function() return true end,
	ReticleConfig = { Color = "red" }, DepthOfField = { Enabled = true },
	ApplyStats = function(s) s.damage += 1; return s end,
}, { make("MeshPart", { Name = "Body" }), make("Part", { Name = "AimPart" }) })

local can = make("MeshPart", { Name = "Body" })
make("Attachment", { Name = "Muzzle", Parent = can })
content("Muzzle", "Can", { Tag = "can", IsCompatible = function() return true end, overHeating = { Enabled = true } }, { can })

local box = make("MeshPart", { Name = "Box" })
make("Attachment", { Name = "Laser", Parent = box })
make("Attachment", { Name = "Hand", Parent = box })
make("Part", { Name = "Flashlight", Parent = box })
content("Underbarrel", "Grip1", {
	IsCompatible = function() return true end, EnableLaser = true, EnableFlashlight = true,
	EnableHandPositioning = true, HandGripPart = "Hand",
}, { box })

local system = GunAttachments.new({
	contentRoot = function() return root end,
	allowUnknownSlots = false,
	services = {
		newInstance = Mocks.Instance.new, identityCFrame = Mocks.CFrame.new(), http = Mocks.Http,
		heartbeat = Mocks.newSignal(), tween = function() end,
		require = function(module) return rawget(module, "_value") end,
	},
	log = false,
})
system._contentRootForTests = root
return system
