--!nonstrict
-- Customize/Signal
-- Minimal synchronous signal. A handler error is reported and does not stop the
-- remaining handlers. No Roblox dependencies (unit-testable in the Luau CLI).

local Signal = {}
Signal.__index = Signal

local report = (warn or print) :: (...any) -> ()

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(handler: (...any) -> ())
	local entry = { fn = handler, connected = true }
	table.insert(self._handlers, entry)
	local signal = self
	return {
		Connected = true,
		Disconnect = function(connection)
			if not entry.connected then
				return
			end
			entry.connected = false
			connection.Connected = false
			local index = table.find(signal._handlers, entry)
			if index then
				table.remove(signal._handlers, index)
			end
		end,
	}
end

function Signal:Fire(...: any)
	-- Snapshot so handlers may connect/disconnect while firing.
	for _, entry in ipairs(table.clone(self._handlers)) do
		if entry.connected then
			local ok, err = pcall(entry.fn, ...)
			if not ok then
				report("[CustomizeUI] signal handler errored:", err)
			end
		end
	end
end

function Signal:DisconnectAll()
	for _, entry in ipairs(self._handlers) do
		entry.connected = false
	end
	table.clear(self._handlers)
end

return Signal
