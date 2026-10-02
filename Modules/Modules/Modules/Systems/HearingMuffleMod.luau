local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")

local HearingMuffleMod = {}

local MUFFLE_MAX_LOW_ATTEN  = -6
local MUFFLE_MAX_MID_ATTEN  = -34
local MUFFLE_MAX_HIGH_ATTEN = -80

local masterGroup = nil
local muffleFilter = nil

local function GetMasterGroup()
	if masterGroup and masterGroup.Parent then
		return masterGroup
	end
	local existing = SoundService:FindFirstChild("SPH_MasterMix")
	if existing and existing:IsA("SoundGroup") then
		masterGroup = existing
	else
		local group = Instance.new("SoundGroup")
		group.Name = "SPH_MasterMix"
		group.Volume = 1
		group.Parent = SoundService
		masterGroup = group
	end
	return masterGroup
end

local function GetFilter()
	if muffleFilter and muffleFilter.Parent then
		return muffleFilter
	end
	local group = GetMasterGroup()
	local existing = group:FindFirstChild("SPH_HearingMuffle")
	if existing and existing:IsA("EqualizerSoundEffect") then
		muffleFilter = existing
	else
		local filter = Instance.new("EqualizerSoundEffect")
		filter.Name = "SPH_HearingMuffle"
		filter.LowGain = 0
		filter.MidGain = 0
		filter.HighGain = 0
		filter.Enabled = true
		filter.Parent = group
		muffleFilter = filter
	end
	return muffleFilter
end
HearingMuffleMod.GetFilter = GetFilter

local function ClaimSound(sound)
	if not sound or not sound:IsA("Sound") then return end
	if CollectionService:HasTag(sound, "SPH_NoMuffle") then return end
	local group = GetMasterGroup()
	if sound.SoundGroup ~= group then
		sound.SoundGroup = group
	end
end

local initialized = false

function HearingMuffleMod.Init()
	if initialized then return end
	initialized = true

	GetFilter()

	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("Sound") then
			ClaimSound(inst)
		end
	end

	game.DescendantAdded:Connect(function(inst)
		if inst:IsA("Sound") then
			ClaimSound(inst)
		end
	end)
end

local activeSources = {}
local sourceSeq = 0
local activeTween = nil

local function CancelActiveTween()
	if activeTween then
		pcall(function() activeTween:Cancel() end)
		activeTween = nil
	end
end

local function ComputeMaxIntensity()
	local max = 0
	for _, intensity in pairs(activeSources) do
		if intensity > max then
			max = intensity
		end
	end
	return max
end

local function ApplyGains(intensity, time)
	local filter = GetFilter()
	if not filter then return end
	filter.Enabled = true
	CancelActiveTween()
	time = math.clamp(time or 0.25, 0.05, 5)
	activeTween = TweenService:Create(
		filter,
		TweenInfo.new(time, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
		{
			LowGain  = MUFFLE_MAX_LOW_ATTEN  * intensity,
			MidGain  = MUFFLE_MAX_MID_ATTEN  * intensity,
			HighGain = MUFFLE_MAX_HIGH_ATTEN * intensity,
		}
	)
	activeTween:Play()
end

function HearingMuffleMod.BeginMuffle(intensity, attackTime)
	intensity = math.clamp(tonumber(intensity) or 0, 0, 1)
	if intensity <= 0 then return nil end

	sourceSeq += 1
	local token = sourceSeq
	activeSources[token] = intensity

	ApplyGains(ComputeMaxIntensity(), attackTime)
	return token
end

function HearingMuffleMod.UpdateMuffle(token, intensity, transitionTime)
	if not token or activeSources[token] == nil then return end
	intensity = math.clamp(tonumber(intensity) or 0, 0, 1)
	activeSources[token] = intensity
	ApplyGains(ComputeMaxIntensity(), transitionTime or 0.15)
end

function HearingMuffleMod.EndMuffle(token, releaseTime)
	if not token or activeSources[token] == nil then return end
	activeSources[token] = nil
	releaseTime = math.clamp(releaseTime or 0.6, 0.1, 8)
	ApplyGains(ComputeMaxIntensity(), releaseTime)
end

function HearingMuffleMod.PulseMuffle(intensity, holdDuration)
	intensity = math.clamp(tonumber(intensity) or 0, 0, 1)
	if intensity <= 0 then return end

	local totalDuration = math.clamp(holdDuration or (0.5 + intensity * 4.5), 0.3, 20)
	local attackTime  = math.clamp(totalDuration * 0.06, 0.05, 0.35)
	local releaseTime = math.max(totalDuration - attackTime, 0.3)

	local token = HearingMuffleMod.BeginMuffle(intensity, attackTime)
	if not token then return end

	task.delay(math.max(totalDuration - releaseTime, 0), function()
		HearingMuffleMod.EndMuffle(token, releaseTime)
	end)
end

function HearingMuffleMod.Reset()
	activeSources = {}
	CancelActiveTween()
	local filter = muffleFilter
	if filter and filter.Parent then
		filter.LowGain = 0
		filter.MidGain = 0
		filter.HighGain = 0
	end
end

return HearingMuffleMod