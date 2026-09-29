--[[
	MainPlugin.luau
	---------------
	Entry point of the AnimSaves Bulk Uploader Studio plugin.

	IMPORTANT: this file must be a **Script** instance (not a ModuleScript) and must
	be installed as a **LOCAL plugin**. In Studio, paste the folded build into a
	Script, right-click it -> "Save to File...", and drop the resulting .rbxmx
	into your local Plugins folder (see Plugin/INSTALL.md).
	`AssetService:CreateAssetAsync` is explicitly unavailable to plugins installed
	from the Creator Store, which is why the plugin is not published.

	Wiring
		MainPlugin owns the toolbar button and the plugin lifecycle. Everything else
		lives in Modules/:

			RigScanner          - unified AnimSaves locator + KeyframeSequence collector
			BinaryCacheService  - binary serialisation, dirty detection, skip-clean
			UploadService       - AssetService:CreateAssetAsync
			RegistrationService - UploadedAnimations folder + StringValues
			UIController        - the DockWidgetPluginGui

		No hardcoded rig paths anywhere: the rig comes from Studio's Selection (or
		the UI's picker) and is resolved by RigScanner.
]]

assert(plugin, "AnimSaves Bulk Uploader must run inside a Studio plugin.")

local Modules = script:WaitForChild("Modules")

local RigScanner = require(Modules:WaitForChild("RigScanner"))
local BinaryCacheService = require(Modules:WaitForChild("BinaryCacheService"))
local UploadService = require(Modules:WaitForChild("UploadService"))
local RegistrationService = require(Modules:WaitForChild("RegistrationService"))
local UIController = require(Modules:WaitForChild("UIController"))
local Util = require(Modules:WaitForChild("Util"))

local PLUGIN_NAME = "AnimSaves Bulk Uploader"
local TOOLBAR_NAME = "AnimSaves Uploader"
local BUTTON_ID = "AnimSavesBulkUploader_Toggle"

--------------------------------------------------------------------------------
-- Module instances
--------------------------------------------------------------------------------

local scanner = RigScanner.new({
	-- Rigs are discovered in these services, in this order. Workspace first
	-- because that is where the Animation Editor puts rigs.
	SearchRoots = { "Workspace", "ServerStorage", "ReplicatedStorage" },
	ScanBudget = 25000,
	MaxContainerDepth = 3,
})

local cache = BinaryCacheService.new({
	Backend = "Settings", -- or "StringValue"
	HashMode = "Deep", -- or "Fast"
	MaxEntries = 10000,
	MaxBlobBytes = 1048576,
	YieldEvery = 4000,
}):SetPlugin(plugin)

local uploader = UploadService.new({
	RequestsPerMinute = 20, -- the API is documented at ~30/min
	MaxRetries = 2,
	RetryDelaySeconds = 5,
	UploadMode = "Direct",
	CreatorType = Enum.AssetCreatorType.User,
	DescriptionTemplate = "Uploaded with the AnimSaves Bulk Uploader Studio plugin.",
})

local registration = RegistrationService.new({
	FolderName = "UploadedAnimations",
	ValueFormat = "Numeric",
	ReplaceMismatchedClasses = false,
	TagRig = true,
})

--------------------------------------------------------------------------------
-- Toolbar
--------------------------------------------------------------------------------

-- Forward declaration: the button's Click handler closes over `ui`, and Luau
-- resolves names lexically, so `ui` must already be a local here.
local ui: any = nil

local toolbar = plugin:CreateToolbar(TOOLBAR_NAME)

local button = toolbar:CreateButton(
	BUTTON_ID,
	"Open the AnimSaves Bulk Uploader",
	"", -- no custom icon; Studio falls back to the button text
	"ANIM"
)

button.Click:Connect(function()
	ui:Toggle()
	button:SetActive(ui:GetWidget() ~= nil and ui:GetWidget().Enabled)
end)

--------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------

-- Shared, mutable options bag. The options panel writes into it and the scan /
-- upload paths read from it.
local options = {
	backend = "Settings",
	hashMode = "Deep",
	creatorType = "User",
	groupId = nil,
	skipClean = false,
	autoReupload = false,
}

ui = UIController.new(plugin, {
	scanner = scanner,
	cache = cache,
	uploader = uploader,
	registration = registration,
	options = options,
	onRigChanged = function(rig: Instance)
		-- A new rig means a new cache scope and a new registration session.
		registration:ResetSession()
		print(string.format("[%s] Target rig: %s (%s)", PLUGIN_NAME, rig:GetFullName(), rig.ClassName))
	end,
})

local selectionConnection = ui:ConnectSelection()

--------------------------------------------------------------------------------
-- Startup
--------------------------------------------------------------------------------

local function onStartup()
	-- Encoding self-test: if base64 is somehow broken we fall back to hex.
	local base64Ok, hexOk = Util.selftestEncodings()
	if not base64Ok then
		warn(string.format("[%s] base64 self-test failed; the cache will use hex encoding.", PLUGIN_NAME))
	end
	if not base64Ok and not hexOk then
		warn(string.format("[%s] Both binary text encodings failed. The binary cache will be disabled.", PLUGIN_NAME))
	end

	-- Availability of the upload path.
	local available, reason = uploader:IsAvailable()
	if available then
		print(string.format("[%s] Ready. Upload path: AssetService:CreateAssetAsync (Animation).", PLUGIN_NAME))
	else
		warn(string.format("[%s] Upload path unavailable: %s", PLUGIN_NAME, reason))
	end

	if plugin:GetStudioUserId() == 0 then
		warn(string.format("[%s] You are not logged in to Studio - uploads will fail with PermissionDenied.", PLUGIN_NAME))
	end

	-- If a rig is already selected when the plugin loads, adopt it immediately.
	local initialRig = scanner:ResolveFromSelection()
	if initialRig then
		print(string.format("[%s] Adopting the currently selected rig: %s", PLUGIN_NAME, initialRig:GetFullName()))
		ui:SetRig(initialRig)
	else
		print(string.format("[%s] Select a rig that contains an AnimSaves container, then open the tool.", PLUGIN_NAME))
	end
end

task.spawn(onStartup)

--------------------------------------------------------------------------------
-- Teardown
--------------------------------------------------------------------------------

plugin.Unloading:Connect(function()
	selectionConnection:Disconnect()

	-- Persist the cache one last time so nothing is lost between Studio sessions.
	if cache:IsDirty() then
		if cache:Save() then
			print(string.format("[%s] Binary cache flushed on unload.", PLUGIN_NAME))
		else
			warn(string.format("[%s] Binary cache could not be flushed: %s", PLUGIN_NAME, tostring(cache:GetLastError())))
		end
	end

	ui:Destroy()
	print(string.format("[%s] Unloaded.", PLUGIN_NAME))
end)
