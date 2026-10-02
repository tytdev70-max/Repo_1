--!strict

local Config: any = require(game:GetService("ReplicatedStorage").SPH_Assets.GameConfig)

--// State

local dead: boolean = false
local vehicleSeated: boolean = false

if Config.firstPersonBody then
	--// Services

	local RunService: RunService = game:GetService("RunService")

	--// Name Patterns

	local NamePatterns = table.freeze({
		Arm = "Arm",
		Leg = "Leg",
		Torso = "Torso",
		Foot = "Foot",
		Head = "Head",
		HolsterPrefix = "Holster_",
		WeaponRig = "WeaponRig",
	})

	local HandPartNames = table.freeze({ "Left Hand", "Right Hand" })

	--// Character References

	-- Walk up from the script rather than assuming a fixed folder depth.
	local function FindOwningCharacter(instance: Instance): Model?
		local current: Instance? = instance
		while current do
			if current:IsA("Model") and current:FindFirstChildOfClass("Humanoid") then
				return current
			end
			current = current.Parent
		end
		return nil
	end

	local Character = FindOwningCharacter(script) :: Model
	local humanoid = Character:WaitForChild("Humanoid") :: Humanoid

	local torso: BasePart
	if humanoid.RigType == Enum.HumanoidRigType.R6 then
		torso = Character:WaitForChild("Torso") :: BasePart
	else
		torso = Character:WaitForChild("UpperTorso") :: BasePart
	end

	local head = Character:WaitForChild("Head") :: BasePart

	--// State

	local gunEquipped: boolean = false

	humanoid.Seated:Connect(function(seated: boolean, seatPart: BasePart?)
		vehicleSeated = seated and seatPart ~= nil and seatPart:IsA("VehicleSeat")
	end)

	--// Helpers

	local function IsHeadDescendant(instance: Instance): boolean
		return instance:IsDescendantOf(head)
	end

	local function MakePartVisible(basePart: Instance?)
		if not basePart or not basePart:IsA("BasePart") then
			return
		end
		if IsHeadDescendant(basePart) then
			return
		end
		basePart.LocalTransparencyModifier = 0
	end

	local function CheckForBodyPartNames(model: Instance): Instance?
		for _, part in ipairs(model:GetChildren()) do
			local checkPart = Character:FindFirstChild(part.Name)
			if checkPart and checkPart:IsA("BasePart") then
				if not (string.find(checkPart.Name, NamePatterns.Arm) and gunEquipped) then
					return part
				end
			end
		end
		return nil
	end

	--// Render Loop

	local renderConn
	renderConn = RunService.RenderStepped:Connect(function(_: number)
		if (not Character:FindFirstChild("Torso") and not Character:FindFirstChild("UpperTorso")) or dead or vehicleSeated then
			return
		elseif head.LocalTransparencyModifier == 0 then
			return
		end

		local actualTool = Character:FindFirstChildWhichIsA("Tool")
		local isUnequipping: boolean = Character:GetAttribute("IsUnequippingForArmHiding") == true
		local isSwitchingWeapons: boolean = Character:GetAttribute("SwitchingWeapons") == true

		gunEquipped = actualTool ~= nil and actualTool:FindFirstChild("SPH_Weapon") ~= nil

		for _, obj in ipairs(Character:GetChildren()) do
			if obj:IsA("BasePart") then
				local isArm: boolean = string.find(obj.Name, NamePatterns.Arm) ~= nil
				local isBody: boolean = string.find(obj.Name, NamePatterns.Leg) ~= nil
					or string.find(obj.Name, NamePatterns.Torso) ~= nil
					or string.find(obj.Name, NamePatterns.Foot) ~= nil

				if isArm then
					local hasHiddenHolster: boolean = false
					for _, childObj in ipairs(Character:GetChildren()) do
						if string.sub(childObj.Name, 1, #NamePatterns.HolsterPrefix) == NamePatterns.HolsterPrefix
							and childObj:GetAttribute("HolsterHidden") == true then
							hasHiddenHolster = true
							break
						end
					end

					local transparency: number = (gunEquipped or isUnequipping or isSwitchingWeapons or hasHiddenHolster) and 1 or 0
					obj.LocalTransparencyModifier = transparency

					for _, desc in ipairs(obj:GetDescendants()) do
						if desc:IsA("BasePart") then
							desc.LocalTransparencyModifier = transparency
						elseif (desc:IsA("Texture") or desc:IsA("Decal")) and desc.Parent then
							(desc.Parent :: BasePart).LocalTransparencyModifier = transparency
						end
					end
				elseif isBody then
					MakePartVisible(obj)
				end

			elseif obj:IsA("Model") and obj:FindFirstChildWhichIsA("BasePart") then
				local middlePart: Instance? = obj:FindFirstChild("Middle") or obj:FindFirstChild("Grip") or CheckForBodyPartNames(obj)

				if middlePart and obj.Name ~= NamePatterns.WeaponRig then
					if string.find(obj.Name, NamePatterns.HolsterPrefix) and not Config.firstPersonHolsters then
						continue
					end

					local welds = (middlePart :: BasePart):GetJoints()
					local badMorph: boolean = false

					for _, cWeld in ipairs(welds) do
						local part0 = cWeld.Part0 :: BasePart
						local part1 = cWeld.Part1 :: BasePart

						if part0 == head or part1 == head then
							badMorph = true
							break
						elseif (string.find(part0.Name, NamePatterns.Arm) ~= nil or string.find(part1.Name, NamePatterns.Arm) ~= nil) and gunEquipped then
							badMorph = true
							break
						end
					end

					if badMorph then
						continue
					end

					for _, part in ipairs(obj:GetDescendants()) do
						if IsHeadDescendant(part) then
							continue
						end

						if part:IsA("BasePart") then
							MakePartVisible(part)
						elseif (part:IsA("Texture") or part:IsA("Decal")) and part.Parent and part.Parent:IsA("BasePart") then
							(part.Parent :: BasePart).LocalTransparencyModifier = 0
						end
					end

				elseif #obj:GetChildren() == 1 then
					local part = obj:FindFirstChildWhichIsA("BasePart")
					if part then
						local welds = part:GetJoints()
						local headMorph: boolean = false

						for _, cWeld in ipairs(welds) do
							if cWeld.Part0 == head or cWeld.Part1 == head then
								headMorph = true
								break
							end
						end

						if not headMorph and not IsHeadDescendant(part) then
							MakePartVisible(part)
							for _, child in ipairs(part:GetChildren()) do
								if (child:IsA("Texture") or child:IsA("Decal")) and child.Parent and child.Parent:IsA("BasePart") then
									(child.Parent :: BasePart).LocalTransparencyModifier = 0
								end
							end
						end
					end

				elseif obj:GetAttribute("FirstPersonVisible") then
					for _, childPart in ipairs(obj:GetChildren()) do
						if childPart:IsA("BasePart") and not IsHeadDescendant(childPart) then
							MakePartVisible(childPart)
						end
					end
				end

			elseif obj:IsA("Accessory") and Config.showAccessoriesFP then
				local part = obj:FindFirstChildWhichIsA("BasePart")
				if part then
					local attachedPart: BasePart? = nil
					local weld: Weld? = part:FindFirstChildWhichIsA("Weld") or (part:FindFirstChild("AccessoryWeld") :: Weld?)

					if weld and weld.Part1 then
						attachedPart = weld.Part1
					else
						local att = part:FindFirstChildWhichIsA("Attachment")
						if att and att.Name:match(NamePatterns.Head) then
							attachedPart = head
						end
					end

					local isArmAccessory: boolean = attachedPart ~= nil and (
						string.find(attachedPart.Name, NamePatterns.Arm) ~= nil
							or table.find(HandPartNames, attachedPart.Name) ~= nil
					)

					if isArmAccessory and (gunEquipped or Character:GetAttribute("HidingArmAccessories") == true) then
						part.LocalTransparencyModifier = 1
					elseif attachedPart and attachedPart.Name == NamePatterns.Head then
						part.LocalTransparencyModifier = 1
					elseif not IsHeadDescendant(part) then
						MakePartVisible(part)
					end
				end
			end
		end
	end)

	--// Death & Seat Tracking

	humanoid.Died:Connect(function()
		dead = true
		if renderConn then renderConn:Disconnect() end
	end)
end

return true