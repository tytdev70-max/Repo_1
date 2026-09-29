--// RingAudio.lua
--// Handles local tinnitus/ring sound playback with fade-out, and provides
--// explosion muffle preset resolution.  No external module dependencies
--// beyond ServiceRefs.

local RingAudio = {}

local ServiceRefs  = require(script.Parent.ServiceRefs)
local RunService   = ServiceRefs.RunService
local SoundService = ServiceRefs.SoundService

--// Constants

local RING_SOUND_DEFAULT_CUTOFF  = 6	:: number
local RING_SOUND_MAX_CUTOFF      = 20	:: number
local RING_SOUND_FADE_TIME       = 2.5	:: number

local EXPLOSION_MUFFLE_PRESETS: {
	[string]: { strength: number, minDuration: number, maxDuration: number }
} = {
	Frag = { strength = 1.0, minDuration = 1.2, maxDuration = 3.5  },
	M84  = { strength = 1.0, minDuration = 4.0, maxDuration = 12.0 },
}

local DEFAULT_MUFFLE_PRESET: { strength: number, minDuration: number, maxDuration: number } = {
	strength    = 0.85,
	minDuration = 1.0,
	maxDuration = 3.0,
}

--// Public

--- Returns the muffle preset table for the given explosion type string,
--- falling back to DEFAULT_MUFFLE_PRESET when none is registered.
function RingAudio.GetMufflePreset(
	explosionType: string
): { strength: number, minDuration: number, maxDuration: number }
	return EXPLOSION_MUFFLE_PRESETS[explosionType] or DEFAULT_MUFFLE_PRESET
end

--- Plays a looping ring sound locally, then fades it out after `holdDuration`
--- seconds.  Identical behavior to the original `playLocalRingSound`.
function RingAudio.PlayLocalRingSound(
	soundId      : any,
	intensity    : number,
	holdDuration : number?
): ()
	if not soundId then
		return
	end

	local s: Sound = Instance.new("Sound")
	s.SoundId          = "rbxassetid://" .. tostring(soundId)
	s.Parent           = SoundService
	s.Volume           = math.clamp(0.6 + intensity * 0.9, 0.5, 1.5)
	s.RollOffMode      = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = 10
	s.Looped           = true

	local ok: boolean = pcall(function(): ()
		SoundService:PlayLocalSound(s)
	end)
	if not ok then
		pcall(function(): ()
			s:Play()
		end)
	end

	local cleanedUp: boolean                    = false
	local fadeConn       						= nil :: RBXScriptConnection?
	local endedConn      						= nil :: RBXScriptConnection?

	local function CleanUp(): ()
		if cleanedUp then return end
		cleanedUp = true

		if endedConn then
			endedConn:Disconnect()
			endedConn = nil
		end
		if fadeConn then
			fadeConn:Disconnect()
			fadeConn = nil
		end
		if s and s.Parent then
			pcall(function() s:Destroy() end)
		end
	end

	endedConn = s.Ended:Connect(CleanUp)

	local cutoff: number = math.clamp(
		holdDuration or RING_SOUND_DEFAULT_CUTOFF,
		1, RING_SOUND_MAX_CUTOFF
	)

	task.delay(cutoff, function(): ()
		if cleanedUp or not s or not s.Parent then return end
		if endedConn then
			endedConn:Disconnect()
			endedConn = nil
		end

		local fadeStart  : number = tick()
		local fromVolume : number = s.Volume

		fadeConn = RunService.Heartbeat:Connect(function(): ()
			if cleanedUp or not s or not s.Parent then
				if fadeConn then
					fadeConn:Disconnect()
					fadeConn = nil
				end
				return
			end

			local alpha: number = math.clamp(
				(tick() - fadeStart) / RING_SOUND_FADE_TIME,
				0, 1
			)
			local eased: number = math.sin(alpha * (math.pi / 2))
			s.Volume = fromVolume * (1 - eased)

			if alpha >= 1 then
				if fadeConn then
					fadeConn:Disconnect()
					fadeConn = nil
				end
				CleanUp()
			end
		end)
	end)
end

return RingAudio