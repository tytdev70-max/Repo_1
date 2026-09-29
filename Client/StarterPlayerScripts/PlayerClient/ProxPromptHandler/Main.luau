--!strict

local Players                = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace              = game:GetService("Workspace")

export type PromptHandlerDef = {
	name: string,
	match: (prompt: ProximityPrompt) -> boolean,
	configure: ((prompt: ProximityPrompt) -> ())?,
	onDetected: ((prompt: ProximityPrompt) -> ())?,
	onTriggered: ((prompt: ProximityPrompt, player: Player) -> ())?,
	onRemoved: ((prompt: ProximityPrompt) -> ())?,
}

local Main = {}

local registeredHandlers: { PromptHandlerDef }                    = {}
local trackedPrompts:     { [ProximityPrompt]: PromptHandlerDef } = {}
local promptConns:        { [ProximityPrompt]: { RBXScriptConnection } } = {}
local initialized = false

local ReleasePrompt: (ProximityPrompt) -> ()

-- ---------------------------------------------------------------------------
-- Internal helpers
-- ---------------------------------------------------------------------------

local function ClaimPrompt(prompt: ProximityPrompt, onlyHandler: PromptHandlerDef?)
	if trackedPrompts[prompt] then
		return
	end
	if not prompt:IsDescendantOf(game) then
		return
	end

	local matched: PromptHandlerDef? = nil

	if onlyHandler then
		local ok, m = pcall(onlyHandler.match, prompt)
		if ok and m then matched = onlyHandler end
	else
		for _, candidate in ipairs(registeredHandlers) do
			local ok, m = pcall(candidate.match, prompt)
			if ok and m then
				matched = candidate
				break
			end
		end
	end

	if not matched then
		return
	end

	if matched.configure then
		local ok, err = pcall(matched.configure, prompt)
		if not ok then
			warn(("[ProxPromptHandler] '%s'.configure errored: %s"):format(matched.name, tostring(err)))
		end
	end

	trackedPrompts[prompt] = matched

	local conns: { RBXScriptConnection } = {}
	promptConns[prompt] = conns

	table.insert(conns, prompt.Destroying:Connect(function()
		ReleasePrompt(prompt)
	end))

	table.insert(conns, prompt.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			ReleasePrompt(prompt)
		end
	end))

	if matched.onDetected then
		local ok, err = pcall(matched.onDetected, prompt)
		if not ok then
			warn(("[ProxPromptHandler] '%s'.onDetected errored: %s"):format(matched.name, tostring(err)))
		end
	end
end

function ReleasePrompt(prompt: ProximityPrompt)
	local handler = trackedPrompts[prompt]
	if not handler then
		return
	end
	trackedPrompts[prompt] = nil

	local conns = promptConns[prompt]
	if conns then
		for _, c in ipairs(conns) do
			if c.Connected then c:Disconnect() end
		end
		promptConns[prompt] = nil
	end

	if handler.onRemoved then
		local ok, err = pcall(handler.onRemoved, prompt)
		if not ok then
			warn(("[ProxPromptHandler] '%s'.onRemoved errored: %s"):format(handler.name, tostring(err)))
		end
	end
end

local function ScanExisting(onlyHandler: PromptHandlerDef?)
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("ProximityPrompt") then
			ClaimPrompt(desc, onlyHandler)
		end
	end
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

function Main.RegisterHandler(def: PromptHandlerDef)
	assert(type(def) == "table", "RegisterHandler expects a table")
	assert(type(def.name) == "string", "RegisterHandler requires a 'name'")
	assert(type(def.match) == "function", "RegisterHandler requires a 'match' function")

	table.insert(registeredHandlers, def)
	ScanExisting(def)
end

function Main.GetTracked(prompt: ProximityPrompt): PromptHandlerDef?
	return trackedPrompts[prompt]
end

function Main.Init()
	if initialized then return end
	initialized = true

	ScanExisting(nil)

	Workspace.DescendantAdded:Connect(function(desc)
		if desc:IsA("ProximityPrompt") then
			ClaimPrompt(desc, nil)
		end
	end)

	Workspace.DescendantRemoving:Connect(function(desc)
		if desc:IsA("ProximityPrompt") then
			ReleasePrompt(desc)
		end
	end)
	
	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		local handler = trackedPrompts[prompt]
		if not handler or not handler.onTriggered then return end
		local ok, err = pcall(handler.onTriggered, prompt, player)
		if not ok then
			warn(("[ProxPromptHandler] '%s'.onTriggered errored: %s")
				:format(handler.name, tostring(err)))
		end
	end)
end

Main.Init()

return Main