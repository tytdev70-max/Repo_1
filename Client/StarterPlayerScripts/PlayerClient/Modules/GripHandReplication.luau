--// GripHandReplication.lua
--// Handles Network packet GripHandReplicate: smoothly lerps an arm Motor6D
--// C0 toward a target CFrame each RenderStep, and restores the original
--// C0 when the grip is released.

local GripHandReplication = {}

local ServiceRefs  = require(script.Parent.ServiceRefs)
local RunService   = ServiceRefs.RunService
local player       : Player = ServiceRefs.player
local modules            = ServiceRefs.modules
local Network            = require(modules.Core.Networking.SPH_Network)

--// State

local gripHandTargets: {
	[any]: { target: CFrame, active: boolean }
} = {}

--// Private: Lerp Loop

local function StartLerpLoop(): ()
	RunService.RenderStepped:Connect(function(dt: number): ()
		if not next(gripHandTargets) then return end

		for armMotor: any, data: { target: CFrame, active: boolean } in pairs(gripHandTargets) do
			if not armMotor or not armMotor.Parent then
				gripHandTargets[armMotor] = nil
				continue
			end

			local alpha: number = math.clamp(dt * 8, 0, 0.3)
			armMotor.C0 = armMotor.C0:Lerp(data.target, alpha)

			if not data.active
				and (armMotor.C0.Position - data.target.Position).Magnitude < 0.005
			then
				armMotor.C0 = data.target
				gripHandTargets[armMotor] = nil
			end
		end
	end)
end

--// Public

function GripHandReplication.Init(): ()
	Network.packets.GripHandReplicate.listen(function(Data: any): ()
		local character : Model    = Data.Character
		local targetC0  : CFrame?  = Data.ArmC0
		local armName   : string   = Data.ArmName

		if not character or not character:FindFirstChild("WeaponRig") then return end
		if character == player.Character then return end

		local animBase: Instance? = character.WeaponRig:FindFirstChild("AnimBase")
		if not animBase then return end

		-- Resolve Motor6D by name or by connected part names
		local armMotor: Motor6D? = animBase:FindFirstChild(armName)

		if not armMotor or not armMotor:IsA("Motor6D") then
			for _, child: Instance in ipairs(animBase:GetChildren()) do
				if child:IsA("Motor6D") then
					local p0: Instance? = (child :: Motor6D).Part0
					local p1: Instance? = (child :: Motor6D).Part1
					if (p0 and p0.Name == armName)
						or (p1 and p1.Name == armName)
					then
						armMotor = child :: Motor6D
						break
					end
				end
			end
		end

		if not armMotor then return end

		if targetC0 then
			if not armMotor:GetAttribute("OriginalC0_Grip") then
				armMotor:SetAttribute("OriginalC0_Grip", armMotor.C0)
			end
			gripHandTargets[armMotor] = { target = targetC0, active = true }
		else
			local orig: CFrame? = armMotor:GetAttribute("OriginalC0_Grip")
			if orig then
				gripHandTargets[armMotor] = { target = orig, active = false }
				armMotor:SetAttribute("OriginalC0_Grip", nil)
			end
		end
	end)

	StartLerpLoop()
end

return GripHandReplication