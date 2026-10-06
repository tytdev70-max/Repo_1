--!nonstrict
-- GunAttachments/Signal
-- Minimal synchronous signal. Handlers run in order; an erroring handler is reported
-- through the provided error callback and never breaks the emitter or other handlers.

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

export type Signal = {
	Connect: (self: Signal, handler: (...any) -> ()) -> Connection,
	Once: (self: Signal, handler: (...any) -> ()) -> Connection,
	Fire: (self: Signal, ...any) -> (),
	DisconnectAll: (self: Signal) -> (),
}

local Signal = {}
Signal.__index = Signal

function Signal.new(onError: ((string) -> ())?): Signal
	local self = setmetatable({
		_handlers = {} :: { any },
		_onError = onError,
	}, Signal)
	return (self :: any) :: Signal
end

function Signal:Connect(handler: (...any) -> ()): Connection
	local signal = self :: any
	local connection = { Connected = true, _handler = handler }
	function connection.Disconnect(conn: any)
		if not conn.Connected then
			return
		end
		conn.Connected = false
		local handlers = signal._handlers
		for index = #handlers, 1, -1 do
			if handlers[index] == conn then
				table.remove(handlers, index)
				break
			end
		end
	end
	table.insert(signal._handlers, connection)
	return (connection :: any) :: Connection
end

function Signal:Once(handler: (...any) -> ()): Connection
	local connection: Connection
	connection = (self :: any):Connect(function(...: any)
		connection:Disconnect()
		handler(...)
	end)
	return connection
end

function Signal:Fire(...: any)
	local signal = self :: any
	-- Snapshot so handlers may disconnect while firing.
	local snapshot = table.clone(signal._handlers)
	for _, connection in ipairs(snapshot) do
		if connection.Connected then
			local ok, err = pcall(connection._handler, ...)
			if not ok and signal._onError then
				signal._onError(tostring(err))
			end
		end
	end
end

function Signal:DisconnectAll()
	local signal = self :: any
	for _, connection in ipairs(signal._handlers) do
		connection.Connected = false
	end
	table.clear(signal._handlers)
end

return Signal
