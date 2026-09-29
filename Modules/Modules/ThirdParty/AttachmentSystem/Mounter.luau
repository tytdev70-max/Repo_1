--[[
	AttachmentSystem.Mounter
	────────────────────────
	The physical half of the system: turning a folder of attachment parts into
	a live, welded part of a weapon model, and taking it apart again.

	Responsibilities:

	  • resolve the mount point (`<categoryPart>.<attachmentName>` must be an
	    `Attachment` instance) and the rig root (`RootPart` or the first
	    BasePart/MeshPart in the source folder)
	  • clone the parts and wire them together with Motor6Ds
	  • hide the gun parts an attachment replaces, remembering what they
	    actually were so teardown can put them back exactly
	  • swap out the muzzle and hand the world the new one

	Everything the 3D preview needs is exposed through `ComputeLayout`, so the
	preview cannot drift away from the real rig.
]]

local Config     = require(script.Parent.Config)
local ConfigLoader = require(script.Parent.ConfigLoader)

local Mounter = {}

-- ─── Layout resolution ──────────────────────────────────────────────────────

--[[
	Work out, without touching the world, where every part of an attachment
	would go. Shared by the live rig builder and the gunsmith's 3D preview so
	there is exactly one implementation of the mounting maths.

	@return a table describing the rig, or nil plus a reason string.
]]
function Mounter.ComputeLayout(weaponModel: Instance?, attachmentFolder: Folder?, config: any)
	local category = config and config.category
	if not category or not weaponModel or not attachmentFolder or not config then
		return nil, "missing arguments"
	end

	local mountName = Config.GetCategoryPartName(category)
	local categoryPart = weaponModel:FindFirstChild(mountName, true)
	if not categoryPart then
		return nil, string.format("model has no '%s'", mountName)
	end

	local mountPoint = categoryPart:FindFirstChild(config.attachmentName)
	if not mountPoint or not mountPoint:IsA("Attachment") then
		return nil, string.format("no Attachment named '%s' under '%s'",
			config.attachmentName, mountName)
	end

	local rootName = ConfigLoader.ResolveRootPartName(attachmentFolder, config)
	if not rootName then
		return nil, "no root part"
	end

	local originalRoot = attachmentFolder:FindFirstChild(rootName)
	if not originalRoot then
		return nil, string.format("root part '%s' missing from source", rootName)
	end

	local mountOffset = config.MountOffset or CFrame.new()
	local rootCFrame  = mountPoint.CFrame * mountOffset

	-- Relative transforms for every part, keyed by name.
	local relative: { [string]: CFrame } = { [rootName] = CFrame.new() }
	for _, child in ipairs(attachmentFolder:GetChildren()) do
		if child:IsA("BasePart") and child.Name ~= rootName then
			relative[child.Name] = originalRoot.CFrame:Inverse() * child.CFrame
		end
	end

	return {
		category       = category,
		attachmentName = config.attachmentName,
		mountName      = mountName,
		categoryPart   = categoryPart,
		mountPoint     = mountPoint,
		sourceFolder   = attachmentFolder,
		config         = config,
		rootName       = rootName,
		rootCFrame     = rootCFrame,
		relative       = relative,
	}, nil
end

-- ─── Part replacement bookkeeping ───────────────────────────────────────────
-- Original values are recorded as attributes on the gun parts themselves, the
-- same way the previous implementation did, so anything already relying on
-- them keeps working, but the restore path now honours what it recorded.

local function rememberTransparency(part: BasePart)
	local key = Config.Naming.originalTransparency
	if part:GetAttribute(key) == nil then
		part:SetAttribute(key, part.Transparency)
	end
end

local function rememberEnabled(instance: Instance)
	local key = Config.Naming.originalEnabled
	if instance:GetAttribute(key) == nil then
		instance:SetAttribute(key, instance.Enabled)
	end
end

--[[
	Hide the gun part an attachment is replacing.

	`baseOverride` lets a host point the system at a different root part name
	than `Grip`/`Base` (some weapons mount the muzzle elsewhere).
	Returns the hidden part so callers can report on it.
]]
function Mounter.HideReplacedPart(weaponModel: Instance): BasePart?
	local base = weaponModel:FindFirstChild(Config.ModelParts.grip, true)
		or weaponModel:FindFirstChild(Config.ModelParts.base, true)
	if not base then
		return nil
	end

	local originalMuzzle = base:FindFirstChild(Config.ModelParts.muzzle, true)
	if not originalMuzzle then
		return nil
	end

	local hideTarget: BasePart? = nil
	if originalMuzzle:IsA("Attachment") then
		local parent = originalMuzzle.Parent
		if parent and parent:IsA("BasePart") then
			hideTarget = parent
		end
	elseif originalMuzzle:IsA("BasePart") then
		hideTarget = originalMuzzle
	end

	if not hideTarget then
		return nil
	end

	rememberTransparency(hideTarget)
	hideTarget.Transparency = 1
	hideTarget.CastShadow  = false

	for _, child in ipairs(hideTarget:GetDescendants()) do
		if child:IsA("BasePart") then
			rememberTransparency(child)
			child.Transparency = 1
			child.CastShadow  = false
		elseif child:IsA("ParticleEmitter") or child:IsA("Light") then
			rememberEnabled(child)
			child.Enabled = false
		end
	end

	if originalMuzzle:IsA("Attachment") then
		originalMuzzle.Visible = false
		originalMuzzle:SetAttribute(Config.Naming.overriddenBy, true)
	end

	return hideTarget
end

--[[
	Undo `HideReplacedPart`.

	The previous implementation guarded the entire restore behind
	`not restoreTarget:GetAttribute("MuzzlePreHidden")`, so a model that had
	been pre-hidden by any other code path would leave its base muzzle
	invisible forever. The pre-hide marker is now scoped to the individual
	attribute writes it actually concerns instead of short-circuiting the whole
	restore.
]]
function Mounter.RestoreReplacedPart(weaponModel: Instance)
	local base = weaponModel:FindFirstChild(Config.ModelParts.grip, true)
		or weaponModel:FindFirstChild(Config.ModelParts.base, true)
	if not base then
		return
	end

	local originalMuzzle = base:FindFirstChild(Config.ModelParts.muzzle, true)
	if not originalMuzzle then
		return
	end

	local restoreTarget: BasePart? = nil
	if originalMuzzle:IsA("Attachment") then
		local parent = originalMuzzle.Parent
		if parent and parent:IsA("BasePart") then
			restoreTarget = parent
		end
	elseif originalMuzzle:IsA("BasePart") then
		restoreTarget = originalMuzzle
	end

	if not restoreTarget then
		return
	end

	local transparencyKey = Config.Naming.originalTransparency
	local enabledKey     = Config.Naming.originalEnabled

	local original = restoreTarget:GetAttribute(transparencyKey)
	if original ~= nil then
		restoreTarget.Transparency = original
		restoreTarget:SetAttribute(transparencyKey, nil)
	end
	if not originalMuzzle:GetAttribute(Config.Naming.muzzlePreHidden) then
		restoreTarget.CastShadow = true
	end

	for _, child in ipairs(restoreTarget:GetDescendants()) do
		if child:IsA("BasePart") then
			local value = child:GetAttribute(transparencyKey)
			if value ~= nil then
				child.Transparency = value
				child:SetAttribute(transparencyKey, nil)
				child.CastShadow  = true
			end
		elseif child:IsA("ParticleEmitter") or child:IsA("Light") then
			local value = child:GetAttribute(enabledKey)
			if value ~= nil then
				child.Enabled = value
				child:SetAttribute(enabledKey, nil)
			end
		end
	end

	if originalMuzzle:IsA("Attachment") then
		originalMuzzle.Visible = true
		originalMuzzle:SetAttribute(Config.Naming.overriddenBy, nil)
	end
end

-- ─── Hiding gun parts an attachment covers ──────────────────────────────────
-- The old teardown hard-reset every hidden part to Transparency = 0, which
-- turned any genuinely translucent barrel or stock permanently opaque after a
-- single attachment swap. We now record and restore the real value.

local function hideCoveredParts(weaponModel: Instance, config: any)
	local hidden = {}
	for _, partName in ipairs(config.HideGunParts or {}) do
		local part = weaponModel:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			if not part:GetAttribute(Config.Naming.originalTransparency) then
				part:SetAttribute(Config.Naming.originalTransparency, part.Transparency)
			end
			part.Transparency = config.HideTransparency or 1
			table.insert(hidden, part)
		end
	end
	return hidden
end

local function restoreCoveredParts(config: any)
	local key = Config.Naming.originalTransparency
	for _, partName in ipairs(config.HideGunParts or {}) do
		local part = nil
		if config.__weaponModel and config.__weaponModel.Parent then
			part = config.__weaponModel:FindFirstChild(partName, true)
		end
		if part and part:IsA("BasePart") then
			local value = part:GetAttribute(key)
			if value ~= nil then
				part.Transparency = value
			end
		end
	end
end

-- ─── Building the rig ───────────────────────────────────────────────────────

--[[
	Create the live rig inside a resolved layout.

	@param layout      result of `ComputeLayout`
	@param parent      Instance to parent the new node to
	@param welded      when true, build Motor6Ds (the live weapon). When false,
	                   the parts are simply positioned, which is what the 3D
	                   preview wants.
	@return the created node, or nil plus a reason.
]]
function Mounter.Build(layout: any, parent: Instance?, welded: boolean)
	if not layout or not parent then
		return nil, "nothing to build"
	end

	local attachmentFolder = layout.sourceFolder
	if not attachmentFolder then
		return nil, "no source folder"
	end

	local node = Instance.new("Folder")
	node.Name   = layout.attachmentName .. Config.Naming.equippedSuffix
	node.Parent = parent

	local cloneParts: { [string]: BasePart } = {}
	for _, child in ipairs(attachmentFolder:GetChildren()) do
		if child:IsA("BasePart") then
			local clone = child:Clone()
			clone.Parent    = node
			clone.CanCollide = false
			clone.Anchored  = false
			clone.Massless  = true
			cloneParts[child.Name] = clone
		end
	end

	local cloneRoot = cloneParts[layout.rootName]
	if not cloneRoot then
		node:Destroy()
		return nil, string.format("root '%s' not cloned", layout.rootName)
	end

	if welded then
		-- Part0 is the mount point's *parent* so the Motor6D sits in the same
		-- assembly as the Attachment it replaces. This is the original rig and
		-- is preserved exactly.
		local rootMotor = Instance.new("Motor6D")
		rootMotor.Name   = "AttachmentMotor_Root_" .. layout.attachmentName
		rootMotor.Part0  = layout.mountPoint.Parent
		rootMotor.Part1  = cloneRoot
		rootMotor.C0     = layout.rootCFrame
		rootMotor.C1     = CFrame.new()
		rootMotor.Parent = cloneRoot
	else
		cloneRoot.CFrame = layout.rootCFrame
	end

	for partName, clonePart in pairs(cloneParts) do
		if partName ~= layout.rootName then
			if welded then
				local relativeCF = layout.relative[partName] or CFrame.new()
				local childMotor = Instance.new("Motor6D")
				childMotor.Name   = "AttachmentMotor_" .. partName
				childMotor.Part0  = cloneRoot
				childMotor.Part1  = clonePart
				childMotor.C0     = relativeCF
				childMotor.C1     = CFrame.new()
				childMotor.Parent = clonePart
			else
				local relativeCF = layout.relative[partName] or CFrame.new()
				clonePart.CFrame = layout.rootCFrame * relativeCF
			end
		end
	end

	return node, nil
end

--[[
	Destroy a rig node and restore everything it hid.
	The weapon model is required to undo part replacement and covered parts.
]]
function Mounter.Teardown(node: Folder?, weaponModel: Instance?, config: any)
	if config and weaponModel then
		local hideCopy = {}
		for key, value in pairs(config) do
			hideCopy[key] = value
		end
		hideCopy.__weaponModel = weaponModel
		restoreCoveredParts(hideCopy)
	end

	if config and type(config.OnUnequip) == "function" and node then
		pcall(config.OnUnequip, weaponModel, config.category, node)
	end

	if node and node.Parent then
		node:Destroy()
	end
end

return Mounter
