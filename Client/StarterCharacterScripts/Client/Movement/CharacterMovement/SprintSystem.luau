-- SprintSystem
-- ToggleSprint: fires viewmodel event and plays/stops sprint animation.

local Constants      = require(script.Parent.Constants)
local SharedState    = require(script.Parent.SharedState)
local AnimationSetup = require(script.Parent.AnimationSetup)

local toggleViewmodelSprint = SharedState.toggleViewmodelSprint
local sprintAnim            = AnimationSetup.sprintAnim
local moving                = nil  -- resolved via SharedState each call

local SPRINT_FADE_IN  = Constants.SPRINT_FADE_IN
local SPRINT_FADE_OUT = Constants.SPRINT_FADE_OUT

local SprintSystem = {}

function SprintSystem.ToggleSprint(toggle: boolean): ()
	toggleViewmodelSprint:Fire(toggle)
	if toggle then
		if SharedState.moving and not sprintAnim.IsPlaying then
			sprintAnim:Play(SPRINT_FADE_IN)
		end
	else
		if sprintAnim.IsPlaying then
			sprintAnim:Stop(SPRINT_FADE_OUT)
		end
	end
end

return SprintSystem