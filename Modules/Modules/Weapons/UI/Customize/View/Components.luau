--!nonstrict
-- Customize/View/Components
-- Small UI building blocks shared by the default view. Theme values come from
-- config.theme (RGB arrays / font names) and are converted here.

local TweenService = game:GetService("TweenService")

local Components = {}

function Components.color(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

function Components.font(name: string): Enum.Font
	local ok, font = pcall(function()
		return (Enum.Font :: any)[name]
	end)
	return if ok and font then font else Enum.Font.GothamMedium
end

-- create("Frame", { Name = "X", Size = ... }, { children... })
function Components.create(className: string, props: { [string]: any }?, children: { Instance }?): Instance
	local instance = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			(instance :: any)[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

local create = Components.create

function Components.corner(parent: Instance, pixels: number)
	return create("UICorner", { CornerRadius = UDim.new(0, pixels), Parent = parent })
end

function Components.stroke(parent: Instance, color: Color3, thickness: number?, transparency: number?)
	return create("UIStroke", {
		Color = color,
		Thickness = thickness or 1,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Components.padding(parent: Instance, pixels: number)
	local p = UDim.new(0, pixels)
	return create("UIPadding", { PaddingTop = p, PaddingBottom = p, PaddingLeft = p, PaddingRight = p, Parent = parent })
end

-- Scaled text that never grows past `maxSize` pixels.
function Components.text(props: { [string]: any }, maxSize: number?): TextLabel
	local label = create(props.ClassName or "TextLabel", {
		Name = props.Name or "Label",
		BackgroundTransparency = 1,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Font = props.Font,
		Text = props.Text or "",
		TextColor3 = props.TextColor3,
		TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left,
		TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center,
		TextScaled = true,
		TextWrapped = props.TextWrapped == true,
		RichText = props.RichText == true,
		ZIndex = props.ZIndex or 1,
		Parent = props.Parent,
	}) :: any
	create("UITextSizeConstraint", { MaxTextSize = maxSize or 18, MinTextSize = 8, Parent = label })
	return label
end

function Components.tween(instance: Instance, time: number, goals: { [string]: any })
	local tween = TweenService:Create(instance, TweenInfo.new(time, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goals)
	tween:Play()
	return tween
end

-- Flat button: background colour reacts to hover; returns the TextButton.
function Components.button(props: { [string]: any }, theme: { [string]: any }): TextButton
	local base = props.BackgroundColor3 or Components.color(theme.card)
	local hover = props.HoverColor3 or Components.color(theme.hover)
	local button = create("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = base,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromScale(1, 1),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Text = "",
		ZIndex = props.ZIndex or 2,
		Parent = props.Parent,
	}) :: any
	Components.corner(button, theme.corner)
	if props.Text then
		Components.text({
			Name = "Text",
			Text = props.Text,
			Font = Components.font(props.Bold and theme.fontBold or theme.font),
			TextColor3 = props.TextColor3 or Components.color(theme.text),
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, -12, 1, -8),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			ZIndex = (props.ZIndex or 2) + 1,
			Parent = button,
		}, props.MaxTextSize or 18)
	end
	if props.Hover ~= false then
		button.MouseEnter:Connect(function()
			if button:GetAttribute("Locked") then
				return
			end
			Components.tween(button, theme.tweenTime, { BackgroundColor3 = hover })
		end)
		button.MouseLeave:Connect(function()
			if button:GetAttribute("Locked") then
				return
			end
			Components.tween(button, theme.tweenTime, { BackgroundColor3 = button:GetAttribute("BaseColor") or base })
		end)
	end
	button:SetAttribute("BaseColor", base)
	return button
end

return Components
