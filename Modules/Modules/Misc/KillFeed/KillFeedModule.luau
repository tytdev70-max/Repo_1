local module = {}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local Debris = game:GetService("Debris")

local SPH_Assets = ReplicatedStorage.SPH_Assets
local HUD = SPH_Assets.HUD
local KillFeedSounds = SPH_Assets.Sounds.KillFeed

local Config = {
	TemplateNames = {
		KillFeedUI = "KillFeedUI",
		Content = "Content",
		Entry = "Kill",
		Feed = "Feed",
		Sound = "KillSound",
	},

	DefaultVerb = "KILLED",

	Timing = {
		BrightnessFadeTime = 0.4,
		PostBrightnessDelay = 0.1,
		SkullFadeInTime = 0.5,
		PostSkullFadeDelay = 0.1,
		PreRevealHoldTime = 1,
		SlideAndExpandTime = 0.5,
		PostExpandDelay = 0.3,
		TypewriterCharDelay = 0.05,
		DisplayHoldTime = 4,
		PostCollapseDelay = 1,
		SkullFadeOutTime = 0.5,
		FinalDelay = 1,
	},

	Positions = {
		SkullRevealed = UDim2.new(0.1, 0, 0.5, 0),
		SkullHidden = UDim2.new(0.5, 0, 0.5, 0),
		InfoRevealed = UDim2.new(0.5, 0, 0.5, 0),
		InfoHidden = UDim2.new(-0.5, 0, 0.5, 0),
		FrameExpanded = UDim2.new(0, 5, 0, 5),
		FrameOutroBar = UDim2.new(0, 5, 0, 0),
		FrameCollapsed = UDim2.new(0, 0, 0, 0),
	},

	Easing = {
		Direction = Enum.EasingDirection.Out,
		Style = Enum.EasingStyle.Sine,
	},
}

local function RequireChild(Parent, ChildName, ContainerLabel)
	local Child = Parent and Parent:FindFirstChild(ChildName)
	if not Child then
		warn(("KillFeed: '%s' not found in %s"):format(ChildName, ContainerLabel))
	end
	return Child
end

local function GetKillFeedUI(PlayerGui)
	local KillFeedUI = PlayerGui:FindFirstChild(Config.TemplateNames.KillFeedUI)
	if KillFeedUI then
		return KillFeedUI
	end

	local Template = HUD.DeathUIs:FindFirstChild(Config.TemplateNames.KillFeedUI)
	if not Template then
		warn(("KillFeed: '%s' template not found under HUD.DeathUIs"):format(Config.TemplateNames.KillFeedUI))
		return nil
	end

	KillFeedUI = Template:Clone()
	KillFeedUI.Parent = PlayerGui
	return KillFeedUI
end

local EntryLookupCache = setmetatable({}, { __mode = "k" })

local function GetEntryTemplate(KillFeedUI)
	local Cached = EntryLookupCache[KillFeedUI]
	if Cached then
		return Cached.Template, Cached.Feed
	end

	local Content = RequireChild(KillFeedUI, Config.TemplateNames.Content, "KillFeedUI")
	if not Content then
		return nil
	end

	local Template = RequireChild(Content, Config.TemplateNames.Entry, "Content")
	if not Template then
		return nil
	end

	local Feed = RequireChild(KillFeedUI, Config.TemplateNames.Feed, "KillFeedUI")
	if not Feed then
		return nil
	end

	EntryLookupCache[KillFeedUI] = { Template = Template, Feed = Feed }
	return Template, Feed
end

local function CreateEntry(KillFeedUI)
	local Template, Feed = GetEntryTemplate(KillFeedUI)
	if not Template or not Feed then
		return nil
	end

	local Entry = Template:Clone()

	local Brightness = RequireChild(Entry, "Brightness", "Kill entry")
	local Skull = RequireChild(Entry, "Skull", "Kill entry")
	local Texts = RequireChild(Entry, "Texts", "Kill entry")
	if not (Brightness and Skull and Texts) then
		Entry:Destroy()
		return nil
	end

	local Information = RequireChild(Texts, "Information", "Texts")
	if not Information then
		Entry:Destroy()
		return nil
	end

	local Notification = RequireChild(Information, "Notf", "Information")
	local PlayerLabel = RequireChild(Information, "Plr", "Information")
	if not (Notification and PlayerLabel) then
		Entry:Destroy()
		return nil
	end

	local Frames = {}
	for Index = 1, 4 do
		local Frame = RequireChild(Notification, "Frame" .. Index, "Notf")
		if not Frame then
			Entry:Destroy()
			return nil
		end
		Frames[Index] = Frame
	end

	return {
		Root = Entry,
		Feed = Feed,
		Brightness = Brightness,
		Skull = Skull,
		Information = Information,
		Notification = Notification,
		PlayerLabel = PlayerLabel,
		Frames = Frames,
	}
end

local function PlayKillSound()
	local SoundTemplate = KillFeedSounds:FindFirstChild(Config.TemplateNames.Sound)
	if not SoundTemplate then
		warn(("KillFeed: '%s' not found under Sounds.KillFeed"):format(Config.TemplateNames.Sound))
		return
	end

	local KillSound = SoundTemplate:Clone()
	KillSound.Parent = SoundService
	KillSound:Play()
	Debris:AddItem(KillSound, KillSound.TimeLength > 0 and KillSound.TimeLength or 3)
end

local function Typewrite(Label, Text, IsAlive)
	for Index = 1, #Text do
		if not IsAlive() then
			return
		end
		Label.Text = string.sub(Text, 1, Index)
		task.wait(Config.Timing.TypewriterCharDelay)
	end
end

local function AnimateEntry(Entry, VictimName, Verb)
	local Timing = Config.Timing
	local Positions = Config.Positions
	local Direction = Config.Easing.Direction
	local Style = Config.Easing.Style

	local function IsAlive()
		return Entry.Root.Parent ~= nil
	end

	Entry.Root.Parent = Entry.Feed
	Entry.Root.Visible = true
	Entry.Root.LayoutOrder = -(#Entry.Feed:GetChildren() + 1)

	TweenService:Create(Entry.Brightness, TweenInfo.new(Timing.BrightnessFadeTime), { ImageTransparency = 1 }):Play()
	task.wait(Timing.PostBrightnessDelay)
	if not IsAlive() then
		return
	end

	TweenService:Create(Entry.Skull, TweenInfo.new(Timing.SkullFadeInTime), { ImageTransparency = 0 }):Play()
	task.wait(Timing.PostSkullFadeDelay)
	task.wait(Timing.PreRevealHoldTime)
	if not IsAlive() then
		return
	end

	Entry.Skull:TweenPosition(Positions.SkullRevealed, Direction, Style, Timing.SlideAndExpandTime)
	Entry.Information:TweenPosition(Positions.InfoRevealed, Direction, Style, Timing.SlideAndExpandTime)
	for _, Frame in Entry.Frames do
		Frame:TweenSize(Positions.FrameExpanded, Direction, Style, Timing.SlideAndExpandTime)
	end
	task.wait(Timing.PostExpandDelay)
	if not IsAlive() then
		return
	end

	Typewrite(Entry.Notification, Verb, IsAlive)
	if not IsAlive() then
		return
	end

	Typewrite(Entry.PlayerLabel, VictimName, IsAlive)
	if not IsAlive() then
		return
	end

	task.wait(Timing.DisplayHoldTime)
	if not IsAlive() then
		return
	end

	Entry.Skull:TweenPosition(Positions.SkullHidden, Direction, Style, Timing.SlideAndExpandTime)
	Entry.Information:TweenPosition(Positions.InfoHidden, Direction, Style, Timing.SlideAndExpandTime)
	Entry.Frames[1]:TweenSize(Positions.FrameCollapsed, Direction, Style, Timing.SlideAndExpandTime)
	Entry.Frames[2]:TweenSize(Positions.FrameOutroBar, Direction, Style, Timing.SlideAndExpandTime)
	Entry.Frames[3]:TweenSize(Positions.FrameCollapsed, Direction, Style, Timing.SlideAndExpandTime)
	Entry.Frames[4]:TweenSize(Positions.FrameCollapsed, Direction, Style, Timing.SlideAndExpandTime)
	task.wait(Timing.PostCollapseDelay)
	if not IsAlive() then
		return
	end

	TweenService:Create(Entry.Skull, TweenInfo.new(Timing.SkullFadeOutTime), { ImageTransparency = 1 }):Play()
	task.wait(Timing.FinalDelay)

	Entry.Root:Destroy()
end

function module.KillFeed(Player, Target, Verb)
	if not Player or not Target then
		warn("KillFeed: Invalid player or target")
		return
	end

	local PlayerGui = Player.PlayerGui
	if not PlayerGui then
		warn("KillFeed: PlayerGui not found")
		return
	end

	local KillFeedUI = GetKillFeedUI(PlayerGui)
	if not KillFeedUI then
		return
	end

	local Entry = CreateEntry(KillFeedUI)
	if not Entry then
		return
	end

	PlayKillSound()

	task.spawn(AnimateEntry, Entry, Target.Name, Verb or Config.DefaultVerb)
end

return module