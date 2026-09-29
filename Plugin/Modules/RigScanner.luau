--[[
	RigScanner.luau
	---------------
	Module 1 of 6 - the unified rig scanner.

	Responsibility
		* Locate the `AnimSaves` container inside a rig.
		* Resolve that container with ONE unified rule, no matter what class it is.
		* Collect every `KeyframeSequence` it exposes.
		* Return a structured, ordered result that the UI and the uploader consume.

	The unified rule
		The Roblox Animation Editor has historically saved a rig's animations in
		two different shapes:

		  1. `AnimSaves` as a **Model**  whose direct children are KeyframeSequences.
		  2. `AnimSaves` as an **ObjectValue** whose direct children are
		     KeyframeSequences, and whose `.Value` is the *name of its parent*
		     (the rig), used as a back-reference.

		Both shapes expose the sequences through the exact same call,
		`container:GetChildren()`, so the scanner deliberately does NOT branch on
		class. It only records the class so the UI can label it. The only
		class-specific handling is reading `.Value` when it exists, which is used
		purely as a label/alias and never as a lookup path.

		See Plugin/API_RESEARCH.md for the DevForum references that motivated this.

	No hardcoded paths: the scanner never assumes `Workspace.Rig.AnimSaves`.
	Rigs are discovered by searching a configurable set of service roots with a
	scan budget, and the user can always point the plugin at an explicit instance.
]]

local Selection = game:GetService("Selection")

local RigScanner = {}
RigScanner.__index = RigScanner

--[[
	Default configuration. Every value can be overridden per-instance so the
	command-bar build and the plugin build can share the module.
]]
RigScanner.Defaults = {
	-- Services searched when auto-discovering rigs. Workspace first because
	-- that is where the Animation Editor puts rigs by default.
	SearchRoots = { "Workspace", "ServerStorage", "ReplicatedStorage" },

	-- Name of the container we look for (case-insensitive match).
	ContainerName = "AnimSaves",

	-- Safety valve: stop descending after this many instances so a pathological
	-- place (100k+ instances) can never freeze Studio.
	ScanBudget = 25000,

	-- How deep below `AnimSaves` we keep looking for KeyframeSequences.
	-- 1 = direct children only (the documented layout).
	-- 2+ = also look inside sub-folders/models of AnimSaves.
	MaxContainerDepth = 3,
}

export type RigScanResult = {
	rig: Instance?,
	rigName: string?,
	container: Instance?,
	containerClass: string?,
	containerAlias: string?,
	aliasMatchesRig: boolean,
	sequences: { KeyframeSequence },
	-- metadata rows, 1:1 with `sequences`
	entries: { RigScanner.Entry },
	truncated: boolean,
	error: string?,
}

export type Entry = {
	sequence: KeyframeSequence,
	name: string,
	container: Instance,
	subPath: string, -- "" when the sequence is a direct child of AnimSaves
	depth: number,
}

--------------------------------------------------------------------------------
-- Construction
--------------------------------------------------------------------------------

function RigScanner.new(options: { [string]: any }?): RigScanner
	local self = setmetatable({}, RigScanner)
	self._options = {}
	for key, value in pairs(RigScanner.Defaults) do
		self._options[key] = value
	end
	if options then
		for key, value in pairs(options) do
			if RigScanner.Defaults[key] ~= nil or key == "SearchRoots" then
				self._options[key] = value
			end
		end
	end
	self._budgetUsed = 0
	return self
end

--------------------------------------------------------------------------------
-- Container resolution
--------------------------------------------------------------------------------

--[[
	Returns the `AnimSaves` container for `rig`, or nil.

	Search order (first hit wins):
	  1. A direct child of `rig` whose name matches `ContainerName`.
	  2. A descendant of `rig` whose name matches `ContainerName` (bounded by
	     the scan budget) - covers rigs where AnimSaves was moved into a
	     sub-folder such as `Rig.Animation.AnimSaves`.

	The returned instance may be a Model, an ObjectValue, a Folder or anything
	else - the caller treats them all identically.
]]
function RigScanner:FindContainer(rig: Instance): Instance?
	if not rig then
		return nil
	end

	local wanted = self._options.ContainerName:lower()

	-- Fast path: direct child.
	for _, child in ipairs(rig:GetChildren()) do
		if child.Name:lower() == wanted then
			return child
		end
	end

	-- Slow path: bounded breadth-first descent.
	self._budgetUsed = 0
	local queue: { Instance } = rig:GetChildren()
	local depth = 0
	while depth < 4 and #queue > 0 do
		local nextQueue = {}
		for _, node in ipairs(queue) do
			self._budgetUsed += 1
			if self._budgetUsed > self._options.ScanBudget then
				return nil
			end
			if node.Name:lower() == wanted then
				return node
			end
			for _, child in ipairs(node:GetChildren()) do
				table.insert(nextQueue, child)
			end
		end
		queue = nextQueue
		depth += 1
	end

	return nil
end

--[[
	Reads the optional `.Value` of an ObjectValue container.

	The documented layout stores the *parent's name* there, so this returns
	the alias string plus whether it matched the rig name. When `.Value` holds
	an Instance instead (a variant seen in some places), we return the instance's
	name and flag it so the caller knows a second scan target exists.
]]
function RigScanner:ReadContainerAlias(container: Instance, rig: Instance?): (string?, boolean, Instance?)
	if not container or not container:IsA("ObjectValue") then
		return nil, false, nil
	end

	local ok, value = pcall(function()
		return (container :: ObjectValue).Value
	end)
	if not ok then
		return nil, false, nil
	end

	if typeof(value) == "Instance" then
		return value.Name, rig ~= nil and value.Name == rig.Name, value
	elseif type(value) == "string" then
		return value, rig ~= nil and value == rig.Name, nil
	end

	return nil, false, nil
end

--------------------------------------------------------------------------------
-- Sequence collection
--------------------------------------------------------------------------------

--[[
	Collects every KeyframeSequence exposed by `container`.

	The unified rule: `container:GetChildren()` filtered by `IsA("KeyframeSequence")`.
	Model and ObjectValue take exactly the same path.

	If no direct KeyframeSequence children are found, and `MaxContainerDepth` > 1,
	the scanner descends into sub-containers (Folders/Models/ObjectValues) so that
	legacy layouts such as `AnimSaves/Locomotion/<sequences>` are still found. Each
	sequence is tagged with its sub-path for display.
]]
function RigScanner:CollectSequences(container: Instance): ({ Entry }, boolean)
	local entries: { Entry } = {}
	if not container then
		return entries, false
	end

	local maxDepth = math.max(1, math.floor(self._options.MaxContainerDepth))
	local truncated = false

	-- Pass 1 - the documented layout: direct children.
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("KeyframeSequence") then
			table.insert(entries, {
				sequence = child,
				name = child.Name,
				container = container,
				subPath = "",
				depth = 1,
			})
		end
	end

	if #entries > 0 or maxDepth <= 1 then
		return self:_sortEntries(entries), truncated
	end

	-- Pass 2 - bounded descent into sub-containers.
	local visited: { [Instance]: boolean } = { [container] = true }
	local frontier: { { container: Instance, path: string, depth: number } } = {
		{ container = container, path = "", depth = 1 },
	}

	while #frontier > 0 do
		local current = table.remove(frontier, 1)
		if current.depth >= maxDepth then
			continue
		end

		for _, child in ipairs(current.container:GetChildren()) do
			if visited[child] then
				continue
			end
			visited[child] = true
			self._budgetUsed += 1
			if self._budgetUsed > self._options.ScanBudget then
				truncated = true
				break
			end

			if child:IsA("KeyframeSequence") then
				local subPath = if current.path == "" then child.Name else current.path .. "/" .. child.Name
				table.insert(entries, {
					sequence = child,
					name = child.Name,
					container = current.container,
					subPath = subPath,
					depth = current.depth + 1,
				})
			elseif child:IsA("Folder") or child:IsA("Model") or child:IsA("ObjectValue") or child:IsA("Configuration") then
				local childPath = if current.path == "" then child.Name else current.path .. "/" .. child.Name
				table.insert(frontier, { container = child, path = childPath, depth = current.depth + 1 })
			end
		end

		if truncated then
			break
		end
	end

	return self:_sortEntries(entries), truncated
end

--[[
	Sorts entries by (name, subPath) so the UI, the cache and the upload order are
	all deterministic and independent of Roblox's child ordering.
]]
function RigScanner:_sortEntries(entries: { Entry }): { Entry }
	table.sort(entries, function(a, b)
		if a.name == b.name then
			return a.subPath < b.subPath
		end
		return a.name < b.name
	end)
	return entries
end

--------------------------------------------------------------------------------
-- Public scan entry point
--------------------------------------------------------------------------------

--[[
	Scans a single rig and returns a structured result.

	Never throws: every failure mode is reported through `result.error` so the
	UI can render it instead of the plugin silently doing nothing.
]]
function RigScanner:ScanRig(rig: Instance?): RigScanResult
	local result: RigScanResult = {
		rig = rig,
		rigName = if rig then rig.Name else nil,
		container = nil,
		containerClass = nil,
		containerAlias = nil,
		aliasMatchesRig = false,
		sequences = {},
		entries = {},
		truncated = false,
		error = nil,
	}

	if not rig then
		result.error = "No rig selected."
		return result
	end
	if not rig:IsA("Instance") then
		result.error = "Selection is not an Instance."
		return result
	end

	local container = self:FindContainer(rig)
	if not container then
		result.error = string.format("No '%s' container found inside '%s'.", self._options.ContainerName, rig:GetFullName())
		return result
	end

	result.container = container
	result.containerClass = container.ClassName

	local alias, matched, aliasInstance = self:ReadContainerAlias(container, rig)
	result.containerAlias = alias
	result.aliasMatchesRig = matched

	local entries, truncated = self:CollectSequences(container)
	result.entries = entries
	result.truncated = truncated

	for _, entry in ipairs(entries) do
		table.insert(result.sequences, entry.sequence)
	end

	-- Defensive: an ObjectValue whose .Value points at another container that
	-- also holds sequences (seen in a few community rigs). Only used when the
	-- direct children yielded nothing, so the unified rule above stays primary.
	if #result.sequences == 0 and aliasInstance then
		local extra, extraTruncated = self:CollectSequences(aliasInstance)
		for _, entry in ipairs(extra) do
			entry.subPath = "(ObjectValue.Value)/" .. entry.name
			table.insert(entries, entry)
			table.insert(result.sequences, entry.sequence)
		end
		result.entries = entries
		result.truncated = result.truncated or extraTruncated
		result.containerAlias = alias .. " (ObjectValue.Value)"
	end

	if #result.sequences == 0 then
		result.error = string.format(
			"'%s' (%s) contains no KeyframeSequence children.",
			container.Name,
			container.ClassName
		)
	end

	return result
end

--------------------------------------------------------------------------------
-- Rig discovery (no hardcoded paths)
--------------------------------------------------------------------------------

--[[
	Returns every instance under the configured service roots that owns an
	`AnimSaves` container holding at least one KeyframeSequence.

	Used to populate the UI's rig picker. Bounded by ScanBudget.
]]
function RigScanner:DiscoverRigs(): { Instance }
	local found: { Instance } = {}
	local seen: { [Instance]: boolean } = {}
	local wanted = self._options.ContainerName:lower()

	self._budgetUsed = 0

	for _, serviceName in ipairs(self._options.SearchRoots) do
		local ok, service = pcall(function()
			return game:GetService(serviceName)
		end)
		if ok and service then
			local queue: { Instance } = { service }
			while #queue > 0 do
				local node = table.remove(queue, 1) :: Instance
				self._budgetUsed += 1
				if self._budgetUsed > self._options.ScanBudget then
					return found
				end
				if not seen[node] then
					seen[node] = true
					if node ~= service and node.Name:lower() == wanted then
						-- Candidate container: check it actually has sequences.
						local entries = self:CollectSequences(node)
						if #entries > 0 then
							local rig = node.Parent
							if rig and not seen[rig] then
								table.insert(found, rig)
							end
						end
					end
					for _, child in ipairs(node:GetChildren()) do
						table.insert(queue, child)
					end
				end
			end
		end
	end

	-- Deterministic order for the UI.
	table.sort(found, function(a, b)
		return a:GetFullName() < b:GetFullName()
	end)

	return found
end

--------------------------------------------------------------------------------
-- Studio selection helpers
--------------------------------------------------------------------------------

--[[
	Returns the currently selected instance, or nil. Reads game.Selection so the
	UI can react to Studio's own selection changes.
]]
function RigScanner:GetSelectedRig(): Instance?
	local selected = Selection:Get()
	if #selected == 0 then
		return nil
	end
	return selected[1]
end

--[[
	Filters a Studio selection down to instances that actually contain an
	`AnimSaves` container. Used so clicking a random Part doesn't wipe the UI.
]]
function RigScanner:ResolveFromSelection(): Instance?
	local selected = Selection:Get()
	for _, instance in ipairs(selected) do
		local container = self:FindContainer(instance)
		if container then
			return instance
		end
	end
	return nil
end

return RigScanner
