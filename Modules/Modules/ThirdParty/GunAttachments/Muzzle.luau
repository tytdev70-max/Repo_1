--!nonstrict
-- GunAttachments/Muzzle
-- Original-muzzle override protocol.
--
-- When a muzzle-slot attachment is mounted, the gun's own muzzle host part (the part
-- holding `<Root>/…/Muzzle`) is hidden and its emitters/lights disabled. Original
-- values are stored in attributes so they can be restored exactly. Attribute names
-- are part of the public protocol (see Defaults.attributes).

local Defaults = require(script.Parent.Defaults)

local ATTR = Defaults.attributes

local Muzzle = {}

-- Returns the model's root part (first match of rootNames, e.g. Grip then Base).
function Muzzle.findRoot(model: Instance, rootNames: { string }): Instance?
	for _, rootName in ipairs(rootNames) do
		local root = (model :: any):FindFirstChild(rootName)
		if root then
			return root
		end
	end
	return nil
end

-- Returns (originalMuzzle, hostPart) or nil.
function Muzzle.findOriginal(model: Instance, rootNames: { string }): (Instance?, Instance?)
	local root = Muzzle.findRoot(model, rootNames)
	if not root then
		return nil, nil
	end
	local original = (root :: any):FindFirstChild("Muzzle", true)
	if not original then
		return nil, nil
	end
	local host = nil
	if original:IsA("Attachment") then
		host = original.Parent
	elseif original:IsA("BasePart") then
		host = original
	end
	if host and host:IsA("BasePart") then
		return original, host
	end
	return original, nil
end

local function hideHost(original: any, host: any)
	if host:GetAttribute(ATTR.originalTransparency) == nil then
		host:SetAttribute(ATTR.originalTransparency, host.Transparency)
	end
	host.Transparency = 1
	host.CastShadow = false

	for _, child in ipairs(host:GetDescendants()) do
		if child:IsA("BasePart") then
			if child:GetAttribute(ATTR.originalTransparency) == nil then
				child:SetAttribute(ATTR.originalTransparency, child.Transparency)
			end
			child.Transparency = 1
			child.CastShadow = false
		elseif child:IsA("ParticleEmitter") or child:IsA("Light") then
			if child:GetAttribute(ATTR.originalEnabled) == nil then
				child:SetAttribute(ATTR.originalEnabled, child.Enabled)
			end
			child.Enabled = false
		end
	end

	if original:IsA("Attachment") then
		original.Visible = false
		original:SetAttribute(ATTR.overridden, true)
	end
end

-- Hides the original muzzle. Returns true if a root part exists (the caller uses this
-- to decide whether to publish ActiveCustomMuzzle, matching the original flow).
function Muzzle.hide(model: Instance, rootNames: { string }): boolean
	local root = Muzzle.findRoot(model, rootNames)
	if not root then
		return false
	end
	local original, host = Muzzle.findOriginal(model, rootNames)
	if original and host then
		hideHost(original, host)
	end
	return true
end

-- Marks the original muzzle as pre-hidden (it stays hidden even after a muzzle
-- attachment is removed) and hides it.
function Muzzle.preHide(model: Instance, rootNames: { string })
	local original, host = Muzzle.findOriginal(model, rootNames)
	if original and host then
		(host :: any):SetAttribute(ATTR.preHidden, true)
		hideHost(original, host)
	end
end

function Muzzle.restore(model: Instance, rootNames: { string })
	local original, host = Muzzle.findOriginal(model, rootNames)
	if original and host and not (host :: any):GetAttribute(ATTR.preHidden) then
		local hostAny = host :: any
		local origTransparency = hostAny:GetAttribute(ATTR.originalTransparency)
		if origTransparency ~= nil then
			hostAny.Transparency = origTransparency
			hostAny.CastShadow = true
			hostAny:SetAttribute(ATTR.originalTransparency, nil)
		end
		for _, child in ipairs(hostAny:GetDescendants()) do
			if child:IsA("BasePart") then
				local childTransparency = child:GetAttribute(ATTR.originalTransparency)
				if childTransparency ~= nil then
					child.Transparency = childTransparency
					child.CastShadow = true
					child:SetAttribute(ATTR.originalTransparency, nil)
				end
			elseif child:IsA("ParticleEmitter") or child:IsA("Light") then
				local origEnabled = child:GetAttribute(ATTR.originalEnabled)
				if origEnabled ~= nil then
					child.Enabled = origEnabled
					child:SetAttribute(ATTR.originalEnabled, nil)
				end
			end
		end
		if (original :: any):IsA("Attachment") then
			(original :: any):SetAttribute(ATTR.overridden, nil)
		end
	end
	(model :: any):SetAttribute(ATTR.activeCustomMuzzle, nil)
end

-- Clears pre-hide + active-muzzle markers (used when a gun model is discarded).
function Muzzle.cleanup(model: Instance, rootNames: { string })
	local root = Muzzle.findRoot(model, rootNames)
	if not root then
		return
	end
	local _, host = Muzzle.findOriginal(model, rootNames)
	if host then
		(host :: any):SetAttribute(ATTR.preHidden, nil)
	end
	(model :: any):SetAttribute(ATTR.activeCustomMuzzle, nil)
end

return Muzzle
