local players = game:GetService("Players")
local runService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local assets = game:GetService("ReplicatedStorage").SPH_Assets
local player = players.LocalPlayer

local realUI = script.Parent.MagUI
local fireModes = realUI.Firemodes
local Magazines = realUI.Magazines
local TotalMagCount = realUI.TotalMagCount
local WeaponName = realUI.WeaponName
local Caliber = realUI.Caliber

local character = nil
local humanoid = nil
local tool, magAmmo, ammoPool, wepStats
local dead = false
local lastMagKey = nil
local lastFillKey = nil

local connections = {}

local function disconnectAll()
	for _, c in ipairs(connections) do
		if c and c.Connected then c:Disconnect() end
	end
	table.clear(connections)
end

local function resetWeaponState()
	tool, magAmmo, ammoPool, wepStats = nil, nil, nil, nil
	lastMagKey, lastFillKey = nil, nil
	realUI.Visible = false
end

local function onChildAdded(newChild)
	if dead then return end
	if not character or not character.Parent then return end
	if not (newChild:FindFirstChild("SPH_Weapon") and assets.WeaponModels:FindFirstChild(newChild.Name)) then
		return
	end

	local stats = require(newChild.SPH_Weapon.WeaponStats)

	if stats.weaponType == "Grenade" then
		resetWeaponState()
		return
	end

	tool = newChild
	local ammoFolder = tool:WaitForChild("Ammo", 5)
	if not ammoFolder then resetWeaponState(); return end
	magAmmo  = ammoFolder:WaitForChild("MagAmmo", 5)
	ammoPool = ammoFolder:WaitForChild("ArcadeAmmoPool", 5)
	if not magAmmo or not ammoPool then resetWeaponState(); return end
	if not stats.openBolt then tool:WaitForChild("Chambered", 2) end

	wepStats = stats
	Caliber.Text = wepStats.ammoType
	lastMagKey, lastFillKey = nil, nil
end

local function onChildRemoved(oldChild)
	if oldChild == tool then
		resetWeaponState()
	end
end

local function bindCharacter(newCharacter)
	disconnectAll()
	resetWeaponState()
	dead = false

	character = newCharacter
	if not character then return end
	humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid then return end

	table.insert(connections, character.ChildAdded:Connect(onChildAdded))
	table.insert(connections, character.ChildRemoved:Connect(onChildRemoved))
	table.insert(connections, humanoid.Died:Connect(function()
		dead = true
		resetWeaponState()
	end))

	for _, child in ipairs(character:GetChildren()) do
		if child:IsA("Tool") then onChildAdded(child) end
	end
end

runService.Heartbeat:Connect(function()
	if dead or not character or not character.Parent then
		realUI.Visible = false
		return
	end
	if character:GetAttribute("SwitchingWeapons") then
		realUI.Visible = false
		return
	end

	local ubglActive = character:GetAttribute("UBGLActive")
	local ubglAmmo = (tool and wepStats and wepStats.UBGL and wepStats.UBGL.Enabled)
		and tool:FindFirstChild("UBGLAmmo")

	if ubglActive and ubglAmmo and not dead then
		realUI.Visible = true

		local capacity = wepStats.UBGL.Capacity or 1
		local loadedVal = ubglAmmo.Loaded.Value
		local poolVal = ubglAmmo.AmmoPool.Value
		local totalAmmo = loadedVal + poolVal
		local magCount = math.floor(poolVal / capacity)
		local remainder = poolVal % capacity

		WeaponName.Text = tool.Name .. " (UBGL)"
		Caliber.Text = wepStats.UBGL.AmmoType or wepStats.ammoType or ""

		for _, frame in pairs(fireModes:GetChildren()) do
			if frame:IsA("Frame") then
				frame.UIStroke.Enabled = false
				frame.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
			end
		end

		Magazines.Visible = true
		TotalMagCount.Text = tostring(magCount)

		local magKey = "ubgl:" .. tostring(tool) .. ":" .. magCount .. ":" .. remainder .. ":" .. capacity
		if magKey ~= lastMagKey then
			lastMagKey = magKey
			for _, child in ipairs(Magazines:GetChildren()) do
				if child.Name == "MagazineClone" then
					child:Destroy()
				end
			end

			local totalDisplayed = math.min(3, magCount + (remainder > 0 and 1 or 0))
			for i = 1, totalDisplayed do
				local baseMag = Magazines:FindFirstChild("Magazine")
				if baseMag then
					local clone = baseMag:Clone()
					clone.Name = "MagazineClone"
					clone.Parent = Magazines
					clone.Visible = true

					local fill = clone.Fill
					local fillPercent = 1
					if i == totalDisplayed and remainder > 0 then
						fillPercent = remainder / capacity
					end
					if magCount == 0 and remainder > 0 then
						fillPercent = remainder / capacity
					end
					fill.Size = UDim2.new(1, 0, fillPercent, 0)
					fill.Position = UDim2.new(0, 0, 1 - fillPercent, 0)
				end
			end
		end
		Magazines.Plus.Visible = magCount > 3

		local currentMag = Magazines:FindFirstChild("CurrentMagazine")
		if currentMag then
			currentMag.MagPlus.Visible = (loadedVal == capacity)

			if totalAmmo <= 0 then
				currentMag.Visible = false
			else
				currentMag.Visible = true
				local currentFill = math.clamp(loadedVal / capacity, 0, 1)
				local fill = currentMag.Fill
				local newSize = UDim2.new(1, 0, currentFill, 0)
				local newPos = UDim2.new(0, 0, 1 - currentFill, 0)

				local newColor
				if currentFill > 0.6 then
					newColor = Color3.fromRGB(255, 255, 255)
				elseif currentFill > 0.3 then
					newColor = Color3.fromRGB(255, 200, 140)
				else
					newColor = Color3.fromRGB(255, 80, 80)
				end

				local fillKey = "ubglfill:" .. loadedVal .. ":" .. capacity
				if fillKey ~= lastFillKey then
					lastFillKey = fillKey
					local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					TweenService:Create(fill, tweenInfo, {
						Size = newSize,
						Position = newPos,
						BackgroundColor3 = newColor
					}):Play()
				end
			end
		end

		return
	end

	if tool and wepStats and (tool:FindFirstChild("Chambered") or wepStats.openBolt) and magAmmo and not dead then
		realUI.Visible = true

		local maxPerMag = magAmmo.MaxValue
		local poolAmmo = ammoPool.Value
		local chambered = (tool:FindFirstChild("Chambered") and tool.Chambered.Value) and 1 or 0
		local totalAmmo = poolAmmo + magAmmo.Value + chambered
		local magCount = math.floor(poolAmmo / maxPerMag)
		local remainder = poolAmmo % maxPerMag

		WeaponName.Text = tool.Name
		Caliber.Text = wepStats.ammoType or ""
		if tool.FireMode.Value == 1 then fireModes.Semi.UIStroke.Enabled = true fireModes.Semi.BackgroundColor3 = Color3.fromRGB(255, 255, 255) fireModes.Auto.UIStroke.Enabled = false fireModes.Auto.BackgroundColor3 = Color3.fromRGB(0, 0, 0) fireModes.Burst.UIStroke.Enabled = false fireModes.Burst.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
		elseif tool.FireMode.Value == 2 then fireModes.Semi.UIStroke.Enabled = false fireModes.Semi.BackgroundColor3 = Color3.fromRGB(0, 0, 0) fireModes.Auto.UIStroke.Enabled = true fireModes.Auto.BackgroundColor3 = Color3.fromRGB(255, 255, 255) fireModes.Burst.UIStroke.Enabled = false fireModes.Burst.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
		elseif tool.FireMode.Value == 3 then fireModes.Semi.UIStroke.Enabled = false fireModes.Semi.BackgroundColor3 = Color3.fromRGB(0, 0, 0) fireModes.Auto.UIStroke.Enabled = false fireModes.Auto.BackgroundColor3 = Color3.fromRGB(0, 0, 0) fireModes.Burst.UIStroke.Enabled = true fireModes.Burst.BackgroundColor3 = Color3.fromRGB(255, 255, 255) 
		elseif tool.FireMode.Value == 4 then fireModes.Semi.UIStroke.Enabled = true fireModes.Semi.BackgroundColor3 = Color3.fromRGB(255, 255, 255) fireModes.Auto.UIStroke.Enabled = false fireModes.Auto.BackgroundColor3 = Color3.fromRGB(0, 0, 0) fireModes.Burst.UIStroke.Enabled = false fireModes.Burst.BackgroundColor3 = Color3.fromRGB(0, 0, 0) 
		elseif tool.FireMode.Value == 0 then fireModes.Semi.UIStroke.Enabled = true fireModes.Semi.BackgroundColor3 = Color3.fromRGB(85, 255, 127) fireModes.Auto.UIStroke.Enabled = true fireModes.Auto.BackgroundColor3 = Color3.fromRGB(85, 255, 127) fireModes.Burst.UIStroke.Enabled = true fireModes.Burst.BackgroundColor3 = Color3.fromRGB(85, 255, 127) end
		if wepStats.infiniteAmmo then
			TotalMagCount.Text = "+"
			Magazines.Visible = false
		else
			Magazines.Visible = true
			TotalMagCount.Text = tostring(magCount)

			local magKey = tostring(tool) .. ":" .. magCount .. ":" .. remainder .. ":" .. maxPerMag
			if magKey ~= lastMagKey then
				lastMagKey = magKey
				for _, child in ipairs(Magazines:GetChildren()) do
					if child.Name == "MagazineClone" then
						child:Destroy()
					end
				end

				local totalDisplayed = math.min(3, magCount + (remainder > 0 and 1 or 0))

				for i = 1, totalDisplayed do
					local baseMag = Magazines:FindFirstChild("Magazine")
					if baseMag then
						local clone = baseMag:Clone()
						clone.Name = "MagazineClone"
						clone.Parent = Magazines
						clone.Visible = true

						local fill = clone.Fill
						local fillPercent = 1

						if i == totalDisplayed and remainder > 0 then
							fillPercent = remainder / maxPerMag
						end

						if magCount == 0 and remainder > 0 then
							fillPercent = remainder / maxPerMag
						end

						fill.Size = UDim2.new(1, 0, fillPercent, 0)
						fill.Position = UDim2.new(0, 0, 1 - fillPercent, 0)
					end
				end
			end

			Magazines.Plus.Visible = magCount > 3

		end

		local currentMag = Magazines:FindFirstChild("CurrentMagazine")
		if magAmmo.Value == maxPerMag then
			currentMag.MagPlus.Visible = true
		else
			currentMag.MagPlus.Visible = false
		end
		if currentMag then
			if totalAmmo <= 0 then
				currentMag.Visible = false
			else
				currentMag.Visible = true

				local effectiveAmmo = magAmmo.Value + chambered
				local currentFill = math.clamp(effectiveAmmo / maxPerMag, 0, 1)

				local fill = currentMag.Fill
				local newSize = UDim2.new(1, 0, currentFill, 0)
				local newPos = UDim2.new(0, 0, 1 - currentFill, 0)

				local newColor
				if currentFill > 0.6 then
					newColor = Color3.fromRGB(255, 255, 255)
				elseif currentFill > 0.3 then
					newColor = Color3.fromRGB(255, 200, 140)
				else
					newColor = Color3.fromRGB(255, 80, 80)
				end

				local fillKey = "fill:" .. effectiveAmmo .. ":" .. maxPerMag
				if fillKey ~= lastFillKey then
					lastFillKey = fillKey
					local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
					TweenService:Create(fill, tweenInfo, {
						Size = newSize,
						Position = newPos,
						BackgroundColor3 = newColor
					}):Play()
				end
			end
		end

	else
		realUI.Visible = false
	end
end)

if player.Character then bindCharacter(player.Character) end
player.CharacterAdded:Connect(bindCharacter)

player.CharacterRemoving:Connect(function(oldCharacter)
	if oldCharacter == character then
		disconnectAll()
		resetWeaponState()
		dead = true
		character = nil
		humanoid = nil
	end
end)

script.Destroying:Connect(disconnectAll)