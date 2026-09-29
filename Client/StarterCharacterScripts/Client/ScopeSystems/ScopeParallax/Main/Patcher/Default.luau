local Method = {}
Method.aimpartZOffset = 0.5

local camera = workspace.CurrentCamera

function Method.autoDetectMethod(): string?
	return nil
end

function Method.modelDetectionPath(): Instance
	return camera
end

function Method.modelDetectionMethod(obj: Instance): Model?
	if obj:IsA("Model") then
		local gunModel = obj:FindFirstChildOfClass("Model")
		if gunModel then
			return gunModel
		end
	end

	return nil
end

function Method.parentingMethod(scopeFocusPart: Instance)
	scopeFocusPart.Parent = workspace
end

return Method