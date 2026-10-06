--!nonstrict
-- GunAttachments/Scheduler
-- Drives config.OnUpdate for mounted attachments. The heartbeat connection exists only
-- while at least one updater is registered (same as the original implementation).

export type Scheduler = {
	Register: (self: Scheduler, model: Instance, slot: string, fn: any) -> (),
	Unregister: (self: Scheduler, model: Instance, slot: string) -> (),
	UnregisterModel: (self: Scheduler, model: Instance) -> (),
	Count: (self: Scheduler) -> number,
	Destroy: (self: Scheduler) -> (),
}

local Scheduler = {}
Scheduler.__index = Scheduler

-- getHeartbeat: () -> signal (resolved lazily so requiring never touches services)
-- onDeadModel: (model) -> ()  called when a registered model lost its parent
function Scheduler.new(getHeartbeat: () -> any, onDeadModel: (Instance) -> ()): Scheduler
	local self = setmetatable({
		_entries = {} :: { [Instance]: { [string]: any } },
		_count = 0,
		_connection = nil :: any,
		_getHeartbeat = getHeartbeat,
		_onDeadModel = onDeadModel,
	}, Scheduler)
	return (self :: any) :: Scheduler
end

local function step(self: any, deltaTime: number)
	for model, slots in pairs(self._entries) do
		local alive = false
		pcall(function()
			alive = (model :: any).Parent ~= nil
		end)
		if not alive then
			self._onDeadModel(model)
		else
			for _, fn in pairs(slots) do
				-- Frozen signature: OnUpdate(nil, nil, deltaTime)
				pcall(fn, nil, nil, deltaTime)
			end
		end
	end
end

local function ensureConnected(self: any)
	if self._connection or self._count <= 0 then
		return
	end
	local heartbeat = self._getHeartbeat()
	if heartbeat then
		self._connection = heartbeat:Connect(function(deltaTime: number)
			step(self, deltaTime)
		end)
	end
end

local function maybeDisconnect(self: any)
	if self._count <= 0 and self._connection then
		self._connection:Disconnect()
		self._connection = nil
	end
end

function Scheduler:Register(model: Instance, slot: string, fn: any)
	local scheduler = self :: any
	if type(fn) ~= "function" then
		return
	end
	local slots = scheduler._entries[model]
	if not slots then
		slots = {}
		scheduler._entries[model] = slots
	end
	if slots[slot] == nil then
		scheduler._count += 1
	end
	slots[slot] = fn
	ensureConnected(scheduler)
end

function Scheduler:Unregister(model: Instance, slot: string)
	local scheduler = self :: any
	local slots = scheduler._entries[model]
	if not slots or slots[slot] == nil then
		return
	end
	slots[slot] = nil
	scheduler._count = math.max(0, scheduler._count - 1)
	if next(slots) == nil then
		scheduler._entries[model] = nil
	end
	maybeDisconnect(scheduler)
end

function Scheduler:UnregisterModel(model: Instance)
	local scheduler = self :: any
	local slots = scheduler._entries[model]
	if not slots then
		return
	end
	for _ in pairs(slots) do
		scheduler._count = math.max(0, scheduler._count - 1)
	end
	scheduler._entries[model] = nil
	maybeDisconnect(scheduler)
end

function Scheduler:Count(): number
	return (self :: any)._count
end

function Scheduler:Destroy()
	local scheduler = self :: any
	table.clear(scheduler._entries)
	scheduler._count = 0
	maybeDisconnect(scheduler)
end

return Scheduler
