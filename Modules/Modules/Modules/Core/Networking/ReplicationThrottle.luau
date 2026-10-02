local ReplicationThrottle = {}
ReplicationThrottle.__index = ReplicationThrottle

function ReplicationThrottle.new(minInterval)
	return setmetatable({
		_lastValue = nil,
		_lastSendTime = 0,
		_minInterval = minInterval or 0,
	}, ReplicationThrottle)
end

function ReplicationThrottle:ShouldSend(newValue, deltaThreshold, deltaFn)
	local now = os.clock()
	if now - self._lastSendTime < self._minInterval then
		return false
	end
	if self._lastValue == nil then
		self._lastValue = newValue
		self._lastSendTime = now
		return true
	end
	local changed
	if deltaFn then
		changed = deltaFn(self._lastValue, newValue) > (deltaThreshold or 0)
	else
		changed = self._lastValue ~= newValue
	end
	if changed then
		self._lastValue = newValue
		self._lastSendTime = now
		return true
	end
	return false
end

function ReplicationThrottle:Reset()
	self._lastValue = nil
	self._lastSendTime = 0
end

function ReplicationThrottle:ForceSend(newValue)
	self._lastValue = newValue
	self._lastSendTime = os.clock()
end

return ReplicationThrottle