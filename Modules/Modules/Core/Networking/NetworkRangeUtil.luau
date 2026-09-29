local Players = game:GetService("Players")

local NetworkRangeUtil = {}

function NetworkRangeUtil.GetPlayersInRange(position: Vector3, range: number, exceptPlayer: Player?): { Player }
	local result = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr == exceptPlayer then
			continue
		end
		local char = plr.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if hrp and (hrp.Position - position).Magnitude <= range then
			table.insert(result, plr)
		end
	end
	return result
end

function NetworkRangeUtil.GetPlayersInRangeIncludingAll(position: Vector3, range: number): { Player }
	return NetworkRangeUtil.GetPlayersInRange(position, range, nil)
end

return NetworkRangeUtil