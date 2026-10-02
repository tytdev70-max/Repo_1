-- Indoor_Reverb/IndoorAudioReverb
-- Applies SoundService.AmbientReverb while the local player is under a ceiling.
--
-- Installed by CoreModuleInits: IndoorAudioReverb.init(character)
-- Lives under SPH_Character.Client (StarterCharacterScripts), so a fresh copy of
-- this module runs for every character; it only ever tracks the character it was
-- given and cleans itself up when that character dies or is removed.
--
-- Per-building reverb: set a string attribute "ReverbZone" (any Enum.ReverbType name,
-- e.g. "Hallway", "Cave", "LivingRoom") on the ceiling part OR on any ancestor
-- (e.g. the building Model). Otherwise INDOOR_REVERB_DEFAULT is used.

local Reverb = {}

--// Services

local RunService   = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

--// Config

local CHECK_INTERVAL        = 0.15                 -- seconds between checks; reverb doesn't need per-frame accuracy
local CAST_OFFSET           = Vector3.new(0, 90, 0) -- how far up to look for a ceiling
local MAX_CAST_PASSES       = 4                    -- re-casts allowed when skipping non-ceiling hits
local REVERB_ZONE_ATTRIBUTE = "ReverbZone"
local INDOOR_REVERB_DEFAULT = Enum.ReverbType.City
local OUTDOOR_REVERB        = Enum.ReverbType.NoReverb

--// State

local camera: Camera = workspace.CurrentCamera :: Camera
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude

local character: Model? = nil
local head: BasePart? = nil
local baseFilter: { Instance } = {}
local heartbeatConn: RBXScriptConnection? = nil
local lifecycleConns: { RBXScriptConnection } = {}
local timeSinceLastCheck = 0
local activeReverb: Enum.ReverbType? = nil
local warnedZones: { [string]: boolean } = {}

--// Reverb handling

local function applyReverb(reverb: Enum.ReverbType)
	if activeReverb == reverb then
		return
	end
	activeReverb = reverb
	SoundService.AmbientReverb = reverb
end

-- Converts an attribute string to Enum.ReverbType (invalid names fall back to default).
local function parseReverbName(name: string): Enum.ReverbType?
	local ok, value = pcall(function()
		return (Enum.ReverbType :: any)[name]
	end)
	if ok and value then
		return value
	end
	if not warnedZones[name] then
		warnedZones[name] = true
		warn(string.format("[IndoorAudioReverb] '%s' is not a valid Enum.ReverbType name", name))
	end
	return nil
end

-- Looks for a ReverbZone attribute on the ceiling part, then up its ancestors.
local function reverbForCeiling(part: BasePart): Enum.ReverbType
	local current: Instance? = part
	while current and current ~= workspace do
		local zone = current:GetAttribute(REVERB_ZONE_ATTRIBUTE)
		if typeof(zone) == "string" then
			return parseReverbName(zone) or INDOOR_REVERB_DEFAULT
		end
		current = current.Parent
	end
	return INDOOR_REVERB_DEFAULT
end

-- A hit only counts as a ceiling if it's visible and not part of another character
-- (e.g. a player standing on the roof, or a hat) — otherwise we skip it and keep looking.
local function isCeiling(part: BasePart): boolean
	if part.Transparency >= 1 then
		return false
	end
	local model = part:FindFirstAncestorOfClass("Model")
	while model do
		if model:FindFirstChildOfClass("Humanoid") then
			return false
		end
		model = model:FindFirstAncestorOfClass("Model")
	end
	return true
end

local function checkOverhead()
	if not head or not head.Parent then
		return
	end

	local origin = head.Position
	local filter = table.clone(baseFilter)

	for _ = 1, MAX_CAST_PASSES do
		raycastParams.FilterDescendantsInstances = filter
		local result = workspace:Raycast(origin, CAST_OFFSET, raycastParams)
		if not result then
			break
		end

		local hit = result.Instance
		if hit:IsA("BasePart") and isCeiling(hit) then
			applyReverb(reverbForCeiling(hit))
			return
		end

		-- Skip this hit and cast again from the same origin
		table.insert(filter, hit)
	end

	applyReverb(OUTDOOR_REVERB)
end

local function onHeartbeat(deltaTime: number)
	timeSinceLastCheck += deltaTime
	if timeSinceLastCheck < CHECK_INTERVAL then
		return
	end
	timeSinceLastCheck = 0
	checkOverhead()
end

--// Lifecycle

-- Stops detection. Pass resetReverb = true to restore outdoor reverb (used when the
-- character is removed; on death we keep the current reverb so death sounds match the room).
function Reverb.stop(resetReverb: boolean?)
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
	if resetReverb then
		applyReverb(OUTDOOR_REVERB)
	end
end

local function cleanup()
	Reverb.stop(true)
	for _, conn in ipairs(lifecycleConns) do
		conn:Disconnect()
	end
	table.clear(lifecycleConns)
	character = nil
	head = nil
end

function Reverb.init(newCharacter: Model)
	if character then
		return -- already running for this character
	end
	character = newCharacter

	head = newCharacter:WaitForChild("Head", 10) :: BasePart?
	local humanoid = newCharacter:WaitForChild("Humanoid", 10) :: Humanoid?
	if not head or not humanoid then
		warn("[IndoorAudioReverb] Head/Humanoid not found; indoor reverb disabled for this character")
		cleanup()
		return
	end

	-- Ignore our own character, the camera (viewmodel lives there) and SPH runtime
	-- parts (bullets, shells, drops, smoke) so they're never mistaken for a ceiling.
	baseFilter = { newCharacter, camera }
	local sphWorkspace = workspace:FindFirstChild("SPH_Workspace")
	if sphWorkspace then
		table.insert(baseFilter, sphWorkspace)
	end

	table.insert(lifecycleConns, humanoid.Died:Connect(function()
		Reverb.stop(false)
	end))
	table.insert(lifecycleConns, newCharacter.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanup()
		end
	end))
	table.insert(lifecycleConns, script.Destroying:Connect(cleanup))

	-- Start with an immediate check so reverb is correct as soon as we spawn
	timeSinceLastCheck = 0
	checkOverhead()
	heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)
end

return Reverb