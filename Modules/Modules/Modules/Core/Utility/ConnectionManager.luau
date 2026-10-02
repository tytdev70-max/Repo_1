local ConnectionManager = {}
ConnectionManager.__index = ConnectionManager

function ConnectionManager.new()
	return setmetatable({ _connections = {} }, ConnectionManager)
end

function ConnectionManager:Add(connection)
	table.insert(self._connections, connection)
	return connection
end

function ConnectionManager:DisconnectAll()
	for _, conn in ipairs(self._connections) do
		if conn.Connected then
			conn:Disconnect()
		end
	end
	table.clear(self._connections)
end

function ConnectionManager:Count()
	return #self._connections
end

return ConnectionManager