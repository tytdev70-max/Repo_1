--!strict

local WeaponContext = {}

export type Context = { [string]: any }

local context: Context = {}

function WeaponContext.get(): Context
	return context
end

function WeaponContext.set(values: Context)
	for key, value in pairs(values) do
		context[key] = value
	end
end

function WeaponContext.clear()
	for key in pairs(context) do
		context[key] = nil
	end
end

return WeaponContext