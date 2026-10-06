--!nonstrict
-- GunAttachments/Mounting
-- Builds and tears down the instance tree of one mounted attachment.
--
-- Result on the gun model:
--   <MountPart>/<Name>                 Attachment (authored mount point on the gun)
--   <MountPart>/<Name><nodeSuffix>     Folder (the "node") containing cloned parts
--       <RootPart>   + Motor6D "AttachmentMotor_Root_<Name>"  (Part0 = mount host part)
--       <OtherPart>  + Motor6D "AttachmentMotor_<Part>"       (Part0 = cloned root)

local Defaults = require(script.Parent.Defaults)
local Types = require(script.Parent.Types)

type AttachmentConfig = Types.AttachmentConfig
type SlotDef = Types.SlotDef

local HIDDEN_ATTR = Defaults.attributes.hiddenPartTransparency

export type MountContext = {
	newInstance: (string) -> Instance,
	identityCFrame: () -> any,
	nodeSuffix: string,
}

local Mounting = {}

local function isPart(instance: any): boolean
	return instance:IsA("BasePart")
end

-- Root resolution. Original behaviour: config.RootPart, else the first MeshPart child
-- (the old FindFirstChildOfClass("BasePart") never matches an abstract class). We keep
-- that preference and additionally fall back to the first BasePart of any class.
function Mounting.resolveRootName(contentFolder: Instance, config: AttachmentConfig): string?
	if type(config.RootPart) == "string" then
		return config.RootPart
	end
	local folder = contentFolder :: any
	local mesh = folder:FindFirstChildOfClass("MeshPart")
	if mesh then
		return mesh.Name
	end
	for _, child in ipairs(folder:GetChildren()) do
		if isPart(child) then
			return child.Name
		end
	end
	return nil
end

-- Mounts the attachment. Returns (node, nil) or (nil, reason). On failure nothing is
-- left behind on the gun model.
function Mounting.mount(
	ctx: MountContext,
	model: Instance,
	slot: SlotDef,
	name: string,
	config: AttachmentConfig,
	contentFolder: Instance
): (Instance?, string?)
	local slotPart = (model :: any):FindFirstChild(slot.mountPart, true)
	if not slotPart then
		return nil, "mount part '" .. slot.mountPart .. "' not found on model"
	end

	local mountPoint = slotPart:FindFirstChild(name)
	if not mountPoint or not mountPoint:IsA("Attachment") then
		return nil, "mount Attachment '" .. name .. "' not found under " .. slot.mountPart
	end

	local nodeName = name .. ctx.nodeSuffix
	local stale = slotPart:FindFirstChild(nodeName)
	if stale then
		stale:Destroy() -- synchronous; the old 0.05s yield is unnecessary
	end

	local rootName = Mounting.resolveRootName(contentFolder, config)
	if not rootName then
		return nil, "content has no parts"
	end
	local originalRoot = (contentFolder :: any):FindFirstChild(rootName)
	if not originalRoot then
		return nil, "root part '" .. rootName .. "' not found in content"
	end

	local node = ctx.newInstance("Folder") :: any
	node.Name = nodeName
	node.Parent = slotPart

	local clones: { [string]: any } = {}
	for _, child in ipairs((contentFolder :: any):GetChildren()) do
		if isPart(child) then
			local clone = child:Clone()
			clone.Parent = node
			clone.CanCollide = false
			clone.Anchored = false
			clones[child.Name] = clone
		end
	end

	local cloneRoot = clones[rootName]
	if not cloneRoot then
		node:Destroy()
		return nil, "root part '" .. rootName .. "' is not a BasePart"
	end

	local mountOffset = config.MountOffset or ctx.identityCFrame()

	local rootMotor = ctx.newInstance("Motor6D") :: any
	rootMotor.Name = "AttachmentMotor_Root_" .. name
	rootMotor.Part0 = mountPoint.Parent
	rootMotor.Part1 = cloneRoot
	rootMotor.C0 = mountPoint.CFrame * mountOffset
	rootMotor.C1 = ctx.identityCFrame()
	rootMotor.Parent = cloneRoot

	for partName, clonePart in pairs(clones) do
		if partName ~= rootName then
			local originalPart = (contentFolder :: any):FindFirstChild(partName)
			if originalPart then
				local childMotor = ctx.newInstance("Motor6D") :: any
				childMotor.Name = "AttachmentMotor_" .. partName
				childMotor.Part0 = cloneRoot
				childMotor.Part1 = clonePart
				childMotor.C0 = originalRoot.CFrame:Inverse() * originalPart.CFrame
				childMotor.C1 = ctx.identityCFrame()
				childMotor.Parent = clonePart
			end
		end
	end

	for _, clonePart in pairs(clones) do
		clonePart.CanCollide = false
		clonePart.Massless = true
	end

	for _, partName in ipairs(config.VisibleParts or {}) do
		local part = node:FindFirstChild(partName, true)
		if part and isPart(part) then
			part.Transparency = 0
		end
	end

	Mounting.hideGunParts(model, config)

	if config.EnableLaser then
		for _, descendant in ipairs(node:GetDescendants()) do
			if descendant:IsA("Beam") then
				descendant.Enabled = false
			end
		end
	end

	return node, nil
end

function Mounting.hideGunParts(model: Instance, config: AttachmentConfig)
	local transparency = config.HideTransparency or 1
	for _, partName in ipairs(config.HideGunParts or {}) do
		local part = (model :: any):FindFirstChild(partName, true)
		if part and isPart(part) then
			if part:GetAttribute(HIDDEN_ATTR) == nil then
				part:SetAttribute(HIDDEN_ATTR, part.Transparency)
			end
			part.Transparency = transparency
		end
	end
end

-- Restores parts hidden by `HideGunParts` to their original transparency (the old
-- implementation forced 0; parts without a remembered value still get 0).
function Mounting.restoreGunParts(model: Instance, config: AttachmentConfig)
	for _, partName in ipairs(config.HideGunParts or {}) do
		local part = (model :: any):FindFirstChild(partName, true)
		if part and isPart(part) then
			local original = part:GetAttribute(HIDDEN_ATTR)
			part.Transparency = if type(original) == "number" then original else 0
			part:SetAttribute(HIDDEN_ATTR, nil)
		end
	end
end

-- Destroys every node folder (name ends with suffix) anywhere in the model.
function Mounting.purgeNodes(model: Instance, suffix: string)
	local pattern = suffix:gsub("%p", "%%%0") .. "$"
	for _, descendant in ipairs((model :: any):GetDescendants()) do
		if descendant:IsA("Folder") and string.match(descendant.Name, pattern) then
			descendant:Destroy()
		end
	end
end

return Mounting
