--!strict

local WeaponMath = {}

function WeaponMath.GetSineOffset(addition: number): number
	return math.sin(tick() * addition * 1.3) * 0.3
end

function WeaponMath.LerpNumber(value: number, target: number, speed: number): number
	return value + (target - value) * speed
end

function WeaponMath.ExpAlpha(ratePerSecond: number, dt: number): number
	return 1 - math.exp(-ratePerSecond * dt)
end

function WeaponMath.GetRotationBetween(u: Vector3, v: Vector3, axis: Vector3): CFrame
	local dot, uxv = u:Dot(v), u:Cross(v)
	if dot < -0.99999 then
		return CFrame.fromAxisAngle(axis, math.pi)
	end
	return CFrame.new(0, 0, 0, uxv.X, uxv.Y, uxv.Z, 1 + dot)
end

return WeaponMath