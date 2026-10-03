--!nonstrict
-- GunAttachments/System
-- One independent attachment system: tracks which attachments are mounted on which
-- gun models, owns the stats store, and answers queries. Holds no global state.

local Defaults = require(script.Parent.Defaults)
local Loadout = require(script.Parent.Loadout)
local Mounting = require(script.Parent.Mounting)
local Muzzle = require(script.Parent.Muzzle)
local Registry = require(script.Parent.Registry)
local Scheduler = require(script.Parent.Scheduler)
local Signal = require(script.Parent.Signal)
local Slots = require(script.Parent.Slots)
local Stats = require(script.Parent.Stats)
local Types = require(script.Parent.Types)
local Util = require(script.Parent.Util)

type Record = Types.Record
type Loadout = Types.Loadout
type AttachmentConfig = Types.AttachmentConfig
type GripData = Types.GripData

local ATTR = Defaults.attributes

local System = {}
System.__index = System

type ModelEntry = { records: { [string]: Record } }

-- ─── construction ────────────────────────────────────────────────────────────

function System.new(userOptions: Types.Options?)
	local options = Defaults.merge(userOptions :: any)
	local log = Util.makeLogger(options.log, "[GunAttachments]")
	local services = options.services

	local self = setmetatable({}, System) :: any
	self._options = options
	self._log = log
	self._slots = Slots.build(options.slots, options.allowUnknownSlots)
	self._registry = Registry.new(options, log)
	self._stats = Stats.newStore(options, log)
	self._rootNames = Util.copyArray(options.modelRootNames)
	self._models = {} :: { [Instance]: ModelEntry }
	self._ownership = {} :: { [Instance]: Instance }
	self._destroyHooks = {} :: { [Instance]: any }
	self._destroyed = false

	self._newInstance = services.newInstance or function(className: string): Instance
		return Instance.new(className :: any)
	end
	self._identityCFrame = function(): any
		return services.identityCFrame or CFrame.new()
	end
	self._tween = services.tween
	self._http = services.http

	self._scheduler = Scheduler.new(function()
		if services.heartbeat then
			return services.heartbeat
		end
		local ok, runService = pcall(function()
			return (game :: any):GetService("RunService")
		end)
		return if ok then runService.Heartbeat else nil
	end, function(model: Instance)
		self:_purge(model)
	end)

	local function onSignalError(message: string)
		log.warn("signal handler errored: " .. message)
	end
	self.Equipped = Signal.new(onSignalError)
	self.Unequipped = Signal.new(onSignalError)
	self.ModelCleared = Signal.new(onSignalError)

	return self
end

-- ─── internals ───────────────────────────────────────────────────────────────

function System:_mountContext(): Mounting.MountContext
	return {
		newInstance = self._newInstance,
		identityCFrame = self._identityCFrame,
		nodeSuffix = self._options.nodeSuffix,
	}
end

function System:_entry(model: Instance): ModelEntry
	local entry = self._models[model]
	if not entry then
		entry = { records = {} }
		self._models[model] = entry
	end
	return entry
end

function System:_hookDestroy(model: Instance)
	if self._destroyHooks[model] then
		return
	end
	local ok, connection = pcall(function()
		return (model :: any).Destroying:Connect(function()
			self:_purge(model)
		end)
	end)
	if ok then
		self._destroyHooks[model] = connection
	end
end

-- Forget a model without touching its instances (it is being destroyed).
function System:_purge(model: Instance)
	self._scheduler:UnregisterModel(model)
	self._models[model] = nil
	self._ownership[model] = nil
	local hook = self._destroyHooks[model]
	if hook then
		hook:Disconnect()
		self._destroyHooks[model] = nil
	end
	self.ModelCleared:Fire(model)
end

function System:_roleRecord(model: Instance, role: string): Record?
	local entry = self._models[model]
	if not entry then
		return nil
	end
	local slot = Slots.forRole(self._slots, role)
	return slot and entry.records[slot.name] or nil
end

function System:_primaryRoot(model: Instance): Instance?
	local first = self._rootNames[1]
	return first and (model :: any):FindFirstChild(first) or nil
end

function System:_unequipAll(model: Instance)
	local entry = self._models[model]
	if not entry then
		return
	end
	local slots = {}
	for slot in pairs(entry.records) do
		table.insert(slots, slot)
	end
	for _, slot in ipairs(slots) do
		self:Unequip(model, slot)
	end
end

local function getHttp(self: any): any?
	if self._http then
		return self._http
	end
	local ok, service = pcall(function()
		return (game :: any):GetService("HttpService")
	end)
	if ok then
		self._http = service
	end
	return self._http
end

-- ─── content ────────────────────────────────────────────────────────────────

function System:LoadConfig(slot: string, name: string): AttachmentConfig?
	return self._registry:LoadConfig(slot, name)
end

function System:GetContentFolder(slot: string, name: string): Instance?
	return self._registry:GetContentFolder(slot, name)
end

function System:GetSlotPartName(slot: string): string?
	local def = Slots.get(self._slots, slot)
	return def and def.mountPart or nil
end

function System:IsValidSlot(slot: any): boolean
	return Slots.isValid(self._slots, slot)
end

function System:GetSlots(): { Types.SlotDef }
	local result = {}
	for index, def in ipairs(self._slots.ordered) do
		result[index] = table.clone(def)
	end
	return result
end

function System:GetSlotForRole(role: string): string?
	local def = Slots.forRole(self._slots, role)
	return def and def.name or nil
end

-- ─── lifecycle ───────────────────────────────────────────────────────────────

-- Mounts `name` into `slot` on `model`. `owner` is forwarded to config.OnEquip as its
-- first argument (SPH passes the Player). Returns (ok, reason?).
function System:Equip(model: Instance, tool: Instance, slot: string, name: string, owner: any?): (boolean, string?)
	local entry = model and self._models[model]
	local existing = entry and entry.records[slot]
	if existing and existing.attachmentName == name then
		return true, nil
	end

	if not tool or not model then
		return false, "missing model or tool"
	end
	if type(name) ~= "string" or name == "" then
		return false, "invalid attachment name"
	end
	local slotDef = Slots.get(self._slots, slot)
	if not slotDef then
		return false, "unknown slot '" .. tostring(slot) .. "'"
	end

	local currentOwner = self._ownership[model]
	if currentOwner and currentOwner ~= tool then
		self:ResetModel(model)
	end
	self._ownership[model] = tool
	self:_hookDestroy(model)

	local config = self._registry:LoadConfig(slot, name)
	if not config then
		return false, "config not found for " .. slot .. "/" .. name
	end
	if not self._registry:IsCompatible(config, tool, slot, name) then
		return false, "incompatible with " .. tostring((tool :: any).Name)
	end

	entry = self._models[model]
	existing = entry and entry.records[slot]
	if existing then
		if existing.attachmentName == name then
			return true, nil
		end
		self:Unequip(model, slot)
	end

	local contentFolder = self._registry:GetContentFolder(slot, name)
	if not contentFolder then
		return false, "content folder not found for " .. slot .. "/" .. name
	end

	local node, reason = Mounting.mount(self:_mountContext(), model, slotDef, name, config, contentFolder)
	if not node then
		return false, reason
	end

	if slotDef.overridesMuzzle then
		local hasRoot = Muzzle.hide(model, self._rootNames)
		if hasRoot and (node :: any):FindFirstChild("Muzzle", true) then
			(model :: any):SetAttribute(ATTR.activeCustomMuzzle, name)
		end
	end

	local record: Record = table.freeze({
		slot = slot,
		attachmentName = name,
		config = config,
		node = node,
		model = node,
		tool = tool,
	})
	self:_entry(model).records[slot] = record

	if type(config.OnUpdate) == "function" then
		self._scheduler:Register(model, slot, config.OnUpdate)
	end

	if type(config.OnEquip) == "function" then
		local ok, err = pcall(config.OnEquip, owner, tool, node)
		if not ok then
			self._log.warn(("OnEquip for '%s/%s' errored: %s"):format(slot, name, tostring(err)))
		end
	end

	self.Equipped:Fire(model, record)
	return true, nil
end

function System:Unequip(model: Instance, slot: string)
	local entry = model and self._models[model]
	local record = entry and entry.records[slot]
	if not record then
		return
	end
	local config = record.config
	local node = record.node

	if type(config.OnUnequip) == "function" then
		-- Frozen signature: OnUnequip(nil, nil, node)
		local ok, err = pcall(config.OnUnequip, nil, nil, node)
		if not ok then
			self._log.warn(("OnUnequip for '%s/%s' errored: %s"):format(slot, record.attachmentName, tostring(err)))
		end
	end

	Mounting.restoreGunParts(model, config)

	local slotDef = Slots.get(self._slots, slot)
	if slotDef and slotDef.overridesMuzzle then
		Muzzle.restore(model, self._rootNames)
	end

	if Util.isAlive(node) then
		(node :: any):Destroy()
	end

	self._scheduler:Unregister(model, slot)
	entry.records[slot] = nil
	self.Unequipped:Fire(model, slot, record.attachmentName)
end

-- Unequips everything and removes stray nodes; the model stays tracked with an empty
-- set (original PrepareForEquip).
function System:ResetModel(model: Instance)
	if not model then
		return
	end
	self:_unequipAll(model)
	Mounting.purgeNodes(model, self._options.nodeSuffix)
	self._models[model] = { records = {} }
end

-- Unequips everything, removes stray nodes and forgets the model (original
-- ClearAllAttachments).
function System:ClearModel(model: Instance)
	if not model then
		return
	end
	self:_unequipAll(model)
	Mounting.purgeNodes(model, self._options.nodeSuffix)
	self._models[model] = nil
	self._ownership[model] = nil
	pcall(function()
		(model :: any):SetAttribute(ATTR.activeCustomMuzzle, nil)
	end)
end

-- Rebuilds `model` from a loadout (defaults to the tool's saved loadout). Entries are
-- applied in slot order. Returns { [slot] = ok }.
function System:ApplyLoadout(model: Instance, tool: Instance, owner: any?, loadout: Loadout?): { [string]: boolean }
	local results: { [string]: boolean } = {}
	if not model or not tool then
		return results
	end
	local selected = loadout or self:GetLoadout(tool)
	self:ClearModel(model)
	self:ResetModel(model)

	local slots = {}
	for slot in pairs(selected) do
		table.insert(slots, slot)
	end
	Slots.sortNames(self._slots, slots)
	for _, slot in ipairs(slots) do
		local ok, reason = self:Equip(model, tool, slot, selected[slot], owner)
		results[slot] = ok
		if not ok then
			self._log.warn(("Failed to apply %s -> %s on %s: %s"):format(
				tostring(selected[slot]), slot, tostring((model :: any).Name), tostring(reason)))
		end
	end
	return results
end

-- ─── queries ────────────────────────────────────────────────────────────────

-- Frozen shallow copy { [slot] = Record }. Never nil.
function System:GetActive(model: Instance): { [string]: Record }
	local entry = model and self._models[model]
	if not entry then
		return table.freeze({})
	end
	return table.freeze(table.clone(entry.records))
end

function System:GetRecord(model: Instance, slot: string): Record?
	local entry = model and self._models[model]
	return entry and entry.records[slot] or nil
end

function System:Has(model: Instance, slot: string): boolean
	return self:GetRecord(model, slot) ~= nil
end

function System:IsTracked(model: Instance): boolean
	return model ~= nil and self._models[model] ~= nil
end

function System:GetOwner(model: Instance): Instance?
	return self._ownership[model]
end

function System:GetSlotConfig(model: Instance, slot: string): AttachmentConfig?
	local record = self:GetRecord(model, slot)
	return record and record.config or nil
end

function System:GetConfigField(model: Instance, slot: string, field: string): any
	local config = self:GetSlotConfig(model, slot)
	if config then
		return config[field]
	end
	return nil
end

-- True if any mounted attachment's config has a truthy `field`.
function System:AnyActiveFlag(model: Instance, field: string): boolean
	local entry = model and self._models[model]
	if not entry then
		return false
	end
	for _, record in pairs(entry.records) do
		if record.config[field] then
			return true
		end
	end
	return false
end

-- Aim part from the optic-role attachment: "AimPart<i>" for i > 1, else "AimPart".
function System:GetAimPart(model: Instance, sightIndex: number?): Instance?
	local record = self:_roleRecord(model, "optic")
	if not record then
		return nil
	end
	local node = record.node :: any
	local index = sightIndex or 1
	if index > 1 then
		local indexed = node:FindFirstChild("AimPart" .. index, true)
		if indexed then
			return indexed
		end
	end
	return node:FindFirstChild("AimPart", true)
end

function System:HasHandGrip(model: Instance): boolean
	local record = self:_roleRecord(model, "grip")
	return record ~= nil and record.config.EnableHandPositioning == true
end

function System:GetGripData(model: Instance): GripData?
	local record = self:_roleRecord(model, "grip")
	if not record or not record.config.EnableHandPositioning then
		return nil
	end
	local config = record.config
	if type(config.HandGripPart) ~= "string" then
		return nil
	end
	local gripPart = (record.node :: any):FindFirstChild(config.HandGripPart, true)
	if not gripPart then
		return nil
	end
	local worldCFrame = nil
	if gripPart:IsA("Attachment") then
		worldCFrame = gripPart.WorldCFrame
	elseif gripPart:IsA("BasePart") then
		worldCFrame = gripPart.CFrame
	end
	return {
		gripWorldCFrame = worldCFrame,
		handToPosition = config.HandToPosition or Defaults.grip.handToPosition,
		transitionSpeed = config.HandTransitionSpeed or Defaults.grip.transitionSpeed,
		matchRotation = config.HandMatchRotation ~= false,
	}
end

-- Muzzle point: muzzle-role attachment → ActiveCustomMuzzle node → <Root>.Muzzle.
function System:GetActiveMuzzle(model: Instance): Instance?
	if not model then
		return nil
	end
	local record = self:_roleRecord(model, "muzzle")
	if record then
		local muzzle = (record.node :: any):FindFirstChild("Muzzle", true)
		if muzzle then
			return muzzle
		end
	end

	local customName = (model :: any):GetAttribute(ATTR.activeCustomMuzzle)
	if type(customName) == "string" then
		local nodeName = customName .. self._options.nodeSuffix
		for _, descendant in ipairs((model :: any):GetDescendants()) do
			if descendant:IsA("Folder") and descendant.Name == nodeName then
				local custom = descendant:FindFirstChild("Muzzle", true)
				if custom then
					return custom
				end
			end
		end
	end

	local root = self:_primaryRoot(model)
	return root and (root :: any):FindFirstChild("Muzzle") or nil
end

local function findNamedAttachment(root: any, name: string): Instance?
	local direct = root:FindFirstChild(name)
	if direct and direct:IsA("Attachment") then
		return direct
	end
	for _, descendant in ipairs(root:GetDescendants()) do
		if descendant:IsA("Attachment") and descendant.Name == name then
			return descendant
		end
	end
	return nil
end

-- Laser source: attachment with EnableLaser → <Root>.Laser → any "Laser" Attachment.
function System:GetLaserSource(model: Instance): Instance?
	if not model then
		return nil
	end
	local entry = self._models[model]
	if entry then
		for _, slotDef in ipairs(self._slots.ordered) do
			local record = entry.records[slotDef.name]
			if record and record.config.EnableLaser then
				local source = findNamedAttachment(record.node, "Laser")
				if source then
					return source
				end
			end
		end
		for slot, record in pairs(entry.records) do
			if not self._slots.byName[slot] and record.config.EnableLaser then
				local source = findNamedAttachment(record.node, "Laser")
				if source then
					return source
				end
			end
		end
	end
	local root = self:_primaryRoot(model)
	if root then
		local rootLaser = (root :: any):FindFirstChild("Laser")
		if rootLaser and rootLaser:IsA("Attachment") then
			return rootLaser
		end
	end
	return findNamedAttachment(model, "Laser")
end

-- Flashlight source. NOTE the different precedence (kept from the original):
-- <Root>.Flashlight → attachment with EnableFlashlight → any descendant "Flashlight".
function System:GetFlashlightSource(model: Instance): Instance?
	if not model then
		return nil
	end
	local root = self:_primaryRoot(model)
	if root then
		local rootLight = (root :: any):FindFirstChild("Flashlight")
		if rootLight then
			return rootLight
		end
	end
	local entry = self._models[model]
	if entry then
		for _, slotDef in ipairs(self._slots.ordered) do
			local record = entry.records[slotDef.name]
			if record and record.config.EnableFlashlight then
				local part = (record.node :: any):FindFirstChild("Flashlight", true)
				if part then
					return part
				end
			end
		end
		for slot, record in pairs(entry.records) do
			if not self._slots.byName[slot] and record.config.EnableFlashlight then
				local part = (record.node :: any):FindFirstChild("Flashlight", true)
				if part then
					return part
				end
			end
		end
	end
	return (model :: any):FindFirstChild("Flashlight", true)
end

-- Tweens ADS-dependent parts: TransparentOnADS, VisibleOnADS, LPVOZoom.leverRingName.
-- Tween duration and delay are aimTime / 20 (fallback 0.2s), as before.
function System:ApplyADSVisibility(model: Instance, aiming: boolean, aimTime: number?)
	local entry = model and self._models[model]
	if not entry then
		return
	end
	local duration = if type(aimTime) == "number"
		then aimTime / Defaults.adsTweenDivisor
		else Defaults.adsTweenFallback

	local tween = self._tween or function(part: Instance, time: number, delay: number, goals: { [string]: any })
		local tweenService = (game :: any):GetService("TweenService")
		local info = TweenInfo.new(time, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, delay)
		tweenService:Create(part, info, goals):Play()
	end

	local function setTransparency(node: any, partName: any, transparency: number)
		if type(partName) ~= "string" then
			return
		end
		local part = node:FindFirstChild(partName, true)
		if part and part:IsA("BasePart") then
			pcall(tween, part, duration, duration, { Transparency = transparency })
		end
	end

	for _, record in pairs(entry.records) do
		local config = record.config
		local node = record.node
		if config.TransparentOnADS then
			for _, partName in ipairs(config.TransparentOnADS) do
				setTransparency(node, partName, if aiming then 1 else 0)
			end
		end
		if config.VisibleOnADS then
			for _, partName in ipairs(config.VisibleOnADS) do
				setTransparency(node, partName, if aiming then 0 else 1)
			end
		end
		local lpvo = config.LPVOZoom
		if type(lpvo) == "table" and lpvo.Enabled and lpvo.leverRingName then
			setTransparency(node, lpvo.leverRingName, if aiming then 0 else 1)
		end
	end
end

function System:CleanupMuzzleState(model: Instance)
	if model then
		Muzzle.cleanup(model, self._rootNames)
	end
end

function System:PreHideOriginalMuzzle(model: Instance)
	if model then
		Muzzle.preHide(model, self._rootNames)
	end
end

-- ─── stats ──────────────────────────────────────────────────────────────────

function System:SetBaseStats(tool: Instance, stats: any)
	self._stats:Set(tool, stats)
end

function System:GetBaseStats(tool: Instance): any?
	return self._stats:Get(tool)
end

function System:ForgetBaseStats(tool: Instance)
	self._stats:Forget(tool)
end

-- Copy of the tool's base stats with every mounted ApplyStats modifier applied in
-- slot order. `model` defaults to hooks.resolveModel(tool).
function System:ComputeStats(tool: Instance, model: Instance?): any?
	if not tool then
		return nil
	end
	local base = self._stats:Get(tool)
	if not base then
		return nil
	end

	local target = model
	if not target then
		local resolve = self._options.hooks.resolveModel
		if resolve then
			local ok, resolved = pcall(resolve, tool)
			if ok then
				target = resolved
			end
		end
	end
	if not target then
		return Util.deepCopy(base)
	end

	local owner = self._ownership[target]
	if owner and owner ~= tool then
		return Util.deepCopy(base)
	end

	local entry = self._models[target]
	if not entry then
		return Util.deepCopy(base)
	end

	local slots = {}
	for slot in pairs(entry.records) do
		table.insert(slots, slot)
	end
	Slots.sortNames(self._slots, slots)
	local modifiers = {}
	for _, slot in ipairs(slots) do
		local record = entry.records[slot]
		if type(record.config.ApplyStats) == "function" then
			table.insert(modifiers, { label = slot .. "/" .. record.attachmentName, fn = record.config.ApplyStats })
		end
	end

	local computed = Stats.applyModifiers(base, modifiers, self._log)
	self._stats:WriteModifiedSnapshot(tool, computed)
	return computed
end

-- ─── loadout ────────────────────────────────────────────────────────────────

function System:GetLoadout(tool: Instance): Loadout
	return Loadout.read(tool, self._options.loadout.folderName)
end

function System:HasLoadout(tool: Instance): boolean
	return Loadout.has(tool, self._options.loadout.folderName)
end

-- Validates an untrusted loadout and runs hooks.filterLoadout.
function System:SanitizeLoadout(raw: any, tool: Instance?): Loadout
	local clean = Loadout.sanitize(raw, self._slots, self._options.loadout.maxNameLength)
	local filter = self._options.hooks.filterLoadout
	if filter then
		local ok, filtered = pcall(filter, tool, clean)
		if ok and type(filtered) == "table" then
			clean = Loadout.sanitize(filtered, self._slots, self._options.loadout.maxNameLength)
		elseif not ok then
			self._log.warn("filterLoadout errored: " .. tostring(filtered))
		end
	end
	return clean
end

function System:SetLoadout(tool: Instance, loadout: Loadout)
	if not tool then
		return
	end
	local slots = {}
	for slot in pairs(loadout) do
		table.insert(slots, slot)
	end
	Slots.sortNames(self._slots, slots)
	local loadoutOptions = self._options.loadout
	Loadout.write(tool, loadout, loadoutOptions.folderName, loadoutOptions.jsonAttribute,
		self._newInstance, getHttp(self), slots)
end

-- Checks a config flag across the tool's *saved* loadout (no mounted model needed).
-- `slot` restricts the check to one slot.
function System:LoadoutHasFlag(tool: Instance, field: string, slot: string?): boolean
	local loadout = self:GetLoadout(tool)
	for loadoutSlot, name in pairs(loadout) do
		if slot == nil or loadoutSlot == slot then
			local config = self._registry:LoadConfig(loadoutSlot, name)
			if config and config[field] then
				return true
			end
		end
	end
	return false
end

-- ─── teardown ───────────────────────────────────────────────────────────────

function System:Destroy()
	if self._destroyed then
		return
	end
	self._destroyed = true
	local models = {}
	for model in pairs(self._models) do
		table.insert(models, model)
	end
	for _, model in ipairs(models) do
		if Util.isAlive(model) then
			self:ClearModel(model)
		end
	end
	for _, hook in pairs(self._destroyHooks) do
		hook:Disconnect()
	end
	table.clear(self._destroyHooks)
	table.clear(self._models)
	table.clear(self._ownership)
	self._scheduler:Destroy()
	self._stats:Clear()
	self.Equipped:DisconnectAll()
	self.Unequipped:DisconnectAll()
	self.ModelCleared:DisconnectAll()
end

return System
