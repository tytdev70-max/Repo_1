local DoorConfig = {}

-- Kicking
DoorConfig.KickCooldown = 1.2        -- seconds before this door can be kicked again
DoorConfig.KickWhooshLeadTime = 0.3
DoorConfig.PhysicsDamping = 0      -- softens every kick's tween duration (0-1)
DoorConfig.KickPartCleanupDelay = 0 -- seconds until debris from the final break-down is destroyed (0 = never)

DoorConfig.KickDefaults = {
	Angle = 10,
	BreakDownAngle = 100,
	Duration = 0.05,
	BreakDownDuration = 0.3,
	ReturnDuration = 0.1, -- seconds for the door to snap back closed after a normal kick
	TweenStyle = Enum.EasingStyle.Back,
	TweenDirection = Enum.EasingDirection.Out,
	ShakeEnabled = true,
	ShakePreset = "Bump",
	ShakeImpulse = 9,
	Sound = "DoorKick",
	PlayImpactVariant = true,
	BreakParts = {},
	LinearImpulse = 40,
	UpwardBias = 10,
	AngularImpulse = 6,
	CleanupDelay = 0,
}

-- Peeking
DoorConfig.PeekAngle = 25
DoorConfig.PeekSpeed = 1.1

-- Opening / Closing
DoorConfig.OpenAngle = 90
DoorConfig.OpenSpeed = 1.3
DoorConfig.CloseSpeed = 2
DoorConfig.AutoCloseDelay = 0

-- Physics
DoorConfig.DoorMassOverride = nil

-- Tweening (used for peek/open/close/kick-return)
DoorConfig.TweenStyle = Enum.EasingStyle.Quad
DoorConfig.TweenDirection = Enum.EasingDirection.Out

-- Sound
DoorConfig.SoundVolume = 0.6
DoorConfig.SoundPitch = 1

-- Prompts
DoorConfig.PromptMaxDistance = 8
DoorConfig.PromptHoldDuration = 0.5
DoorConfig.PromptObjectText = "Door"
DoorConfig.PromptTexts = {
	Kick = "Kick",
	Peek = "Peek",
	Unpeek = "Stop Peeking",
	Open = "Open",
	Close = "Close",
}

DoorConfig.PartLookupTimeout = 5

DoorConfig.MovingParts = {
	Main = true,
}

DoorConfig.WeldedParts = {
	Knob1 = true,
	Knob2 = true,
	Kickable = true,
	Openable = true,
	Peekable = true,
}

DoorConfig.KickedDownUnanchorParts = {
	Knob1 = false,
	Knob2 = false,
}

return DoorConfig