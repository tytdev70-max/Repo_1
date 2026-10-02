-- HolsterSystem
-- HolsterWeapon, CheckHolster, RemoveHolster, showHolsterRemote handler.

local ServiceRefs   = require(script.Parent.ServiceRefs)
local AssetRefs     = require(script.Parent.AssetRefs)
local ServerState   = require(script.Parent.ServerState)
local EventRefs     = require(script.Parent.EventRefs)

local replicatedStorage = ServiceRefs.replicatedStorage
local assets            = AssetRefs.assets
local weldMod           = AssetRefs.weldMod
local attachmentManager = AssetRefs.attachmentManager

local pendingHolsterShows = ServerState.pendingHolsterShows
local showHolsterRemote   = EventRefs.showHolsterRemote

local HolsterSystem = {}

local function getHiddenStore()
	local folder = replicatedStorage:FindFirstChild("_HolsterHidden")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name   = "_HolsterHidden"
		folder.Parent = replicatedStorage
	end
	return folder
end

local function isUnderScopeOrReticle(inst)
	if not inst or not inst.Parent then return false end
	if inst.Name == "SCOPE_FOCUS" or inst.Name == "SightReticle" then return true end
	if inst:FindFirstAncestor("SCOPE_FOCUS") or inst:FindFirstAncestor("SightReticle") then return true end
	return false
end

function HolsterSystem.HolsterWeapon(player, holsterPart, tool, holsterCFrame)
	local holsterModel
	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	if not assets.WeaponModels.HolsterModels:FindFirstChild(tool.Name) then
		holsterModel = assets.WeaponModels:FindFirstChild(tool.Name):Clone()
		holsterModel.Name = "Holster_" .. tool.Name
		weldMod.WeldModel(holsterModel, holsterModel.Grip)
		local holsterWeld  = weldMod.BlankWeld(holsterPart, holsterModel.Grip)
		holsterWeld.Name   = "HolsterWeld"
		holsterWeld.C0     = holsterCFrame
		holsterWeld.Parent = holsterModel
		holsterModel.Parent = player.Character
	else
		holsterModel = assets.WeaponModels.HolsterModels:FindFirstChild(tool.Name):Clone()
		holsterModel.Name = "Holster_" .. tool.Name
		weldMod.WeldModel(holsterModel, holsterModel.Middle)
		local holsterWeld  = weldMod.BlankWeld(holsterPart, holsterModel.Middle)
		holsterWeld.Name   = "HolsterWeld"
		holsterWeld.Parent = holsterModel
		holsterModel.Parent = player.Character
		holsterModel.Middle.Name = "Grip"
		holsterModel.Grip.Transparency = 1
	end

	attachmentManager.ClearAllAttachments(holsterModel)
	attachmentManager.PrepareForEquip(holsterModel)

	local savedAttachments = tool:FindFirstChild("SavedAttachments")
	if savedAttachments then
		for _, attachmentData in ipairs(savedAttachments:GetChildren()) do
			if attachmentData:IsA("StringValue") and attachmentData.Value ~= "" then
				local category       = attachmentData.Name
				local attachmentName = attachmentData.Value
				local success = attachmentManager.EquipAttachment(player, tool, holsterModel, attachmentName, category)
				if not success then
					warn("[Holster] Failed to apply attachment:", attachmentName, "->", category)
				end
			end
		end
	end

	local hiddenStore = getHiddenStore()

	for _, obj in ipairs(holsterModel:GetDescendants()) do
		if obj:IsA("ModuleScript") then continue end
		if isUnderScopeOrReticle(obj) then
			if obj:IsA("SurfaceGui") or obj:IsA("BillboardGui") then
				pcall(function() obj.Enabled = false end)
				pcall(function() obj.Parent  = hiddenStore end)
			elseif obj:IsA("GuiObject") then
				pcall(function() obj.Visible = false end)
				pcall(function() obj.Parent  = hiddenStore end)
			elseif obj:IsA("Decal") or obj:IsA("Texture") then
				pcall(function() obj.Parent = hiddenStore end)
			elseif obj:IsA("SurfaceAppearance") then
				pcall(function() obj.Parent = hiddenStore end)
			elseif obj.Name == "SCOPE_FOCUS" and obj:IsA("BasePart") then
				pcall(function()
					obj.Transparency  = 1
					obj.CanCollide    = false
					obj.CastShadow    = false
					obj.Parent        = hiddenStore
				end)
			elseif (obj:IsA("MeshPart") or obj:IsA("BasePart")) and isUnderScopeOrReticle(obj) then
				pcall(function()
					obj.Transparency  = 1
					obj.CanCollide    = false
					obj.CastShadow    = false
					obj.Parent        = hiddenStore
				end)
			else
				if not obj:IsA("ModuleScript") then
					pcall(function() obj.Parent = hiddenStore end)
				end
			end
		end
	end

	if tool:FindFirstChild("Chambered")
		and holsterModel
		and holsterModel:FindFirstChild(wepStats.projectile)
		and not tool.Chambered.Value then
		local projectile = holsterModel:FindFirstChild(wepStats.projectile)
		if projectile then
			if projectile:IsA("BasePart") then
				projectile.Transparency  = 1
				projectile.CanCollide    = false
				projectile.CastShadow    = false
			end
			if projectile.Parent ~= hiddenStore then
				pcall(function() projectile.Parent = hiddenStore end)
			end
		end
	end

	if tool:GetAttribute("HasBeenEquipped") then
		local pending = pendingHolsterShows[player]
		if pending and pending[tool.Name] then
			pending[tool.Name] = nil
		else
			for _, part in ipairs(holsterModel:GetDescendants()) do
				if part:IsA("BasePart") then
					part:SetAttribute("HolsterOriginalTransparency", part.Transparency)
					part.Transparency = 1
				end
			end
			holsterModel:SetAttribute("HolsterHidden", true)
		end
	end
end

function HolsterSystem.CheckHolster(player, tool)
	local wepStats = require(tool.SPH_Weapon.WeaponStats)
	if wepStats.holster then
		local holsterPart = player.Character:FindFirstChild(wepStats.holsterPart)
		if player.Character
			and not player.Character:FindFirstChild("Holster_" .. tool.Name)
			and not player.Character:FindFirstChild(tool.Name)
			and holsterPart then
			HolsterSystem.HolsterWeapon(player, holsterPart, tool, wepStats.holsterPosition)
		end
	end
end

function HolsterSystem.RemoveHolster(player, toolName)
	if player.Character then
		local holsterModel = player.Character:FindFirstChild("Holster_" .. toolName)
		if holsterModel and not player.Backpack:FindFirstChild(toolName) then
			holsterModel:Destroy()
		end
	end
end

function HolsterSystem.init()
	showHolsterRemote.OnServerEvent:Connect(function(player, toolName)
		if not player.Character then return end
		local holsterModel = player.Character:FindFirstChild("Holster_" .. tostring(toolName))
		if holsterModel and holsterModel:GetAttribute("HolsterHidden") then
			for _, part in ipairs(holsterModel:GetDescendants()) do
				if part:IsA("BasePart") then
					local orig = part:GetAttribute("HolsterOriginalTransparency")
					part.Transparency = (orig ~= nil) and orig or 0
				end
			end
			holsterModel:SetAttribute("HolsterHidden", false)
		else
			if not pendingHolsterShows[player] then
				pendingHolsterShows[player] = {}
			end
			pendingHolsterShows[player][tostring(toolName)] = true
		end
	end)
end

return HolsterSystem