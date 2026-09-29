--// ChildModuleLoader.lua
--// Spawns child LocalScript modules that live as descendants of the
--// PlayerClient script.  Each entry maps a subfolder name to a module
--// name inside that folder.

local ChildModuleLoader = {}

--// Module manifest — mirrors the original CHILD_MODULES table exactly.
local CHILD_MODULES: { { folder: string, name: string } } = {
	{ folder = "FootstepHandler",   name = "Footsteps"        },
	{ folder = "ProxPromptHandler", name = "ProximityPrompt"  },
	{ folder = "LoadingScreen",     name = "LoadingHandler"   },
	{ folder = "LensFlareInit",     name = "LensFlare"        },
}

--// Public

--- `parentScript` should be the PlayerClient script instance (i.e. `script`
--- in Main.client.lua) so child folders are found via FindFirstChild.
function ChildModuleLoader.Init(parentScript: Instance): ()
	for _, entry: { folder: string, name: string } in ipairs(CHILD_MODULES) do
		local folder: Instance? = parentScript:FindFirstChild(entry.folder)
		local module: Instance? = folder and folder:FindFirstChild(entry.name)

		if module then
			task.spawn(function(): ()
				require(module)
			end)
		else
			warn(
				("[PlayerClient] Missing child module: %s.%s")
					:format(entry.folder, entry.name)
			)
		end
	end
end

return ChildModuleLoader