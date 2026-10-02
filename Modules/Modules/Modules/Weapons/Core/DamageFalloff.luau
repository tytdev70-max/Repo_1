--!strict

local Assets = script:FindFirstAncestor("SPH_Assets")
local config = require(Assets.GameConfig)

export type FalloffConfig = {
	StartDistance: number?,
	EndDistance: number?,
	MinMultiplier: number?,
}

local DamageFalloff = {}

local MAX_DISTANCE: number = config.maxBulletDistance or 4000

function DamageFalloff.ResolveDistance(clientDistance: unknown, straightLineDistance: number): number
	local straight = if type(straightLineDistance) == "number" and straightLineDistance == straightLineDistance
		then math.max(straightLineDistance, 0)
		else 0

	local reported = 0
	if type(clientDistance) == "number" and clientDistance == clientDistance and clientDistance ~= math.huge then
		reported = math.max(clientDistance, 0)
	end

	return math.clamp(math.max(reported, straight), 0, MAX_DISTANCE)
end

function DamageFalloff.GetMultiplier(falloff: FalloffConfig?, distance: number): number
	if type(falloff) ~= "table" then
		return 1
	end

	local minMultiplier = math.clamp(falloff.MinMultiplier or 1, 0, 1)
	local startDistance = math.max(falloff.StartDistance or 0, 0)
	local endDistance = math.max(falloff.EndDistance or startDistance, startDistance)

	if distance <= startDistance then
		return 1
	elseif distance >= endDistance then
		return minMultiplier
	end

	local alpha = (distance - startDistance) / (endDistance - startDistance)
	return 1 + (minMultiplier - 1) * alpha
end

function DamageFalloff.Apply(damage: number, falloff: FalloffConfig?, distance: number): number
	if type(damage) ~= "number" or damage ~= damage then
		return 0
	end
	return math.max(damage * DamageFalloff.GetMultiplier(falloff, distance), 0)
end

return DamageFalloff