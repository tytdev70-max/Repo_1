local table = require(script:WaitForChild("Table"))

local PartCacheStatic = {}
PartCacheStatic.__index = PartCacheStatic
PartCacheStatic.__type = "PartCache"

export type PartCache = {
	Open: {[number]: BasePart},
	InUse: {[number]: BasePart},
	CurrentCacheParent: Instance,
	Template: BasePart,
	ExpansionSize: number,
	HiddenContainer: Folder
}

local hiddenStorage = Instance.new("Folder")
hiddenStorage.Name = "PartCacheStorage"
hiddenStorage.Parent = nil

local ERR_NOT_INSTANCE = "Cannot statically invoke method '%s' - It is an instance method. Call it on an instance of this class created via %s"

local function assertwarn(requirement: boolean, messageIfNotMet: string)
	if requirement == false then
		warn(messageIfNotMet)
	end
end

local function MakeFromTemplate(template: BasePart, hiddenContainer: Instance): BasePart
	local part: BasePart = template:Clone()
	part.Anchored = true
	part.Parent = hiddenContainer 
	return part
end

function PartCacheStatic.new(template: BasePart, numPrecreatedParts: number?, currentCacheParent: Instance?): PartCache
	local newNumPrecreatedParts: number = numPrecreatedParts or 5
	local newCurrentCacheParent: Instance = currentCacheParent or workspace

	assert(numPrecreatedParts > 0, "PrecreatedParts can not be negative!")
	assertwarn(numPrecreatedParts ~= 0, "PrecreatedParts is 0! This may have adverse effects when initially using the cache.")
	assertwarn(template.Archivable, "The template's Archivable property has been set to false, which prevents it from being cloned. It will temporarily be set to true.")

	local oldArchivable = template.Archivable
	template.Archivable = true
	local newTemplate: BasePart = template:Clone()
	template.Archivable = oldArchivable
	template = newTemplate

	local hiddenContainer = Instance.new("Folder")
	hiddenContainer.Name = "HiddenCache"
	hiddenContainer.Parent = hiddenStorage

	local object: PartCache = {
		Open = {},
		InUse = {},
		CurrentCacheParent = newCurrentCacheParent,
		Template = template,
		ExpansionSize = 10,
		HiddenContainer = hiddenContainer
	}
	setmetatable(object, PartCacheStatic)

	for _ = 1, newNumPrecreatedParts do
		table.insert(object.Open, MakeFromTemplate(template, hiddenContainer))
	end
	object.Template.Parent = nil

	return object
end

function PartCacheStatic:GetPart(): BasePart
	assert(getmetatable(self) == PartCacheStatic, ERR_NOT_INSTANCE:format("GetPart", "PartCache.new"))

	local part: BasePart? = nil

	while part == nil do
		if #self.Open == 0 then
			for i = 1, self.ExpansionSize, 1 do
				table.insert(self.Open, MakeFromTemplate(self.Template, self.HiddenContainer))
			end
		end

		local candidate = self.Open[#self.Open]
		self.Open[#self.Open] = nil

		local ok = pcall(function()
			candidate.Parent = self.CurrentCacheParent
		end)

		if ok then
			part = candidate
		else
			warn("[PartCache] Discarded a destroyed part found in the Open pool (\"" .. candidate.Name .. "\"); replacing it.")
		end
	end

	table.insert(self.InUse, part)

	return part
end

function PartCacheStatic:ReturnPart(part: BasePart)
	assert(getmetatable(self) == PartCacheStatic, ERR_NOT_INSTANCE:format("ReturnPart", "PartCache.new"))

	local index = table.indexOf(self.InUse, part)
	if index ~= nil then
		table.remove(self.InUse, index)

		local ok = pcall(function()
			part.Parent = self.HiddenContainer
			part.Anchored = true
		end)

		if ok then
			table.insert(self.Open, part)
		else
			warn("[PartCache] Part \"" .. part.Name .. "\" was destroyed while in use; replacing it in the pool instead of recycling it.")
			table.insert(self.Open, MakeFromTemplate(self.Template, self.HiddenContainer))
		end
	else
		error("Attempted to return part \"" .. part.Name .. "\" (" .. part:GetFullName() .. ") to the cache, but it's not in-use!")
	end
end

function PartCacheStatic:SetCacheParent(newParent: Instance)
	assert(getmetatable(self) == PartCacheStatic, ERR_NOT_INSTANCE:format("SetCacheParent", "PartCache.new"))
	assert(newParent:IsDescendantOf(workspace) or newParent == workspace, "Cache parent is not a descendant of Workspace!")

	self.CurrentCacheParent = newParent

	for i = 1, #self.InUse do
		self.InUse[i].Parent = newParent
	end
end

function PartCacheStatic:Expand(numParts: number): ()
	assert(getmetatable(self) == PartCacheStatic, ERR_NOT_INSTANCE:format("Expand", "PartCache.new"))
	if numParts == nil then
		numParts = self.ExpansionSize
	end

	for i = 1, numParts do
		table.insert(self.Open, MakeFromTemplate(self.Template, self.HiddenContainer))
	end
end

function PartCacheStatic:Dispose()
	assert(getmetatable(self) == PartCacheStatic, ERR_NOT_INSTANCE:format("Dispose", "PartCache.new"))

	for i = 1, #self.Open do
		self.Open[i]:Destroy()
	end
	for i = 1, #self.InUse do
		self.InUse[i]:Destroy()
	end

	self.Template:Destroy()
	self.HiddenContainer:Destroy()

	self.Open = {}
	self.InUse = {}
	self.CurrentCacheParent = nil
	self.HiddenContainer = nil

	self.GetPart = nil
	self.ReturnPart = nil
	self.SetCacheParent = nil
	self.Expand = nil
	self.Dispose = nil
end

return PartCacheStatic