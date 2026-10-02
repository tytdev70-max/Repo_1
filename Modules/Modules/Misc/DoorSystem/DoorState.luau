local DoorState = {}
DoorState.States = {
	Locked = "Locked";
	Closed = "Closed";
	Peeked = "Peeked";
	Opened = "Opened";
	Broken = "Broken";
}
DoorState.Transitions = {
	[DoorState.States.Locked] = { Kick = true };
	[DoorState.States.Closed] = { Kick = true, Peek = true };
	[DoorState.States.Peeked] = { Open = true, Unpeek = true };
	[DoorState.States.Opened] = { Close = true };
	[DoorState.States.Broken] = {};
}
function DoorState.CanFire(currentState, action)
	local allowed = DoorState.Transitions[currentState]
	return allowed ~= nil and allowed[action] == true
end
return DoorState