--[[
	Keyed registry for ByteNet packet listeners on the client.

	ByteNet listeners live in the packet module, not in the script that registered
	them, so a listener registered by a character script keeps firing after that
	character is gone. Binding through a key guarantees only the newest listener
	for that key stays connected: rebinding disconnects the previous one, so a
	generation that failed to clean itself up cannot stack a second callback and
	make replicated effects (shells, lasers, lean, ...) fire twice.
]]

local ClientBridge = {}

local bound: {[string]: () -> ()} = {}

function ClientBridge.unbind(key: string)
	local disconnect = bound[key]
	if disconnect then
		bound[key] = nil
		pcall(disconnect)
	end
end

function ClientBridge.bind(key: string, packet, callback)
	ClientBridge.unbind(key)
	bound[key] = packet.listen(callback)
end

function ClientBridge.unbindAll()
	local keys = {}
	for key in pairs(bound) do
		table.insert(keys, key)
	end
	for _, key in ipairs(keys) do
		ClientBridge.unbind(key)
	end
end

function ClientBridge.isBound(key: string): boolean
	return bound[key] ~= nil
end

return ClientBridge