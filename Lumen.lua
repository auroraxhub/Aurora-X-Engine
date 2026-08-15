--[[
    Lumen UI — a modern, mobile-first UI library for Roblox (Luau)
    Version 1.0.0

    Bundled build. The source lives in ./lumen — edit there and rebuild with:
        bun lumen/build.mjs

    Load it in an executor with:
        local Lumen = loadstring(game:HttpGet("RAW_URL_TO_THIS_FILE"))()

    License: MIT
]]

local Lumen = (function()
    local _modules = {}
    local function _require(name)
        local m = _modules[name]
        if m == nil then
            error("[Lumen] Module not found: " .. tostring(name), 2)
        end
        if not m.loaded then
            m.value = m.factory(_require)
            m.loaded = true
        end
        return m.value
    end
    local function _def(name, factory)
        _modules[name] = { factory = factory, loaded = false }
    end

    -- ==================== Components/Button ====================
    _def("Components/Button", function(require)
--[[
    Lumen UI — Components/Button
    Full-width control. Styles: default (surface), "Primary" (accent),
    "Danger" (danger). Hover/pressed/disabled are pure color derivations — no
    per-frame work, just recomputed on state changes.
]]

local Element = require("UI/Element")
local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")

local Button = setmetatable({}, { __index = Element })
Button.__index = Button

function Button.new(section, props)
    local self = setmetatable({}, Button)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window
    self.Name = props.Name or "Button"
    self.Style = props.Style or "default"
    self.Callback = props.Callback
    self.Disabled = false
    self._hover = false
    self._pressed = false

    local theme = Theme.Get()

    self.Instance = Utility.Create("TextButton", {
        Name = "Button",
        Text = self.Name,
        Font = Theme.Fonts.Bold,
        TextSize = Layout.FontSize.Element,
        BackgroundColor3 = theme.SurfaceAlt,
        TextColor3 = theme.Text,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, Layout.ElementHeight),
        Parent = section.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.ControlRadius), Parent = self.Instance })

    self:Connect(self.Instance.Activated, function()
        if not self.Disabled and self.Callback then
            self.Callback()
        end
    end)
    self:Connect(self.Instance.MouseEnter, function()
        self._hover = true
        self:_refreshState()
    end)
    self:Connect(self.Instance.MouseLeave, function()
        self._hover = false
        self:_refreshState()
    end)
    self:Connect(self.Instance.InputBegan, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            self._pressed = true
            self:_refreshState()
        end
    end)
    self:Connect(self.Instance.InputEnded, function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            self._pressed = false
            self:_refreshState()
        end
    end)

    self:SubscribeTheme()
    return self
end

function Button:_baseColor(theme)
    if self.Style == "Primary" then
        return theme.Accent
    elseif self.Style == "Danger" then
        return theme.Danger
    end
    return theme.SurfaceAlt
end

function Button:ApplyTheme(theme)
    Element.ApplyTheme(self, theme)
    self._theme = theme
    self:_refreshState()
end

function Button:_refreshState()
    if not self._theme or self.Destroyed then
        return
    end
    local theme = self._theme
    local color
    if self.Disabled then
        color = theme.SurfaceAlt
    elseif self._pressed then
        color = Utility.Darken(self:_baseColor(theme), theme.PressTint)
    elseif self._hover then
        color = Utility.Lighten(self:_baseColor(theme), theme.HoverTint)
    else
        color = self:_baseColor(theme)
    end

    self.Instance.BackgroundColor3 = color
    if self.Style == "Primary" and not self.Disabled then
        self.Instance.TextColor3 = theme.OnAccent
    elseif self.Disabled then
        self.Instance.TextColor3 = theme.Subtext
    else
        self.Instance.TextColor3 = theme.Text
    end
    self.Instance.TextTransparency = self.Disabled and 0.4 or 0
end

function Button:SetText(text)
    self.Name = text
    self.Instance.Text = text
end

function Button:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self:_refreshState()
end

function Button:Press()
    if not self.Disabled and self.Callback then
        self.Callback()
    end
end

return Button
    end)

    -- ==================== Components/ColorPicker ====================
    _def("Components/ColorPicker", function(require)
--[[
    Lumen UI — Components/ColorPicker
    Opens a modal with an HSV saturation/value pad, a hue slider and preset
    swatches. Uses native UIGradients for the color planes (no per-frame color
    math) and only recalculates on drag input.
]]

local Element = require("UI/Element")
local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")
local Overlay = require("UI/Overlay")

local ColorPicker = setmetatable({}, { __index = Element })
ColorPicker.__index = ColorPicker

local UserInputService = game:GetService("UserInputService")

local function toHex(color)
    return string.format("#%02X%02X%02X",
        math.floor(color.R * 255 + 0.5),
        math.floor(color.G * 255 + 0.5),
        math.floor(color.B * 255 + 0.5))
end

local RAINBOW = ColorSequence.new({
    ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
    ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
    ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
    ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
    ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
    ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
    ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
})

-- One-axis drag helper. The single global InputEnded is registered with
-- ui.Track so it is cleaned up when the overlay closes.
local function bindDrag(track, frame, handler)
    local dragging = false
    frame.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            handler(input.Position)
        end
    end)
    frame.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch) then
            handler(input.Position)
        end
    end)
    frame.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
    track(UserInputService.InputEnded:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
        end
    end))
end

function ColorPicker.new(section, props)
    local self = setmetatable({}, ColorPicker)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window
    self.Name = props.Name or "ColorPicker"
    self.Value = props.Default or Color3.fromRGB(255, 255, 255)
    self.Callback = props.Callback
    self.Disabled = false

    local h, s, v = self.Value:ToHSV()
    self.Hue = h
    self.Sat = s
    self.Val = v

    local theme = Theme.Get()

    self.Instance = Utility.Create("TextButton", {
        Name = "ColorPicker",
        Text = "",
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, Layout.ElementHeight),
        Parent = section.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.ControlRadius), Parent = self.Instance })

    self.Swatch = Utility.Create("Frame", {
        Name = "Swatch",
        Active = false,
        BackgroundColor3 = self.Value,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(22, 22),
        Parent = self.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = self.Swatch })
    Utility.Create("UIStroke", { Color = theme.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = self.Swatch })

    self.NameLabel = Utility.Create("TextLabel", {
        Name = "Name",
        Text = self.Name,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Element,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 44, 0, 0),
        Size = UDim2.new(0.5, 0, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Instance,
    })
    self.ValueLabel = Utility.Create("TextLabel", {
        Name = "Value",
        Text = toHex(self.Value),
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Value,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.new(0.5, 0, 0, 0),
        Size = UDim2.new(1, -52, 1, 0),
        Parent = self.Instance,
    })

    self:Connect(self.Instance.Activated, function()
        if not self.Disabled then
            self:Open()
        end
    end)

    self:SubscribeTheme()
    return self
end

function ColorPicker:ApplyTheme(theme)
    Element.ApplyTheme(self, theme)
    self._theme = theme
    self.Instance.BackgroundColor3 = theme.SurfaceAlt
    self.NameLabel.TextColor3 = theme.Text
    self.ValueLabel.TextColor3 = theme.Subtext
    self.Swatch.UIStroke.Color = theme.Border
end

function ColorPicker:Open()
    local selfRef = self
    self.Overlay = Overlay.Open({
        Title = self.Name,
        Height = 340,
        Scrollable = false,
        Build = function(ui)
            local theme = Theme.Get()

            -- Preview row
            local preview = Utility.Create("Frame", {
                Name = "Preview",
                BackgroundColor3 = theme.SurfaceAlt,
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 46),
                LayoutOrder = 0,
                Parent = ui.Content,
            })
            Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = preview })
            local previewSwatch = Utility.Create("Frame", {
                Name = "Swatch",
                BackgroundColor3 = selfRef.Value,
                BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0, 0.5),
                Position = UDim2.new(0, 10, 0.5, 0),
                Size = UDim2.fromOffset(30, 30),
                Parent = preview,
            })
            Utility.Create("UICorner", { CornerRadius = UDim.new(0, 6), Parent = previewSwatch })
            local hexLabel = Utility.Create("TextLabel", {
                Text = toHex(selfRef.Value),
                Font = Theme.Fonts.Bold,
                TextSize = 14,
                TextColor3 = theme.Text,
                BackgroundTransparency = 1,
                TextXAlignment = Enum.TextXAlignment.Left,
                Position = UDim2.new(0, 52, 0, 0),
                Size = UDim2.new(1, -60, 1, 0),
                Parent = preview,
            })
            selfRef.PreviewSwatch = previewSwatch
            selfRef.HexLabel = hexLabel

            -- SV pad
            local pad = Utility.Create("Frame", {
                Name = "SV",
                Active = true,
                BackgroundColor3 = Color3.fromHSV(selfRef.Hue, 1, 1),
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 150),
                LayoutOrder = 1,
                Parent = ui.Content,
            })
            Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = pad })
            Utility.Create("UIGradient", {
                Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)),
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0),
                    NumberSequenceKeypoint.new(1, 1),
                }),
                Rotation = 0,
                Parent = pad,
            })
            Utility.Create("UIGradient", {
                Color = ColorSequence.new(Color3.fromRGB(0, 0, 0)),
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 1),
                    NumberSequenceKeypoint.new(1, 0),
                }),
                Rotation = 90,
                Parent = pad,
            })
            local cursor = Utility.Create("Frame", {
                Name = "Cursor",
                Active = false,
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0, 0),
                Size = UDim2.fromOffset(14, 14),
                ZIndex = 3,
                Parent = pad,
            })
            Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = cursor })
            Utility.Create("UIStroke", { Color = theme.ToggleKnob, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = cursor })

            -- Hue slider
            local hueTrack = Utility.Create("Frame", {
                Name = "Hue",
                Active = true,
                BackgroundColor3 = Color3.fromRGB(255, 255, 255),
                BorderSizePixel = 0,
                Size = UDim2.new(1, 0, 0, 20),
                LayoutOrder = 2,
                Parent = ui.Content,
            })
            Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = hueTrack })
            Utility.Create("UIGradient", { Color = RAINBOW, Rotation = 0, Parent = hueTrack })
            local hueThumb = Utility.Create("Frame", {
                Name = "HueThumb",
                Active = false,
                BackgroundColor3 = theme.ToggleKnob,
                BorderSizePixel = 0,
                AnchorPoint = Vector2.new(0, 0.5),
                Size = UDim2.fromOffset(14, 20),
                ZIndex = 3,
                Parent = hueTrack,
            })
            Utility.Create("UICorner", { CornerRadius = UDim.new(0, 4), Parent = hueThumb })

            -- Presets
            local presets = Utility.Create("Frame", {
                Name = "Presets",
                BackgroundTransparency = 1,
                Size = UDim2.new(1, 0, 0, 28),
                LayoutOrder = 3,
                Parent = ui.Content,
            })
            local presetList = Utility.Create("UIListLayout", {
                SortOrder = Enum.SortOrder.LayoutOrder,
                FillDirection = Enum.FillDirection.Horizontal,
                Padding = UDim.new(0, 8),
                Parent = presets,
            })
            local presetColors = {
                theme.Accent, theme.Success, theme.Warning, theme.Danger, theme.Info,
                Color3.fromRGB(255, 255, 255), Color3.fromRGB(0, 0, 0),
            }
            for i = 1, #presetColors do
                local swatch = Utility.Create("TextButton", {
                    Name = "Preset",
                    Text = "",
                    BackgroundColor3 = presetColors[i],
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Size = UDim2.fromOffset(28, 28),
                    LayoutOrder = i,
                    Parent = presets,
                })
                Utility.Create("UICorner", { CornerRadius = UDim.new(0, 7), Parent = swatch })
                Utility.Create("UIStroke", { Color = theme.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = swatch })
                swatch.Activated:Connect(function()
                    local ph, ps, pv = presetColors[i]:ToHSV()
                    selfRef:SetHSV(ph, ps, pv, true)
                end)
            end

            selfRef.Pad = pad
            selfRef.Cursor = cursor
            selfRef.HueThumb = hueThumb

            bindDrag(ui.Track, pad, function(absPos)
                local abs = pad.AbsolutePosition
                local size = pad.AbsoluteSize
                if size.X <= 0 or size.Y <= 0 then
                    return
                end
                local s = Utility.Clamp((absPos.X - abs.X) / size.X, 0, 1)
                local v = Utility.Clamp(1 - (absPos.Y - abs.Y) / size.Y, 0, 1)
                selfRef:SetHSV(selfRef.Hue, s, v, true)
            end)
            bindDrag(ui.Track, hueTrack, function(absPos)
                local abs = hueTrack.AbsolutePosition
                local size = hueTrack.AbsoluteSize
                if size.X <= 0 then
                    return
                end
                local h = Utility.Clamp((absPos.X - abs.X) / size.X, 0, 1)
                selfRef:SetHSV(h, selfRef.Sat, selfRef.Val, true)
            end)

            -- Position the cursor/thumb at the current values
            selfRef:_syncControls()
        end,
    })
end

function ColorPicker:SetHSV(h, s, v, fireCallback)
    self.Hue = Utility.Clamp(h, 0, 1)
    self.Sat = Utility.Clamp(s, 0, 1)
    self.Val = Utility.Clamp(v, 0, 1)
    self.Value = Color3.fromHSV(self.Hue, self.Sat, self.Val)
    self.Swatch.BackgroundColor3 = self.Value
    self.ValueLabel.Text = toHex(self.Value)
    self:_syncControls()
    if fireCallback and self.Callback then
        self.Callback(self.Value)
    end
end

function ColorPicker:_syncControls()
    if not self.Pad or self.Destroyed then
        return
    end
    self.Pad.BackgroundColor3 = Color3.fromHSV(self.Hue, 1, 1)
    self.Cursor.Position = UDim2.new(self.Sat, -7, 1 - self.Val, -7)
    self.HueThumb.Position = UDim2.new(self.Hue, -7, 0.5, 0)
    if self.PreviewSwatch then
        self.PreviewSwatch.BackgroundColor3 = self.Value
    end
    if self.HexLabel then
        self.HexLabel.Text = toHex(self.Value)
    end
end

function ColorPicker:Set(color, fireCallback)
    local h, s, v = color:ToHSV()
    self:SetHSV(h, s, v, fireCallback)
end

function ColorPicker:Get()
    return self.Value
end

function ColorPicker:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self.Instance.GroupTransparency = self.Disabled and 0.4 or 0
end

function ColorPicker:Destroy()
    if self.Overlay then
        self.Overlay:Close()
        self.Overlay = nil
    end
    Element.Destroy(self)
end

return ColorPicker
    end)

    -- ==================== Components/Divider ====================
    _def("Components/Divider", function(require)
--[[ Lumen UI — Components/Divider: horizontal rule, optionally with centered text ]]
local Element = require("UI/Element")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")

local Divider = setmetatable({}, { __index = Element })
Divider.__index = Divider

function Divider.new(section, props)
    local self = setmetatable({}, Divider)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window

    local theme = Theme.Get()
    local text = props.Text or ""

    self.Instance = Utility.Create("Frame", {
        Name = "Divider",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, text ~= "" and 18 or 10),
        Parent = section.Instance,
    })

    self.Line = Utility.Create("Frame", {
        Name = "Line",
        BackgroundColor3 = theme.Border,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.new(0.5, 0, 0.5, 0),
        Size = UDim2.new(1, 0, 0, 1),
        Parent = self.Instance,
    })

    if text ~= "" then
        local label = Utility.Create("TextLabel", {
            Name = "Text",
            Text = text,
            Font = Theme.Fonts.Bold,
            TextSize = Layout.FontSize.Small,
            TextColor3 = theme.Subtext,
            BackgroundColor3 = theme.Surface,
            BackgroundTransparency = 0,
            BorderSizePixel = 0,
            AnchorPoint = Vector2.new(0.5, 0.5),
            Position = UDim2.new(0.5, 0, 0.5, 0),
            Size = UDim2.new(0, Utility.TextWidth(text, Theme.Fonts.Bold, Layout.FontSize.Small) + 18, 0, 18),
            ZIndex = 2,
            Parent = self.Instance,
        })
        self.Label = label
        self:BindColor(label, "TextColor3", "Subtext")
        self:BindColor(label, "BackgroundColor3", "Surface")
    end

    self:BindColor(self.Line, "BackgroundColor3", "Border")
    self:SubscribeTheme()
    return self
end

function Divider:Set(text)
    if self.Label then
        self.Label.Text = text
    end
end

return Divider
    end)

    -- ==================== Components/Dropdown ====================
    _def("Components/Dropdown", function(require)
--[[
    Lumen UI — Components/Dropdown
    Single-select. Opens a centered modal picker with large touch-friendly
    option rows; tapping outside closes it.
]]

local Element = require("UI/Element")
local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")
local Overlay = require("UI/Overlay")

local Dropdown = setmetatable({}, { __index = Element })
Dropdown.__index = Dropdown

function Dropdown.new(section, props)
    local self = setmetatable({}, Dropdown)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window
    self.Name = props.Name or "Dropdown"
    self.Options = props.Options or {}
    self.Value = props.Default or (self.Options[1] or "")
    self.Callback = props.Callback
    self.Disabled = false

    local theme = Theme.Get()

    self.Instance = Utility.Create("TextButton", {
        Name = "Dropdown",
        Text = "",
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, Layout.ElementHeight),
        Parent = section.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.ControlRadius), Parent = self.Instance })

    self.NameLabel = Utility.Create("TextLabel", {
        Name = "Name",
        Text = self.Name,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Element,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.55, 0, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Instance,
    })
    self.ValueLabel = Utility.Create("TextLabel", {
        Name = "Value",
        Text = tostring(self.Value),
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Value,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.new(0.55, 0, 0, 0),
        Size = UDim2.new(1, -44, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Instance,
    })
    self.Arrow = Utility.Create("TextLabel", {
        Name = "Arrow",
        Text = "▾",
        Font = Theme.Fonts.Medium,
        TextSize = 13,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        Active = false,
        Position = UDim2.new(1, -30, 0, 0),
        Size = UDim2.fromOffset(20, Layout.ElementHeight),
        Parent = self.Instance,
    })

    self:Connect(self.Instance.Activated, function()
        if not self.Disabled then
            self:Open()
        end
    end)

    self:SubscribeTheme()
    return self
end

function Dropdown:ApplyTheme(theme)
    Element.ApplyTheme(self, theme)
    self._theme = theme
    self.Instance.BackgroundColor3 = theme.SurfaceAlt
    self.NameLabel.TextColor3 = theme.Text
    self.ValueLabel.TextColor3 = theme.Subtext
    self.Arrow.TextColor3 = theme.Subtext
end

function Dropdown:Open()
    local selfRef = self
    self.Overlay = Overlay.Open({
        Title = self.Name,
        Height = math.min(360, 44 + #self.Options * 44),
        Build = function(ui)
            local theme = Theme.Get()
            for i = 1, #selfRef.Options do
                local option = selfRef.Options[i]
                local btn = Utility.Create("TextButton", {
                    Name = "Option",
                    Text = tostring(option),
                    Font = Theme.Fonts.Medium,
                    TextSize = Layout.FontSize.Element,
                    TextColor3 = option == selfRef.Value and theme.Accent or theme.Text,
                    BackgroundColor3 = theme.SurfaceAlt,
                    BackgroundTransparency = 0,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Size = UDim2.new(1, 0, 0, 40),
                    LayoutOrder = i,
                    Parent = ui.Content,
                })
                Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = btn })
                btn.Activated:Connect(function()
                    selfRef:Set(option, true)
                    if selfRef.Overlay then
                        selfRef.Overlay:Close()
                    end
                end)
            end
        end,
    })
end

function Dropdown:Set(value, fireCallback)
    self.Value = value
    self.ValueLabel.Text = tostring(value)
    if fireCallback and self.Callback then
        self.Callback(value)
    end
end

function Dropdown:Get()
    return self.Value
end

function Dropdown:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self.Instance.GroupTransparency = self.Disabled and 0.4 or 0
end

function Dropdown:Destroy()
    if self.Overlay then
        self.Overlay:Close()
        self.Overlay = nil
    end
    Element.Destroy(self)
end

return Dropdown
    end)

    -- ==================== Components/Keybind ====================
    _def("Components/Keybind", function(require)
--[[
    Lumen UI — Components/Keybind
    Tap to rebind: the next key (or mouse button, if allowed) becomes the new
    binding; Escape cancels. A single event-driven UIS.InputBegan connection per
    keybind handles both triggering and capture — no polling.
]]

local Element = require("UI/Element")
local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")

local Keybind = setmetatable({}, { __index = Element })
Keybind.__index = Keybind

Keybind._activeBinder = nil

local UserInputService = game:GetService("UserInputService")

local function normalize(value)
    if value == nil then
        return "None"
    end
    if typeof(value) == "EnumItem" then
        return value
    end
    if type(value) == "string" then
        local keyCode = Enum.KeyCode[value]
        if keyCode then
            return keyCode
        end
        if value == "MB1" or value == "MB2" or value == "MB3" then
            return value
        end
    end
    return "None"
end

local function displayName(value)
    if value == "None" then
        return "None"
    end
    if type(value) == "string" then
        return value
    end
    return value.Name
end

local function matches(value, input)
    if value == "None" or value == nil then
        return false
    end
    if typeof(value) == "EnumItem" then
        return input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode == value
    end
    if value == "MB1" then
        return input.UserInputType == Enum.UserInputType.MouseButton1
    elseif value == "MB2" then
        return input.UserInputType == Enum.UserInputType.MouseButton2
    elseif value == "MB3" then
        return input.UserInputType == Enum.UserInputType.MouseButton3
    end
    return false
end

function Keybind.new(section, props)
    local self = setmetatable({}, Keybind)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window
    self.Name = props.Name or "Keybind"
    self.Value = normalize(props.Default)
    self.AllowMouse = props.AllowMouse ~= false
    self.Callback = props.Callback
    self.Disabled = false
    self.Binding = false
    self.LastFire = 0

    local theme = Theme.Get()

    self.Instance = Utility.Create("TextButton", {
        Name = "Keybind",
        Text = "",
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, Layout.ElementHeight),
        Parent = section.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.ControlRadius), Parent = self.Instance })

    self.NameLabel = Utility.Create("TextLabel", {
        Name = "Name",
        Text = self.Name,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Element,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -90, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Instance,
    })

    self.KeyPill = Utility.Create("Frame", {
        Name = "KeyPill",
        Active = false,
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(70, 26),
        Parent = self.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, 7), Parent = self.KeyPill })
    self.KeyLabel = Utility.Create("TextLabel", {
        Name = "Key",
        Text = displayName(self.Value),
        Font = Theme.Fonts.Bold,
        TextSize = Layout.FontSize.Value,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        Active = false,
        Size = UDim2.fromScale(1, 1),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.KeyPill,
    })

    self:Connect(self.Instance.Activated, function()
        if not self.Disabled then
            self:BeginBind()
        end
    end)

    self:Connect(UserInputService.InputBegan, function(input, gameProcessedEvent)
        if gameProcessedEvent then
            return
        end
        if self.Binding then
            self:Capture(input)
        elseif not self.Disabled and matches(self.Value, input) then
            local now = tick()
            if now - self.LastFire >= Config.KeybindDelay then
                self.LastFire = now
                if self.Callback then
                    self.Callback()
                end
            end
        end
    end)

    self:SubscribeTheme()
    return self
end

function Keybind:ApplyTheme(theme)
    Element.ApplyTheme(self, theme)
    self._theme = theme
    self.Instance.BackgroundColor3 = theme.SurfaceAlt
    self.NameLabel.TextColor3 = theme.Text
    self.KeyPill.BackgroundColor3 = theme.Surface
    if not self.Binding then
        self.KeyLabel.TextColor3 = theme.Subtext
    end
end

function Keybind:_refresh()
    if self.Binding then
        self.KeyLabel.Text = "..."
        self.KeyLabel.TextColor3 = Theme.Get().Accent
    else
        self.KeyLabel.Text = displayName(self.Value)
        self.KeyLabel.TextColor3 = Theme.Get().Subtext
    end
end

function Keybind:BeginBind()
    if Keybind._activeBinder and Keybind._activeBinder ~= self and not Keybind._activeBinder.Destroyed then
        Keybind._activeBinder.Binding = false
        Keybind._activeBinder:_refresh()
    end
    Keybind._activeBinder = self
    self.Binding = true
    self:_refresh()
end

function Keybind:Capture(input)
    if input.UserInputType == Enum.UserInputType.Keyboard then
        if input.KeyCode == Enum.KeyCode.Escape then
            self.Binding = false
            self:_refresh()
            return
        end
        self.Value = input.KeyCode
        self.Binding = false
        self:_refresh()
    elseif self.AllowMouse then
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            self.Value = "MB1"
        elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
            self.Value = "MB2"
        elseif input.UserInputType == Enum.UserInputType.MouseButton3 then
            self.Value = "MB3"
        else
            return
        end
        self.Binding = false
        self:_refresh()
    end
end

function Keybind:Set(value)
    self.Value = normalize(value)
    self.Binding = false
    self:_refresh()
end

function Keybind:Get()
    return self.Value
end

function Keybind:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self.Instance.GroupTransparency = self.Disabled and 0.4 or 0
end

return Keybind
    end)

    -- ==================== Components/Label ====================
    _def("Components/Label", function(require)
--[[ Lumen UI — Components/Label: single-line text ]]
local Element = require("UI/Element")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")

local Label = setmetatable({}, { __index = Element })
Label.__index = Label

function Label.new(section, props)
    local self = setmetatable({}, Label)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window

    local theme = Theme.Get()

    self.Instance = Utility.Create("TextLabel", {
        Name = "Label",
        Text = props.Text or "",
        Font = props.Emphasis and Theme.Fonts.Bold or Theme.Fonts.Medium,
        TextSize = props.Size or Layout.FontSize.Element,
        TextColor3 = props.Color or theme.Text,
        BackgroundTransparency = 1,
        TextXAlignment = props.Alignment or Enum.TextXAlignment.Left,
        TextWrapped = true,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = section.Instance,
    })

    if not props.Color then
        self:BindColor(self.Instance, "TextColor3", "Text")
    end

    self:SubscribeTheme()
    return self
end

function Label:Set(text)
    self.Instance.Text = text
end

function Label:SetColor(color)
    self.Instance.TextColor3 = color
end

return Label
    end)

    -- ==================== Components/MultiDropdown ====================
    _def("Components/MultiDropdown", function(require)
--[[
    Lumen UI — Components/MultiDropdown
    Multi-select with check rows and a Done/Clear footer.
]]

local Element = require("UI/Element")
local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")
local Overlay = require("UI/Overlay")

local MultiDropdown = setmetatable({}, { __index = Element })
MultiDropdown.__index = MultiDropdown

function MultiDropdown.new(section, props)
    local self = setmetatable({}, MultiDropdown)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window
    self.Name = props.Name or "MultiDropdown"
    self.Options = props.Options or {}
    self.Value = {}
    if type(props.Default) == "table" then
        for i = 1, #props.Default do
            self.Value[#self.Value + 1] = props.Default[i]
        end
    end
    self.Callback = props.Callback
    self.Disabled = false

    local theme = Theme.Get()

    self.Instance = Utility.Create("TextButton", {
        Name = "MultiDropdown",
        Text = "",
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, Layout.ElementHeight),
        Parent = section.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.ControlRadius), Parent = self.Instance })

    self.NameLabel = Utility.Create("TextLabel", {
        Name = "Name",
        Text = self.Name,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Element,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(0.55, 0, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Instance,
    })
    self.ValueLabel = Utility.Create("TextLabel", {
        Name = "Value",
        Text = "",
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Value,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.new(0.55, 0, 0, 0),
        Size = UDim2.new(1, -44, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Instance,
    })
    self.Arrow = Utility.Create("TextLabel", {
        Name = "Arrow",
        Text = "▾",
        Font = Theme.Fonts.Medium,
        TextSize = 13,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        Active = false,
        Position = UDim2.new(1, -30, 0, 0),
        Size = UDim2.fromOffset(20, Layout.ElementHeight),
        Parent = self.Instance,
    })

    self:Connect(self.Instance.Activated, function()
        if not self.Disabled then
            self:Open()
        end
    end)

    self:SubscribeTheme()
    self:_refreshLabel()
    return self
end

function MultiDropdown:ApplyTheme(theme)
    Element.ApplyTheme(self, theme)
    self._theme = theme
    self.Instance.BackgroundColor3 = theme.SurfaceAlt
    self.NameLabel.TextColor3 = theme.Text
    self.ValueLabel.TextColor3 = theme.Subtext
    self.Arrow.TextColor3 = theme.Subtext
end

function MultiDropdown:_refreshLabel()
    local count = #self.Value
    self.ValueLabel.Text = count == 0 and "None" or (count .. " selected")
end

function MultiDropdown:Open()
    local selfRef = self
    self.Overlay = Overlay.Open({
        Title = self.Name,
        Height = math.min(380, 44 + #self.Options * 44 + 60),
        Footer = true,
        Build = function(ui)
            local theme = Theme.Get()
            local selected = {}
            for i = 1, #selfRef.Value do
                selected[selfRef.Value[i]] = true
            end

            for i = 1, #selfRef.Options do
                local option = selfRef.Options[i]
                local btn = Utility.Create("TextButton", {
                    Name = "Option",
                    Text = "",
                    Font = Theme.Fonts.Medium,
                    TextSize = Layout.FontSize.Element,
                    BackgroundColor3 = theme.SurfaceAlt,
                    BackgroundTransparency = 0,
                    BorderSizePixel = 0,
                    AutoButtonColor = false,
                    Size = UDim2.new(1, 0, 0, 40),
                    LayoutOrder = i,
                    Parent = ui.Content,
                })
                Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = btn })
                Utility.Create("TextLabel", {
                    Text = tostring(option),
                    Font = Theme.Fonts.Medium,
                    TextSize = Layout.FontSize.Element,
                    TextColor3 = theme.Text,
                    BackgroundTransparency = 1,
                    Active = false,
                    TextXAlignment = Enum.TextXAlignment.Left,
                    Position = UDim2.new(0, 12, 0, 0),
                    Size = UDim2.new(1, -40, 1, 0),
                    TextTruncate = Enum.TextTruncate.AtEnd,
                    Parent = btn,
                })
                local check = Utility.Create("TextLabel", {
                    Text = "✓",
                    Font = Theme.Fonts.Bold,
                    TextSize = 16,
                    TextColor3 = theme.Accent,
                    BackgroundTransparency = 1,
                    Active = false,
                    TextXAlignment = Enum.TextXAlignment.Right,
                    Position = UDim2.new(1, -12, 0, 0),
                    Size = UDim2.fromOffset(24, 40),
                    Visible = selected[option] == true,
                    Parent = btn,
                })
                btn.Activated:Connect(function()
                    if selected[option] then
                        selected[option] = nil
                    else
                        selected[option] = true
                    end
                    check.Visible = selected[option] == true
                end)
            end

            -- Footer: Clear + Done
            local clear = Utility.Create("TextButton", {
                Text = "Clear",
                Font = Theme.Fonts.Bold,
                TextSize = Layout.FontSize.Value,
                TextColor3 = theme.Subtext,
                BackgroundColor3 = theme.SurfaceAlt,
                BackgroundTransparency = 0,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Size = UDim2.fromOffset(72, 36),
                LayoutOrder = 1,
                Parent = ui.Footer,
            })
            Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = clear })
            clear.Activated:Connect(function()
                for k in pairs(selected) do
                    selected[k] = nil
                end
                selfRef:Set({}, true)
                if selfRef.Overlay then
                    selfRef.Overlay:Close()
                end
            end)

            local done = Utility.Create("TextButton", {
                Text = "Done",
                Font = Theme.Fonts.Bold,
                TextSize = Layout.FontSize.Value,
                TextColor3 = theme.OnAccent,
                BackgroundColor3 = theme.Accent,
                BackgroundTransparency = 0,
                BorderSizePixel = 0,
                AutoButtonColor = false,
                Size = UDim2.fromOffset(88, 36),
                LayoutOrder = 2,
                Parent = ui.Footer,
            })
            Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = done })
            done.Activated:Connect(function()
                local newValue = {}
                for i = 1, #selfRef.Options do
                    if selected[selfRef.Options[i]] then
                        newValue[#newValue + 1] = selfRef.Options[i]
                    end
                end
                selfRef:Set(newValue, true)
                if selfRef.Overlay then
                    selfRef.Overlay:Close()
                end
            end)
        end,
    })
end

function MultiDropdown:Set(values, fireCallback)
    self.Value = {}
    if type(values) == "table" then
        for i = 1, #values do
            self.Value[#self.Value + 1] = values[i]
        end
    end
    self:_refreshLabel()
    if fireCallback and self.Callback then
        self.Callback(self.Value)
    end
end

function MultiDropdown:Get()
    local copy = {}
    for i = 1, #self.Value do
        copy[i] = self.Value[i]
    end
    return copy
end

function MultiDropdown:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self.Instance.GroupTransparency = self.Disabled and 0.4 or 0
end

function MultiDropdown:Destroy()
    if self.Overlay then
        self.Overlay:Close()
        self.Overlay = nil
    end
    Element.Destroy(self)
end

return MultiDropdown
    end)

    -- ==================== Components/Paragraph ====================
    _def("Components/Paragraph", function(require)
--[[ Lumen UI — Components/Paragraph: wrapped body text ]]
local Element = require("UI/Element")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")

local Paragraph = setmetatable({}, { __index = Element })
Paragraph.__index = Paragraph

function Paragraph.new(section, props)
    local self = setmetatable({}, Paragraph)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window

    local theme = Theme.Get()

    self.Instance = Utility.Create("TextLabel", {
        Name = "Paragraph",
        Text = props.Text or "",
        Font = Theme.Fonts.Regular,
        TextSize = props.Size or Layout.FontSize.Value,
        TextColor3 = props.Color or theme.Subtext,
        BackgroundTransparency = 1,
        TextXAlignment = props.Alignment or Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Top,
        TextWrapped = true,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        Parent = section.Instance,
    })

    if not props.Color then
        self:BindColor(self.Instance, "TextColor3", "Subtext")
    end

    self:SubscribeTheme()
    return self
end

function Paragraph:Set(text)
    self.Instance.Text = text
end

function Paragraph:SetColor(color)
    self.Instance.TextColor3 = color
end

return Paragraph
    end)

    -- ==================== Components/Search ====================
    _def("Components/Search", function(require)
--[[
    Lumen UI — Components/Search
    A rounded search input with a drawn magnifier icon and a clear button.
    Fires OnChange as the user types; wire it to your own filtering logic.
]]

local Element = require("UI/Element")
local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")

local Search = setmetatable({}, { __index = Element })
Search.__index = Search

function Search.new(section, props)
    local self = setmetatable({}, Search)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window
    self.Placeholder = props.Placeholder or "Search…"
    self.OnChange = props.OnChange
    self.Disabled = false

    local theme = Theme.Get()

    self.Instance = Utility.Create("Frame", {
        Name = "Search",
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, Layout.ElementHeight),
        Parent = section.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.ControlRadius), Parent = self.Instance })
    Utility.Create("UIStroke", { Color = theme.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = self.Instance })

    -- Drawn magnifier icon (no external assets)
    local icon = Utility.Create("Frame", {
        Name = "Icon",
        Active = false,
        BackgroundTransparency = 1,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(16, 16),
        Parent = self.Instance,
    })
    local ring = Utility.Create("Frame", {
        Name = "Ring",
        Active = false,
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(11, 11),
        Position = UDim2.new(0, 0, 0, 0),
        Parent = icon,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = ring })
    local ringStroke = Utility.Create("UIStroke", {
        Color = theme.Subtext,
        Thickness = 1.5,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = ring,
    })
    local handle = Utility.Create("Frame", {
        Name = "Handle",
        Active = false,
        BackgroundColor3 = theme.Subtext,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromOffset(11, 12),
        Size = UDim2.fromOffset(6, 1.5),
        Rotation = 45,
        Parent = icon,
    })

    self.Input = Utility.Create("TextBox", {
        Name = "Input",
        Text = "",
        PlaceholderText = self.Placeholder,
        PlaceholderColor3 = theme.Subtext,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Element,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 34, 0, 0),
        Size = UDim2.new(1, -68, 1, 0),
        Parent = self.Instance,
    })

    self.ClearButton = Utility.Create("TextButton", {
        Name = "Clear",
        Text = "✕",
        Font = Theme.Fonts.Medium,
        TextSize = 12,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(24, 24),
        Visible = false,
        Parent = self.Instance,
    })

    self.IconRing = ringStroke
    self.IconHandle = handle

    self:Connect(self.Input:GetPropertyChangedSignal("Text"), function()
        local hasText = self.Input.Text ~= ""
        self.ClearButton.Visible = hasText
        if self.OnChange then
            self.OnChange(self.Input.Text)
        end
    end)
    self:Connect(self.ClearButton.Activated, function()
        self.Input.Text = ""
    end)

    self:SubscribeTheme()
    return self
end

function Search:ApplyTheme(theme)
    Element.ApplyTheme(self, theme)
    self._theme = theme
    self.Instance.BackgroundColor3 = theme.SurfaceAlt
    self.Instance.UIStroke.Color = theme.Border
    self.IconRing.Color = theme.Subtext
    self.IconHandle.BackgroundColor3 = theme.Subtext
    self.Input.TextColor3 = theme.Text
    self.Input.PlaceholderColor3 = theme.Subtext
    self.ClearButton.TextColor3 = theme.Subtext
end

function Search:Set(text)
    self.Input.Text = text or ""
end

function Search:Get()
    return self.Input.Text
end

function Search:Clear()
    self.Input.Text = ""
end

function Search:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self.Input.TextEditable = not self.Disabled
    self.Instance.GroupTransparency = self.Disabled and 0.4 or 0
end

return Search
    end)

    -- ==================== Components/Slider ====================
    _def("Components/Slider", function(require)
--[[
    Lumen UI — Components/Slider
    Label + live value readout + a track with a draggable thumb. Input is
    handled through the track's InputChanged events (no heartbeat); the fill
    and thumb update in place only while the value actually changes.
]]

local Element = require("UI/Element")
local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")

local Slider = setmetatable({}, { __index = Element })
Slider.__index = Slider

function Slider.new(section, props)
    local self = setmetatable({}, Slider)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window
    self.Name = props.Name or "Slider"
    self.Min = props.Min or 0
    self.Max = props.Max or 100
    self.Step = props.Step or 1
    self.Decimals = props.Decimals or 0
    self.Suffix = props.Suffix or ""
    self.Callback = props.Callback
    self.Disabled = false
    self.Value = Utility.Clamp(props.Default or self.Min, self.Min, self.Max)

    local theme = Theme.Get()

    self.Instance = Utility.Create("Frame", {
        Name = "Slider",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 56),
        Parent = section.Instance,
    })

    self.NameLabel = Utility.Create("TextLabel", {
        Name = "Name",
        Text = self.Name,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Element,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 0, 0, 0),
        Size = UDim2.new(1, -80, 0, 22),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Instance,
    })
    self.ValueLabel = Utility.Create("TextLabel", {
        Name = "Value",
        Text = "",
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Value,
        TextColor3 = theme.Accent,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Right,
        Position = UDim2.new(1, -80, 0, 0),
        Size = UDim2.new(0, 80, 0, 22),
        Parent = self.Instance,
    })

    self.Track = Utility.Create("Frame", {
        Name = "Track",
        Active = true,
        BackgroundColor3 = theme.SliderTrack,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 8),
        Size = UDim2.new(1, 0, 0, 10),
        Parent = self.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.Track })

    self.Fill = Utility.Create("Frame", {
        Name = "Fill",
        Active = false,
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(0, 1),
        Parent = self.Track,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.Fill })

    self.Thumb = Utility.Create("Frame", {
        Name = "Thumb",
        Active = false,
        BackgroundColor3 = theme.ToggleKnob,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 0, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        ZIndex = 2,
        Parent = self.Track,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.Thumb })

    local dragging = false
    local function updateFromPosition(absX)
        local absPos = self.Track.AbsolutePosition
        local absSize = self.Track.AbsoluteSize
        if absSize.X <= 0 then
            return
        end
        local ratio = Utility.Clamp((absX - absPos.X) / absSize.X, 0, 1)
        local value = self.Min + ratio * (self.Max - self.Min)
        if self.Step and self.Step > 0 then
            value = Utility.Round(value / self.Step) * self.Step
        end
        value = Utility.Clamp(value, self.Min, self.Max)
        if value ~= self.Value then
            self:Set(value, true)
        end
    end

    self:Connect(self.Track.InputBegan, function(input)
        if self.Disabled then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            updateFromPosition(input.Position.X)
        end
    end)
    self:Connect(self.Track.InputChanged, function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            updateFromPosition(input.Position.X)
        end
    end)
    self:Connect(self.Track.InputEnded, function()
        dragging = false
    end)
    self:Connect(game:GetService("UserInputService").InputEnded, function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch) then
            dragging = false
        end
    end)

    self:SubscribeTheme()
    self:_refreshVisuals()
    return self
end

function Slider:ApplyTheme(theme)
    Element.ApplyTheme(self, theme)
    self._theme = theme
    self.NameLabel.TextColor3 = theme.Text
    self.ValueLabel.TextColor3 = theme.Accent
    self.Track.BackgroundColor3 = theme.SliderTrack
    self.Fill.BackgroundColor3 = theme.Accent
    self.Thumb.BackgroundColor3 = theme.ToggleKnob
end

function Slider:_refreshVisuals()
    if self.Destroyed then
        return
    end
    local ratio = (self.Value - self.Min) / math.max(self.Max - self.Min, 0.0001)
    self.Fill.Size = UDim2.fromScale(ratio, 1)
    self.Thumb.Position = UDim2.new(ratio, -9, 0.5, 0)
    self.ValueLabel.Text = Utility.FormatNumber(self.Value, self.Decimals) .. self.Suffix
end

function Slider:Set(value, fireCallback)
    self.Value = Utility.Clamp(value, self.Min, self.Max)
    self:_refreshVisuals()
    if fireCallback and self.Callback then
        self.Callback(self.Value)
    end
end

function Slider:Get()
    return self.Value
end

function Slider:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self.Instance.GroupTransparency = self.Disabled and 0.4 or 0
end

return Slider
    end)

    -- ==================== Components/Textbox ====================
    _def("Components/Textbox", function(require)
--[[
    Lumen UI — Components/Textbox
    Label above a full-width input. On mobile it nudges the window up while
    focused so the virtual keyboard never covers the field, then restores the
    position on focus loss.
]]

local Element = require("UI/Element")
local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")

local Textbox = setmetatable({}, { __index = Element })
Textbox.__index = Textbox

function Textbox.new(section, props)
    local self = setmetatable({}, Textbox)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window
    self.Name = props.Name or "Textbox"
    self.Placeholder = props.Placeholder or ""
    self.Value = props.Default or ""
    self.Callback = props.Callback
    self.OnChange = props.OnChange
    self.Disabled = false

    local theme = Theme.Get()

    self.Instance = Utility.Create("Frame", {
        Name = "Textbox",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 58),
        Parent = section.Instance,
    })

    self.NameLabel = Utility.Create("TextLabel", {
        Name = "Name",
        Text = self.Name,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Value,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 2, 0, 0),
        Size = UDim2.new(1, 0, 0, 18),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Instance,
    })

    self.Input = Utility.Create("TextBox", {
        Name = "Input",
        Text = self.Value,
        PlaceholderText = self.Placeholder,
        PlaceholderColor3 = theme.Subtext,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Element,
        TextColor3 = theme.Text,
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ClearTextOnFocus = props.ClearTextOnFocus == true,
        Position = UDim2.new(0, 0, 0, 22),
        Size = UDim2.new(1, 0, 0, 36),
        Parent = self.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.ControlRadius), Parent = self.Input })
    Utility.Create("UIStroke", { Color = theme.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = self.Input })

    self:Connect(self.Input.Focused, function()
        self.Window:_onInputFocus(true)
    end)
    self:Connect(self.Input.FocusLost, function(enterPressed)
        self.Window:_onInputFocus(false)
        self.Value = self.Input.Text
        if self.Callback then
            self.Callback(self.Input.Text, enterPressed)
        end
    end)
    if self.OnChange then
        self:Connect(self.Input:GetPropertyChangedSignal("Text"), function()
            self.OnChange(self.Input.Text)
        end)
    end

    self:SubscribeTheme()
    return self
end

function Textbox:ApplyTheme(theme)
    Element.ApplyTheme(self, theme)
    self._theme = theme
    self.NameLabel.TextColor3 = theme.Subtext
    self.Input.BackgroundColor3 = theme.SurfaceAlt
    self.Input.TextColor3 = theme.Text
    self.Input.PlaceholderColor3 = theme.Subtext
    self.Input.UIStroke.Color = theme.Border
end

function Textbox:Set(text)
    self.Value = text or ""
    self.Input.Text = self.Value
end

function Textbox:Get()
    return self.Input.Text
end

function Textbox:SetPlaceholder(text)
    self.Placeholder = text or ""
    self.Input.PlaceholderText = self.Placeholder
end

function Textbox:Clear()
    self.Input.Text = ""
end

function Textbox:Focus()
    self.Input:CaptureFocus()
end

function Textbox:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self.Input.TextEditable = not self.Disabled
    self.Instance.GroupTransparency = self.Disabled and 0.4 or 0
end

return Textbox
    end)

    -- ==================== Components/Toggle ====================
    _def("Components/Toggle", function(require)
--[[
    Lumen UI — Components/Toggle
    Row with a label and a large thumb switch. The knob slide and track color
    are single tweens on toggle; nothing animates while idle.
]]

local Element = require("UI/Element")
local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")
local Animation = require("Core/Animation")

local Toggle = setmetatable({}, { __index = Element })
Toggle.__index = Toggle

function Toggle.new(section, props)
    local self = setmetatable({}, Toggle)
    Element.init(self)
    props = props or {}
    self.Section = section
    self.Window = section.Window
    self.Name = props.Name or "Toggle"
    self.Value = props.Default and true or false
    self.Callback = props.Callback
    self.Disabled = false

    local theme = Theme.Get()

    self.Instance = Utility.Create("TextButton", {
        Name = "Toggle",
        Text = "",
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.new(1, 0, 0, Layout.ElementHeight),
        Parent = section.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.ControlRadius), Parent = self.Instance })

    self.NameLabel = Utility.Create("TextLabel", {
        Name = "Name",
        Text = self.Name,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Element,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -70, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Instance,
    })

    self.Track = Utility.Create("Frame", {
        Name = "Track",
        Active = false,
        BackgroundColor3 = theme.ToggleOff,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -12, 0.5, 0),
        Size = UDim2.fromOffset(44, 24),
        Parent = self.Instance,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.Track })

    self.Knob = Utility.Create("Frame", {
        Name = "Knob",
        Active = false,
        BackgroundColor3 = theme.ToggleKnob,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(18, 18),
        Parent = self.Track,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = self.Knob })

    self:Connect(self.Instance.Activated, function()
        if not self.Disabled then
            self:Set(not self.Value, true)
        end
    end)

    self:SubscribeTheme()
    self:_applyVisuals()
    return self
end

function Toggle:ApplyTheme(theme)
    Element.ApplyTheme(self, theme)
    self._theme = theme
    self.NameLabel.TextColor3 = theme.Text
    self.Instance.BackgroundColor3 = theme.SurfaceAlt
    self:_applyVisuals()
end

function Toggle:_applyVisuals()
    if not self._theme or self.Destroyed then
        return
    end
    local theme = self._theme
    if self.Value then
        Animation.Tween(self.Track, { BackgroundColor3 = theme.Accent }, 0.12)
        Animation.Tween(self.Knob, { Position = UDim2.new(0, 23, 0.5, 0) }, 0.12)
    else
        Animation.Tween(self.Track, { BackgroundColor3 = theme.ToggleOff }, 0.12)
        Animation.Tween(self.Knob, { Position = UDim2.new(0, 3, 0.5, 0) }, 0.12)
    end
    self.Knob.BackgroundColor3 = theme.ToggleKnob
    self.Instance.TextTransparency = self.Disabled and 0.4 or 0
    self.Track.BackgroundTransparency = self.Disabled and 0.4 or 0
end

function Toggle:Set(value, fireCallback)
    self.Value = value and true or false
    self:_applyVisuals()
    if fireCallback and self.Callback then
        self.Callback(self.Value)
    end
end

function Toggle:Get()
    return self.Value
end

function Toggle:SetDisabled(disabled)
    self.Disabled = disabled and true or false
    self:_applyVisuals()
end

return Toggle
    end)

    -- ==================== Core/Animation ====================
    _def("Core/Animation", function(require)
--[[
    Lumen UI — Core/Animation
    Thin wrapper over TweenService. When Config.Animations is false we set the
    target values directly and skip creating tweens entirely, saving CPU on
    weak devices.
]]

local Config = require("Core/Config")

local TweenService = game:GetService("TweenService")

local Animation = {}

function Animation.Tween(instance, goals, duration, easingStyle, easingDirection)
    if not Config.Animations then
        for key, value in pairs(goals) do
            instance[key] = value
        end
        return nil
    end
    local info = TweenInfo.new(
        duration or Config.AnimationDuration,
        easingStyle or Enum.EasingStyle.Quart,
        easingDirection or Enum.EasingDirection.Out,
        0,
        false,
        0
    )
    local tween = TweenService:Create(instance, info, goals)
    tween:Play()
    return tween
end

return Animation
    end)

    -- ==================== Core/Config ====================
    _def("Core/Config", function(require)
--[[
    Lumen UI — Core/Config
    Global configuration. Users can mutate this table directly at runtime:
        Library.Config.Animations = false
]]

local Config = {
    -- Master switch for all animations/tweens. Disable on very weak devices.
    Animations = true,

    -- Base duration (seconds) for most UI tweens. Keep short for a snappy feel.
    AnimationDuration = 0.16,

    -- How long (seconds) a notification stays on screen before auto-dismissing.
    NotificationDuration = 3,

    -- Force mobile layout. nil = auto-detect via UserInputService.TouchEnabled.
    MobileMode = nil,

    -- Minimum delay (seconds) between repeated keybind triggers while held.
    KeybindDelay = 0.25,

    -- Corner radii (design pixels, scaled by the window's UIScale).
    WindowRadius = 16,
    SectionRadius = 12,
    ControlRadius = 9,
}

local _cachedMobile = nil

function Config.IsMobile()
    if Config.MobileMode ~= nil then
        return Config.MobileMode
    end
    if _cachedMobile == nil then
        _cachedMobile = game:GetService("UserInputService").TouchEnabled
    end
    return _cachedMobile
end

return Config
    end)

    -- ==================== Core/Input ====================
    _def("Core/Input", function(require)
--[[
    Lumen UI — Core/Input
    Touch/mouse dragging. We use the grab-handle's own InputBegan/Changed/Ended
    events (they only fire while the pointer is over the handle), so there is
    no permanent RenderStepped/Heartbeat loop — the window moves only while the
    user actually drags it. A single global InputEnded acts as a safety net for
    releases that happen outside the handle.
]]

local Utility = require("Core/Utility")

local Input = {}

local UserInputService = game:GetService("UserInputService")

-- options:
--   Handle   GuiObject that receives the drag input
--   Target   GuiObject being moved (used for clamping against AbsoluteSize)
--   Scale    the window's UIScale factor (offsets are divided by it)
--   Clamp    keep the window grabbable on-screen (default true)
--   MinGrabX / MinGrabY   minimum pixels of the title bar kept reachable
--   OnMove   function(absPosition) called after clamping
function Input.CreateDragger(options)
    local target = options.Target
    local handle = options.Handle
    local scale = options.Scale or 1

    -- Ensure the handle actually receives input events on every platform.
    handle.Active = true
    local minGrabX = options.MinGrabX or 80
    local minGrabY = options.MinGrabY or 40

    local dragging = false
    local lastPos = Vector2.zero
    local activeInput = nil

    local function clampPosition(pos)
        if options.Clamp == false then
            return pos
        end
        local camera = workspace.CurrentCamera
        local vp = camera and camera.ViewportSize or Vector2.new(1080, 720)
        local size = target.AbsoluteSize
        local minX = -(size.X - minGrabX)
        local maxX = vp.X - minGrabX
        local maxY = vp.Y - minGrabY
        return Vector2.new(
            Utility.Clamp(pos.X, minX, maxX),
            Utility.Clamp(pos.Y, 0, maxY)
        )
    end

    local function writePosition(pos)
        if options.OnMove then
            options.OnMove(pos)
        else
            target.Position = UDim2.fromOffset(pos.X / scale, pos.Y / scale)
        end
    end

    local conns = {}

    conns[#conns + 1] = handle.InputBegan:Connect(function(input)
        if dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            activeInput = input
            lastPos = input.Position
        end
    end)

    conns[#conns + 1] = handle.InputChanged:Connect(function(input)
        if not dragging then
            return
        end
        if input.UserInputType == Enum.UserInputType.MouseMovement
            or input.UserInputType == Enum.UserInputType.Touch then
            local delta = input.Position - lastPos
            lastPos = input.Position
            writePosition(clampPosition(target.AbsolutePosition + delta))
        end
    end)

    local function endDrag(input)
        if dragging and input == activeInput then
            dragging = false
            activeInput = nil
        end
    end

    conns[#conns + 1] = handle.InputEnded:Connect(endDrag)
    conns[#conns + 1] = UserInputService.InputEnded:Connect(endDrag)

    return {
        Destroy = function()
            for i = 1, #conns do
                conns[i]:Disconnect()
            end
            dragging = false
        end,
    }
end

return Input
    end)

    -- ==================== Core/Layout ====================
    _def("Core/Layout", function(require)
--[[
    Lumen UI — Core/Layout
    Mobile-first design metrics. Every value here is a "design pixel" that the
    window's UIScale multiplies so the UI stays proportionally identical on
    phones, tablets and desktop.

    The scale is computed from the viewport so the window always fits on-screen
    (width and height) while keeping touch targets large.
]]

local Utility = require("Core/Utility")

local Layout = {}

Layout.DesignWidth = 380
Layout.DesignHeight = 560

Layout.Pad = 14              -- outer window padding
Layout.SectionPad = 12       -- padding inside a section
Layout.Spacing = 8           -- vertical gap between elements
Layout.SectionGap = 12       -- gap between sections
Layout.ElementHeight = 40    -- minimum touch-friendly control height
Layout.TitleBarHeight = 52
Layout.TabBarHeight = 44

Layout.FontSize = {
    Title = 17,
    Subtitle = 11,
    Tab = 13,
    Section = 12,
    Element = 14,
    Value = 13,
    Small = 11,
}

function Layout.GetViewport()
    local camera = workspace.CurrentCamera
    if not camera then
        return Vector2.new(1080, 720)
    end
    return camera.ViewportSize
end

-- Uniform scale applied to the whole window via UIScale.
-- Scales with screen size but is clamped so it never becomes unusably small
-- or comically large on ultra-wide displays.
function Layout.ComputeScale()
    local vp = Layout.GetViewport()
    local byWidth = vp.X / (Layout.DesignWidth + 24)
    local byHeight = (vp.Y - 24) / Layout.DesignHeight
    local scale = math.min(byWidth, byHeight)
    return Utility.Clamp(scale, 0.6, 1.35)
end

return Layout
    end)

    -- ==================== Core/Signal ====================
    _def("Core/Signal", function(require)
--[[
    Lumen UI — Core/Signal
    A minimal, dependency-free signal. Used for theme-change propagation.
    Avoids BindableEvent overhead and gives clean disconnect semantics.
]]

local Signal = {}
Signal.__index = Signal

local Connection = {}
Connection.__index = Connection

function Connection:Disconnect()
    if not self.Connected then
        return
    end
    self.Connected = false
    local listeners = self._signal._listeners
    for i = 1, #listeners do
        if listeners[i] == self then
            table.remove(listeners, i)
            break
        end
    end
end

function Signal.new()
    local self = setmetatable({}, Signal)
    self._listeners = {}
    return self
end

function Signal:Connect(listener)
    local conn = setmetatable({
        Connected = true,
        _signal = self,
        _listener = listener,
    }, Connection)
    table.insert(self._listeners, conn)
    return conn
end

function Signal:Fire(...)
    -- Iterate over a snapshot so listeners can disconnect safely mid-fire.
    local snapshot = {}
    for i = 1, #self._listeners do
        snapshot[#snapshot + 1] = self._listeners[i]
    end
    local args = { n = select("#", ...), ... }
    for i = 1, #snapshot do
        local conn = snapshot[i]
        if conn.Connected then
            conn._listener(table.unpack(args, 1, args.n))
        end
    end
end

function Signal:Destroy()
    for i = 1, #self._listeners do
        self._listeners[i].Connected = false
    end
    self._listeners = {}
end

return Signal
    end)

    -- ==================== Core/Theme ====================
    _def("Core/Theme", function(require)
--[[
    Lumen UI — Core/Theme
    Real theme system. A theme is a flat table of colors + small numeric knobs.
    Presets live in Theme.Themes; Theme.Set accepts a preset name, a preset
    table, or a partial custom table (missing keys are merged over the current
    theme). Subscribers (windows/elements) are notified on change.
]]

local Signal = require("Core/Signal")
local Utility = require("Core/Utility")

local Theme = {}

Theme.Fonts = {
    Regular = Enum.Font.Gotham,
    Medium = Enum.Font.GothamMedium,
    Bold = Enum.Font.GothamBold,
}

local function makeTheme(name, colors)
    return {
        Name = name,
        Background = colors.Background,
        Surface = colors.Surface,
        SurfaceAlt = colors.SurfaceAlt,
        Border = colors.Border,
        Accent = colors.Accent,
        OnAccent = colors.OnAccent,
        Text = colors.Text,
        Subtext = colors.Subtext,
        ToggleOff = colors.ToggleOff,
        ToggleKnob = colors.ToggleKnob,
        SliderTrack = colors.SliderTrack,
        Success = colors.Success,
        Warning = colors.Warning,
        Danger = colors.Danger,
        Info = colors.Info,
        Shadow = colors.Shadow,
        HoverTint = 0.06,   -- lighten amount on hover
        PressTint = 0.14,   -- darken amount on press
    }
end

Theme.Themes = {
    Dark = makeTheme("Dark", {
        Background = Color3.fromRGB(15, 17, 23),
        Surface = Color3.fromRGB(24, 27, 35),
        SurfaceAlt = Color3.fromRGB(33, 37, 48),
        Border = Color3.fromRGB(46, 51, 64),
        Accent = Color3.fromRGB(84, 196, 224),
        OnAccent = Color3.fromRGB(7, 20, 24),
        Text = Color3.fromRGB(233, 236, 243),
        Subtext = Color3.fromRGB(146, 153, 170),
        ToggleOff = Color3.fromRGB(48, 53, 66),
        ToggleKnob = Color3.fromRGB(255, 255, 255),
        SliderTrack = Color3.fromRGB(40, 44, 56),
        Success = Color3.fromRGB(86, 207, 150),
        Warning = Color3.fromRGB(235, 177, 85),
        Danger = Color3.fromRGB(234, 104, 104),
        Info = Color3.fromRGB(84, 196, 224),
        Shadow = Color3.fromRGB(0, 0, 0),
    }),
    Light = makeTheme("Light", {
        Background = Color3.fromRGB(244, 246, 250),
        Surface = Color3.fromRGB(255, 255, 255),
        SurfaceAlt = Color3.fromRGB(240, 243, 248),
        Border = Color3.fromRGB(220, 225, 232),
        Accent = Color3.fromRGB(36, 120, 220),
        OnAccent = Color3.fromRGB(255, 255, 255),
        Text = Color3.fromRGB(28, 32, 40),
        Subtext = Color3.fromRGB(108, 116, 130),
        ToggleOff = Color3.fromRGB(205, 211, 220),
        ToggleKnob = Color3.fromRGB(255, 255, 255),
        SliderTrack = Color3.fromRGB(226, 231, 238),
        Success = Color3.fromRGB(38, 160, 110),
        Warning = Color3.fromRGB(200, 140, 40),
        Danger = Color3.fromRGB(210, 70, 70),
        Info = Color3.fromRGB(36, 120, 220),
        Shadow = Color3.fromRGB(60, 66, 80),
    }),
    Midnight = makeTheme("Midnight", {
        Background = Color3.fromRGB(10, 11, 16),
        Surface = Color3.fromRGB(18, 20, 28),
        SurfaceAlt = Color3.fromRGB(26, 29, 40),
        Border = Color3.fromRGB(40, 44, 58),
        Accent = Color3.fromRGB(110, 140, 255),
        OnAccent = Color3.fromRGB(12, 14, 26),
        Text = Color3.fromRGB(226, 230, 240),
        Subtext = Color3.fromRGB(130, 138, 158),
        ToggleOff = Color3.fromRGB(36, 40, 52),
        ToggleKnob = Color3.fromRGB(245, 247, 252),
        SliderTrack = Color3.fromRGB(30, 33, 44),
        Success = Color3.fromRGB(90, 210, 150),
        Warning = Color3.fromRGB(238, 180, 90),
        Danger = Color3.fromRGB(236, 110, 110),
        Info = Color3.fromRGB(110, 140, 255),
        Shadow = Color3.fromRGB(0, 0, 0),
    }),
    Emerald = makeTheme("Emerald", {
        Background = Color3.fromRGB(11, 20, 17),
        Surface = Color3.fromRGB(18, 29, 25),
        SurfaceAlt = Color3.fromRGB(24, 38, 32),
        Border = Color3.fromRGB(36, 52, 45),
        Accent = Color3.fromRGB(66, 214, 160),
        OnAccent = Color3.fromRGB(8, 24, 18),
        Text = Color3.fromRGB(226, 238, 233),
        Subtext = Color3.fromRGB(140, 158, 150),
        ToggleOff = Color3.fromRGB(34, 48, 42),
        ToggleKnob = Color3.fromRGB(245, 255, 250),
        SliderTrack = Color3.fromRGB(28, 40, 35),
        Success = Color3.fromRGB(66, 214, 160),
        Warning = Color3.fromRGB(232, 180, 90),
        Danger = Color3.fromRGB(232, 110, 110),
        Info = Color3.fromRGB(90, 180, 220),
        Shadow = Color3.fromRGB(0, 0, 0),
    }),
    Rose = makeTheme("Rose", {
        Background = Color3.fromRGB(22, 14, 18),
        Surface = Color3.fromRGB(30, 20, 25),
        SurfaceAlt = Color3.fromRGB(39, 26, 33),
        Border = Color3.fromRGB(52, 38, 46),
        Accent = Color3.fromRGB(244, 120, 150),
        OnAccent = Color3.fromRGB(26, 10, 16),
        Text = Color3.fromRGB(240, 228, 233),
        Subtext = Color3.fromRGB(160, 140, 150),
        ToggleOff = Color3.fromRGB(48, 32, 40),
        ToggleKnob = Color3.fromRGB(255, 245, 248),
        SliderTrack = Color3.fromRGB(40, 28, 35),
        Success = Color3.fromRGB(90, 205, 140),
        Warning = Color3.fromRGB(235, 178, 85),
        Danger = Color3.fromRGB(235, 100, 100),
        Info = Color3.fromRGB(110, 150, 235),
        Shadow = Color3.fromRGB(0, 0, 0),
    }),
    Sand = makeTheme("Sand", {
        Background = Color3.fromRGB(247, 243, 236),
        Surface = Color3.fromRGB(255, 252, 246),
        SurfaceAlt = Color3.fromRGB(240, 235, 226),
        Border = Color3.fromRGB(222, 214, 200),
        Accent = Color3.fromRGB(214, 140, 60),
        OnAccent = Color3.fromRGB(255, 255, 255),
        Text = Color3.fromRGB(40, 36, 30),
        Subtext = Color3.fromRGB(120, 110, 95),
        ToggleOff = Color3.fromRGB(208, 200, 188),
        ToggleKnob = Color3.fromRGB(255, 255, 255),
        SliderTrack = Color3.fromRGB(226, 220, 208),
        Success = Color3.fromRGB(60, 160, 110),
        Warning = Color3.fromRGB(200, 140, 40),
        Danger = Color3.fromRGB(205, 70, 70),
        Info = Color3.fromRGB(80, 130, 200),
        Shadow = Color3.fromRGB(70, 60, 50),
    }),
}

Theme.Changed = Signal.new()
Theme.Current = Utility.DeepCopy(Theme.Themes.Dark)

-- Accepts a preset name string, a preset table, or a partial custom table.
function Theme.Set(theme, silent)
    local source = theme
    if type(source) == "string" then
        source = Theme.Themes[source]
        if not source then
            warn("[Lumen] Unknown theme: " .. tostring(theme))
            return
        end
    end
    if type(source) ~= "table" or source.Background == nil then
        warn("[Lumen] Invalid theme: expected a table with at least a Background color.")
        return
    end
    local merged = Utility.DeepCopy(Theme.Current)
    for key, value in pairs(source) do
        merged[key] = value
    end
    Theme.Current = merged
    if not silent then
        Theme.Changed:Fire(Theme.Current)
    end
end

function Theme.Get()
    return Theme.Current
end

-- Subscribe to theme changes. The callback runs immediately with the current
-- theme, then again on every change. Returns an unsubscribe function.
function Theme.Subscribe(callback)
    callback(Theme.Current)
    local conn = Theme.Changed:Connect(callback)
    return function()
        conn:Disconnect()
    end
end

return Theme
    end)

    -- ==================== Core/Utility ====================
    _def("Core/Utility", function(require)
--[[
    Lumen UI — Core/Utility
    Shared helpers: instance creation, math, color, text measurement, scheduling.
]]

local Utility = {}

-- Create an Instance and assign properties. "Children" is a special key that
-- parents an array of instances.
function Utility.Create(className, props)
    local instance = Instance.new(className)
    if props then
        for key, value in pairs(props) do
            if key == "Children" then
                for i = 1, #value do
                    value[i].Parent = instance
                end
            elseif value ~= nil then
                instance[key] = value
            end
        end
    end
    return instance
end

function Utility.Clamp(value, min, max)
    if value < min then return min end
    if value > max then return max end
    return value
end

function Utility.Round(value, decimals)
    decimals = decimals or 0
    local mult = 10 ^ decimals
    return math.floor(value * mult + 0.5) / mult
end

function Utility.Lerp(a, b, t)
    return a + (b - a) * t
end

function Utility.LerpColor(a, b, t)
    return Color3.new(
        Utility.Lerp(a.R, b.R, t),
        Utility.Lerp(a.G, b.G, t),
        Utility.Lerp(a.B, b.B, t)
    )
end

function Utility.Lighten(color, amount)
    return Utility.LerpColor(color, Color3.new(1, 1, 1), amount)
end

function Utility.Darken(color, amount)
    return Utility.LerpColor(color, Color3.new(0, 0, 0), amount)
end

-- Cached width of a string in pixels at a given font/size (used once per
-- static label like tabs/sections, not on hot paths).
function Utility.TextWidth(text, font, size)
    return game:GetService("TextService")
        :GetTextSize(text, size, font, Vector2.new(2000, 2000)).X
end

-- Scheduling with fallbacks for executors missing the `task` library.
function Utility.Delay(seconds, callback)
    if task and task.delay then
        task.delay(seconds, callback)
    else
        delay(callback, seconds)
    end
end

function Utility.Spawn(callback)
    if task and task.spawn then
        task.spawn(callback)
    else
        spawn(callback)
    end
end

-- Plain-table deep copy (colors/userdata are returned as-is).
function Utility.DeepCopy(value)
    if type(value) ~= "table" then
        return value
    end
    local copy = {}
    for k, v in pairs(value) do
        copy[Utility.DeepCopy(k)] = Utility.DeepCopy(v)
    end
    return setmetatable(copy, getmetatable(value))
end

-- Format a number for display, trimming trailing zeros (e.g. 1.50 -> "1.5").
function Utility.FormatNumber(value, decimals)
    decimals = decimals or 0
    if decimals <= 0 then
        return tostring(math.floor(value + 0.5))
    end
    local s = string.format("%." .. decimals .. "f", Utility.Round(value, decimals))
    s = s:gsub("%.?0+$", "")
    if s == "" or s == "-" then
        s = "0"
    end
    return s
end

-- Human-friendly name for an input (used by keybinds).
function Utility.KeyName(inputType, keyCode)
    if inputType == Enum.UserInputType.MouseButton1 then
        return "MB1"
    elseif inputType == Enum.UserInputType.MouseButton2 then
        return "MB2"
    elseif inputType == Enum.UserInputType.MouseButton3 then
        return "MB3"
    end
    return keyCode.Name
end

return Utility
    end)

    -- ==================== UI/Element ====================
    _def("UI/Element", function(require)
--[[
    Lumen UI — UI/Element
    Base class for every component. Provides:
      - connection tracking + one-call cleanup (no leaked event connections)
      - theme color bindings + automatic re-style on theme change
      - shared SetVisible / Destroy behavior

    Components inherit via:  local Comp = setmetatable({}, { __index = Element })
]]

local Theme = require("Core/Theme")

local Element = {}
Element.__index = Element

function Element.init(self)
    self.Connections = {}
    self.ThemeBindings = {}
    self.Destroyed = false
    return self
end

function Element:Track(connection)
    self.Connections[#self.Connections + 1] = connection
    return connection
end

function Element:Connect(signal, callback)
    return self:Track(signal:Connect(callback))
end

-- Bind an instance property to a theme color key. ApplyTheme sets it.
function Element:BindColor(instance, property, themeKey)
    self.ThemeBindings[#self.ThemeBindings + 1] = {
        instance = instance,
        property = property,
        key = themeKey,
    }
end

function Element:SubscribeTheme()
    self._unsubscribeTheme = Theme.Subscribe(function(theme)
        self:ApplyTheme(theme)
    end)
end

function Element:ApplyTheme(theme)
    for i = 1, #self.ThemeBindings do
        local binding = self.ThemeBindings[i]
        local color = theme[binding.key]
        if color and binding.instance and binding.instance.Parent then
            binding.instance[binding.property] = color
        end
    end
end

function Element:SetVisible(visible)
    if self.Instance and not self.Destroyed then
        self.Instance.Visible = visible
    end
end

function Element:SetDisabled(disabled)
    -- overridden per component
end

function Element:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    for i = 1, #self.Connections do
        self.Connections[i]:Disconnect()
    end
    self.Connections = {}
    if self._unsubscribeTheme then
        self._unsubscribeTheme()
        self._unsubscribeTheme = nil
    end
    if self.Instance then
        self.Instance:Destroy()
        self.Instance = nil
    end
end

return Element
    end)

    -- ==================== UI/Notification ====================
    _def("UI/Notification", function(require)
--[[
    Lumen UI — UI/Notification
    Toast notifications. Each toast is a one-shot: a fade-in tween, a single
    task.delay for auto-dismiss, a fade-out tween, then destroy. No persistent
    loops. Stacked top-center on mobile, top-right on desktop.
]]

local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")
local Animation = require("Core/Animation")

local Notifications = {}

local Players = game:GetService("Players")

local holder = nil
local noteCount = 0

local function getHolder()
    if not holder or not holder.Parent then
        local gui = Instance.new("ScreenGui")
        gui.Name = "LumenNotifications"
        gui.IgnoreGuiInset = true
        gui.ResetOnSpawn = false
        gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
        gui.DisplayOrder = 90
        gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

        holder = Utility.Create("Frame", {
            Name = "Holder",
            BackgroundTransparency = 1,
            BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 0),
            AutomaticSize = Enum.AutomaticSize.Y,
            Parent = gui,
        })
        Utility.Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            FillDirection = Enum.FillDirection.Vertical,
            Padding = UDim.new(0, 8),
            Parent = holder,
        })
    end
    return holder
end

-- opts: Title, Content, Type ("info" | "success" | "warning" | "danger"), Duration
function Notifications.Notify(opts)
    opts = opts or {}
    local theme = Theme.Get()
    local scale = Layout.ComputeScale()
    local vp = Layout.GetViewport()
    local mobile = Config.IsMobile()

    local width = math.min(320 * scale, vp.X - 24)
    local typeName = opts.Type or "info"
    local accents = {
        info = theme.Info,
        success = theme.Success,
        warning = theme.Warning,
        danger = theme.Danger,
    }
    local accent = accents[typeName] or theme.Info

    local root = getHolder()

    noteCount = noteCount + 1
    local note = Utility.Create("CanvasGroup", {
        Name = "Notification",
        Active = false,
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(width, 60),
        GroupTransparency = 1,
        LayoutOrder = noteCount,
        Parent = root,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.ControlRadius), Parent = note })
    Utility.Create("UIStroke", { Color = theme.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = note })

    Utility.Create("Frame", {
        Name = "AccentBar",
        BackgroundColor3 = accent,
        BorderSizePixel = 0,
        Size = UDim2.new(0, 4, 1, 0),
        Parent = note,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = note.AccentBar })

    Utility.Create("TextLabel", {
        Name = "Title",
        Text = opts.Title or "Notification",
        Font = Theme.Fonts.Bold,
        TextSize = 14,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 14, 0, 8),
        Size = UDim2.new(1, -40, 0, 18),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = note,
    })
    Utility.Create("TextLabel", {
        Name = "Content",
        Text = opts.Content or "",
        Font = Theme.Fonts.Medium,
        TextSize = 12,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 14, 0, 30),
        Size = UDim2.new(1, -40, 0, 22),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = note,
    })
    local closeBtn = Utility.Create("TextButton", {
        Name = "Close",
        Text = "✕",
        Font = Theme.Fonts.Medium,
        TextSize = 12,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0),
        Position = UDim2.new(1, -6, 0, 4),
        Size = UDim2.fromOffset(24, 24),
        Parent = note,
    })

    local closed = false
    local function close()
        if closed then
            return
        end
        closed = true
        if Config.Animations then
            local tween = Animation.Tween(note, { GroupTransparency = 1 }, 0.18)
            if tween then
                tween.Completed:Connect(function()
                    note:Destroy()
                end)
            else
                note:Destroy()
            end
        else
            note:Destroy()
        end
    end

    closeBtn.Activated:Connect(close)
    Animation.Tween(note, { GroupTransparency = 0 }, 0.18)
    Utility.Delay(opts.Duration or Config.NotificationDuration, close)

    return {
        Close = close,
    }
end

return Notifications
    end)

    -- ==================== UI/Overlay ====================
    _def("UI/Overlay", function(require)
--[[
    Lumen UI — UI/Overlay
    Full-screen modal used by Dropdown, MultiDropdown and ColorPicker. It is a
    mobile-friendly bottom-of-center sheet with a dim backdrop that closes on
    tap-outside. Build() receives a context with Content/Footer frames plus a
    Track() helper so callers can register connections that get cleaned up.
]]

local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")
local Animation = require("Core/Animation")

local Overlay = {}
Overlay.__index = Overlay

local Players = game:GetService("Players")

local openOverlays = {}

local function newScreenGui()
    local gui = Instance.new("ScreenGui")
    gui.Name = "LumenOverlay"
    gui.IgnoreGuiInset = true
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 100
    gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
    return gui
end

-- options:
--   Title      string
--   Height     design-px panel height (clamped to viewport)
--   Scrollable bool (default true) — allow the content list to scroll
--   Footer     bool — reserve a bottom bar (Build receives ui.Footer)
--   Build      function(ui)
function Overlay.Open(options)
    local self = setmetatable({}, Overlay)
    self.Connections = {}
    self.Closed = false

    local theme = Theme.Get()
    local scale = Layout.ComputeScale()
    local vp = Layout.GetViewport()

    local panelW = math.min(340, (vp.X - 32) / scale)
    local panelH = math.min(options.Height or 320, (vp.Y - 40) / scale)
    local footerH = options.Footer and 56 or 0

    self.ScreenGui = newScreenGui()

    self.Dim = Utility.Create("Frame", {
        Name = "Dim",
        Active = true,
        BackgroundColor3 = theme.Shadow,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ZIndex = 1,
        Parent = self.ScreenGui,
    })

    self.Panel = Utility.Create("Frame", {
        Name = "Panel",
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        AnchorPoint = Vector2.new(0.5, 0.5),
        Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(panelW, panelH),
        ZIndex = 2,
        Parent = self.ScreenGui,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.WindowRadius), Parent = self.Panel })
    Utility.Create("UIStroke", { Color = theme.Border, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = self.Panel })
    Utility.Create("UIScale", { Scale = scale, Parent = self.Panel })

    -- Title bar
    self.TitleBar = Utility.Create("Frame", {
        Name = "TitleBar",
        BackgroundColor3 = theme.SurfaceAlt,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 44),
        Parent = self.Panel,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.WindowRadius), Parent = self.TitleBar })
    self.TitleLabel = Utility.Create("TextLabel", {
        Text = options.Title or "",
        Font = Theme.Fonts.Bold,
        TextSize = 15,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 14, 0, 0),
        Size = UDim2.new(1, -60, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.TitleBar,
    })
    self.CloseButton = Utility.Create("TextButton", {
        Text = "✕",
        Font = Theme.Fonts.Medium,
        TextSize = 16,
        TextColor3 = theme.Subtext,
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -8, 0.5, 0),
        Size = UDim2.fromOffset(30, 30),
        ZIndex = 3,
        Parent = self.TitleBar,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.CloseButton })
    self.Connections[#self.Connections + 1] = self.CloseButton.Activated:Connect(function()
        self:Close()
    end)

    -- Content
    self.Content = Utility.Create("ScrollingFrame", {
        Name = "Content",
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, 44),
        Size = UDim2.new(1, 0, 1, -(44 + footerH)),
        ScrollingDirection = Enum.ScrollingDirection.Y,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.Border,
        ScrollingEnabled = options.Scrollable ~= false,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromScale(0, 0),
        ClipsDescendants = true,
        ZIndex = 2,
        Parent = self.Panel,
    })
    Utility.Create("UIPadding", {
        PaddingTop = UDim.new(0, 8),
        PaddingBottom = UDim.new(0, 8),
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = self.Content,
    })
    self.ContentList = Utility.Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, 6),
        Parent = self.Content,
    })

    -- Footer (optional)
    self.Footer = nil
    self.FooterList = nil
    if options.Footer then
        self.Footer = Utility.Create("Frame", {
            Name = "Footer",
            BackgroundColor3 = theme.SurfaceAlt,
            BorderSizePixel = 0,
            Position = UDim2.new(0, 0, 1, -footerH),
            Size = UDim2.new(1, 0, 0, footerH),
            ZIndex = 2,
            Parent = self.Panel,
        })
        Utility.Create("UIPadding", {
            PaddingTop = UDim.new(0, 8),
            PaddingBottom = UDim.new(0, 8),
            PaddingLeft = UDim.new(0, 10),
            PaddingRight = UDim.new(0, 10),
            Parent = self.Footer,
        })
        self.FooterList = Utility.Create("UIListLayout", {
            SortOrder = Enum.SortOrder.LayoutOrder,
            FillDirection = Enum.FillDirection.Horizontal,
            Padding = UDim.new(0, 8),
            HorizontalAlignment = Enum.HorizontalAlignment.Right,
            VerticalAlignment = Enum.VerticalAlignment.Center,
            Parent = self.Footer,
        })
    end

    -- Open animation (no continuous loops — one tween, then done)
    if Config.Animations then
        self.Panel.GroupTransparency = 0.3
        Animation.Tween(self.Dim, { BackgroundTransparency = 0.45 }, 0.15)
        Animation.Tween(self.Panel, { GroupTransparency = 0 }, 0.15)
    else
        self.Dim.BackgroundTransparency = 0.45
        self.Panel.GroupTransparency = 0
    end

    -- Tap outside the panel closes it
    self.Connections[#self.Connections + 1] = self.Dim.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            self:Close()
        end
    end)

    if options.Build then
        options.Build({
            Content = self.Content,
            List = self.ContentList,
            Footer = self.Footer,
            FooterList = self.FooterList,
            Scale = scale,
            Theme = theme,
            Track = function(conn)
                self.Connections[#self.Connections + 1] = conn
            end,
        })
    end

    openOverlays[#openOverlays + 1] = self
    return self
end

function Overlay:Close()
    if self.Closed then
        return
    end
    self.Closed = true
    for i = 1, #openOverlays do
        if openOverlays[i] == self then
            table.remove(openOverlays, i)
            break
        end
    end
    for i = 1, #self.Connections do
        self.Connections[i]:Disconnect()
    end
    self.Connections = {}

    local gui = self.ScreenGui
    if Config.Animations then
        Animation.Tween(self.Dim, { BackgroundTransparency = 1 }, 0.12)
        local tween = Animation.Tween(self.Panel, { GroupTransparency = 1 }, 0.12)
        if tween then
            tween.Completed:Connect(function()
                gui:Destroy()
            end)
        else
            gui:Destroy()
        end
    else
        gui:Destroy()
    end
end

function Overlay.CloseAll()
    for i = #openOverlays, 1, -1 do
        if openOverlays[i] then
            openOverlays[i]:Close()
        end
    end
end

return Overlay
    end)

    -- ==================== UI/Section ====================
    _def("UI/Section", function(require)
--[[
    Lumen UI — UI/Section
    A titled card that stacks elements vertically. Sections auto-size their
    height from the UIListLayout so adding/removing elements never needs manual
    resizing.
]]

local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")

local Button = require("Components/Button")
local Toggle = require("Components/Toggle")
local Slider = require("Components/Slider")
local Dropdown = require("Components/Dropdown")
local MultiDropdown = require("Components/MultiDropdown")
local Textbox = require("Components/Textbox")
local Keybind = require("Components/Keybind")
local ColorPicker = require("Components/ColorPicker")
local Label = require("Components/Label")
local Paragraph = require("Components/Paragraph")
local Divider = require("Components/Divider")
local Search = require("Components/Search")

local Section = {}
Section.__index = Section

function Section.new(tab, name)
    local self = setmetatable({}, Section)
    self.Tab = tab
    self.Window = tab.Window
    self.Name = name or ""
    self.Elements = {}
    self.Connections = {}
    self.Destroyed = false

    local theme = Theme.Get()

    self.Instance = Utility.Create("Frame", {
        Name = "Section",
        BackgroundColor3 = theme.Surface,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, 0),
        AutomaticSize = Enum.AutomaticSize.Y,
        LayoutOrder = #tab.Sections + 1,
        Parent = tab.Content,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.SectionRadius), Parent = self.Instance })

    self.Layout = Utility.Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, Layout.Spacing),
        Parent = self.Instance,
    })
    Utility.Create("UIPadding", {
        PaddingTop = UDim.new(0, Layout.SectionPad),
        PaddingBottom = UDim.new(0, Layout.SectionPad),
        PaddingLeft = UDim.new(0, Layout.SectionPad),
        PaddingRight = UDim.new(0, Layout.SectionPad),
        Parent = self.Instance,
    })

    -- Header (accent bar + title)
    self.Header = Utility.Create("Frame", {
        Name = "Header",
        BackgroundTransparency = 1,
        Size = UDim2.new(1, 0, 0, 18),
        LayoutOrder = 0,
        Parent = self.Instance,
    })
    local accentBar = Utility.Create("Frame", {
        Name = "AccentBar",
        BackgroundColor3 = theme.Accent,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(3, 12),
        Position = UDim2.new(0, 0, 0, 3),
        Parent = self.Header,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(1, 0), Parent = accentBar })
    self.TitleLabel = Utility.Create("TextLabel", {
        Text = string.upper(self.Name),
        Font = Theme.Fonts.Bold,
        TextSize = Layout.FontSize.Section,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 12, 0, 0),
        Size = UDim2.new(1, -12, 1, 0),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.Header,
    })

    self._unsubscribeTheme = Theme.Subscribe(function(t)
        self:ApplyTheme(t)
    end)

    return self
end

function Section:ApplyTheme(theme)
    if self.Destroyed then
        return
    end
    self.Instance.BackgroundColor3 = theme.Surface
    self.Header.AccentBar.BackgroundColor3 = theme.Accent
    self.TitleLabel.TextColor3 = theme.Subtext
end

function Section:_addElement(element)
    element.Instance.LayoutOrder = #self.Elements + 1
    element.Instance.Parent = self.Instance
    self.Elements[#self.Elements + 1] = element
    return element
end

function Section:CreateButton(props)
    return self:_addElement(Button.new(self, props or {}))
end

function Section:CreateToggle(props)
    return self:_addElement(Toggle.new(self, props or {}))
end

function Section:CreateSlider(props)
    return self:_addElement(Slider.new(self, props or {}))
end

function Section:CreateDropdown(props)
    return self:_addElement(Dropdown.new(self, props or {}))
end

function Section:CreateMultiDropdown(props)
    return self:_addElement(MultiDropdown.new(self, props or {}))
end

function Section:CreateTextbox(props)
    return self:_addElement(Textbox.new(self, props or {}))
end

function Section:CreateKeybind(props)
    return self:_addElement(Keybind.new(self, props or {}))
end

function Section:CreateColorPicker(props)
    return self:_addElement(ColorPicker.new(self, props or {}))
end

function Section:CreateLabel(props)
    return self:_addElement(Label.new(self, props or {}))
end

function Section:CreateParagraph(props)
    return self:_addElement(Paragraph.new(self, props or {}))
end

function Section:CreateDivider(props)
    return self:_addElement(Divider.new(self, props or {}))
end

function Section:CreateSearch(props)
    return self:_addElement(Search.new(self, props or {}))
end

function Section:SetTitle(name)
    self.Name = name or ""
    self.TitleLabel.Text = string.upper(self.Name)
end

function Section:Clear()
    for i = #self.Elements, 1, -1 do
        self.Elements[i]:Destroy()
    end
    self.Elements = {}
end

function Section:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    self:Clear()
    if self._unsubscribeTheme then
        self._unsubscribeTheme()
        self._unsubscribeTheme = nil
    end
    if self.Instance then
        self.Instance:Destroy()
        self.Instance = nil
    end
end

return Section
    end)

    -- ==================== UI/Tab ====================
    _def("UI/Tab", function(require)
--[[
    Lumen UI — UI/Tab
    A tab owns a pill button in the window's tab bar and a vertical scrolling
    content frame that holds sections. Switching tabs just toggles visibility
    plus a single quick fade tween — nothing runs continuously.
]]

local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")
local Animation = require("Core/Animation")
local SectionModule = require("UI/Section")

local Tab = {}
Tab.__index = Tab

function Tab.new(window, name, index)
    local self = setmetatable({}, Tab)
    self.Window = window
    self.Name = name
    self.Index = index
    self.Sections = {}
    self.Connections = {}
    self.Active = false
    self.Destroyed = false

    local theme = Theme.Get()

    -- Tab button (auto-sized pill, horizontally scrollable when there are many)
    local width = math.max(64, Utility.TextWidth(name, Theme.Fonts.Bold, Layout.FontSize.Tab) + 30)
    self.Button = Utility.Create("TextButton", {
        Name = "Tab_" .. name,
        Text = name,
        Font = Theme.Fonts.Bold,
        TextSize = Layout.FontSize.Tab,
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        Size = UDim2.fromOffset(width, 32),
        LayoutOrder = index,
        ClipsDescendants = true,
        Parent = window.TabBar,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = self.Button })

    -- Content scroller
    self.Content = Utility.Create("ScrollingFrame", {
        Name = "Tab_" .. name .. "_Content",
        BackgroundColor3 = theme.Background,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1),
        ClipsDescendants = true,
        ScrollBarThickness = 3,
        ScrollBarImageColor3 = theme.Border,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        CanvasSize = UDim2.fromScale(0, 0),
        Visible = false,
        Parent = window.Content,
    })
    Utility.Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
        Padding = UDim.new(0, Layout.SectionGap),
        HorizontalAlignment = Enum.HorizontalAlignment.Center,
        Parent = self.Content,
    })
    Utility.Create("UIPadding", {
        PaddingTop = UDim.new(0, Layout.Pad),
        PaddingBottom = UDim.new(0, Layout.Pad),
        PaddingLeft = UDim.new(0, Layout.Pad),
        PaddingRight = UDim.new(0, Layout.Pad),
        Parent = self.Content,
    })

    self.Connections[#self.Connections + 1] = self.Button.Activated:Connect(function()
        window:SetTab(self)
    end)

    self._unsubscribeTheme = Theme.Subscribe(function(t)
        self:ApplyTheme(t)
    end)

    return self
end

function Tab:ApplyTheme(theme)
    if self.Destroyed then
        return
    end
    self._theme = theme
    self:_refreshButton()
    self.Content.ScrollBarImageColor3 = theme.Border
end

function Tab:_refreshButton()
    if not self._theme or self.Destroyed then
        return
    end
    local theme = self._theme
    if self.Active then
        self.Button.BackgroundColor3 = theme.Accent
        self.Button.TextColor3 = theme.OnAccent
    else
        self.Button.BackgroundColor3 = theme.SurfaceAlt
        self.Button.TextColor3 = theme.Subtext
    end
end

function Tab:SetActive(active)
    self.Active = active
    if self.Destroyed then
        return
    end
    self._refreshButton()
    self.Content.Visible = active
    if active and Config.Animations then
        self.Content.GroupTransparency = 0.35
        Animation.Tween(self.Content, { GroupTransparency = 0 }, 0.15)
    elseif active then
        self.Content.GroupTransparency = 0
    end
end

function Tab:CreateSection(name)
    local section = SectionModule.new(self, name)
    self.Sections[#self.Sections + 1] = section
    return section
end

function Tab:SetTitle(name)
    self.Name = name
    self.Button.Text = name
end

function Tab:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    for i = 1, #self.Sections do
        self.Sections[i]:Destroy()
    end
    self.Sections = {}
    for i = 1, #self.Connections do
        self.Connections[i]:Disconnect()
    end
    self.Connections = {}
    if self._unsubscribeTheme then
        self._unsubscribeTheme()
        self._unsubscribeTheme = nil
    end
    if self.Button then
        self.Button:Destroy()
        self.Button = nil
    end
    if self.Content then
        self.Content:Destroy()
        self.Content = nil
    end
end

return Tab
    end)

    -- ==================== UI/Window ====================
    _def("UI/Window", function(require)
--[[
    Lumen UI — UI/Window
    The root window: title bar (drag handle), minimize/close, tab bar, content
    area and keyboard handling.

    Layout strategy (mobile-first):
      - Main and Shadow are sized/positioned in absolute screen pixels, so
        dragging is plain pixel math with no scale conversion.
      - Everything inside Main lives in a "Shell" frame that carries the single
        UIScale, so all design-pixel offsets scale uniformly across devices.

    Performance notes:
      - Dragging is driven by InputChanged events only (no Heartbeat loop).
      - Minimize/expand are one-shot tweens, not running animations.
      - Every connection is tracked and disconnected in :Destroy().
]]

local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")
local Animation = require("Core/Animation")
local Input = require("Core/Input")
local TabModule = require("UI/Tab")
local Notification = require("UI/Notification")
local Overlay = require("UI/Overlay")

local Window = {}
Window.__index = Window

local Players = game:GetService("Players")

function Window.new(options)
    local self = setmetatable({}, Window)
    self.Connections = {}
    self.Tabs = {}
    self.ActiveTab = nil
    self.Minimized = false
    self.Destroyed = false
    self._posAbs = Vector2.new(0, 0)
    self._preFocusPos = nil

    options = options or {}
    self.Title = options.Title or "Lumen"
    self.Subtitle = options.Subtitle or ""

    if options.Theme then
        Theme.Set(options.Theme)
    end
    if type(options.Config) == "table" then
        for key, value in pairs(options.Config) do
            Config[key] = value
        end
    end

    local theme = Theme.Get()
    local scale = Layout.ComputeScale()
    self.Scale = scale
    self.AbsWidth = Layout.DesignWidth * scale
    self.AbsHeight = Layout.DesignHeight * scale
    self.AbsCollapsedHeight = Layout.TitleBarHeight * scale

    local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

    self.ScreenGui = Utility.Create("ScreenGui", {
        Name = "Lumen",
        IgnoreGuiInset = true,
        ResetOnSpawn = false,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
        Parent = playerGui,
    })

    -- Drop shadow (sibling behind the main frame, subtle depth only)
    self.Shadow = Utility.Create("Frame", {
        Name = "Shadow",
        BackgroundColor3 = theme.Shadow,
        BackgroundTransparency = 0.82,
        BorderSizePixel = 0,
        Size = UDim2.fromOffset(self.AbsWidth, self.AbsHeight),
        ZIndex = 1,
        Parent = self.ScreenGui,
    })
    Utility.Create("UICorner", {
        CornerRadius = UDim.new(0, Config.WindowRadius * scale),
        Parent = self.Shadow,
    })

    -- Main frame (absolute px, draggable)
    self.Main = Utility.Create("Frame", {
        Name = "Main",
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
        ClipsDescendants = true,
        Size = UDim2.fromOffset(self.AbsWidth, self.AbsHeight),
        ZIndex = 2,
        Parent = self.ScreenGui,
    })
    Utility.Create("UICorner", {
        CornerRadius = UDim.new(0, Config.WindowRadius * scale),
        Parent = self.Main,
    })
    self.MainStroke = Utility.Create("UIStroke", {
        Color = theme.Border,
        Thickness = 1,
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Parent = self.Main,
    })

    -- Scaled shell: all content below uses design pixels
    self.Shell = Utility.Create("Frame", {
        Name = "Shell",
        BackgroundTransparency = 1,
        Size = UDim2.fromOffset(Layout.DesignWidth, Layout.DesignHeight),
        Parent = self.Main,
    })
    Utility.Create("UIScale", { Scale = scale, Parent = self.Shell })

    self:_buildTitleBar(theme)
    self:_buildTabBar(theme)
    self:_buildContent(theme)
    self:_center()

    self.Dragger = Input.CreateDragger({
        Handle = self.DragHandle,
        Target = self.Main,
        MinGrabX = 96 * scale,
        MinGrabY = 52 * scale,
        OnMove = function(absPos)
            self:_setPositionAbs(absPos.X, absPos.Y)
        end,
    })

    self._unsubscribeTheme = Theme.Subscribe(function(t)
        self:ApplyTheme(t)
    end)

    return self
end

function Window:_buildTitleBar(theme)
    self.TitleBar = Utility.Create("Frame", {
        Name = "TitleBar",
        BackgroundColor3 = theme.Surface,
        BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, Layout.TitleBarHeight),
        Parent = self.Shell,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, Config.WindowRadius), Parent = self.TitleBar })

    self.DragHandle = Utility.Create("Frame", {
        Name = "DragHandle",
        Active = true,
        BackgroundTransparency = 1,
        Size = UDim2.fromScale(1, 1),
        Parent = self.TitleBar,
    })

    self.TitleLabel = Utility.Create("TextLabel", {
        Name = "Title",
        Text = self.Title,
        Font = Theme.Fonts.Bold,
        TextSize = Layout.FontSize.Title,
        TextColor3 = theme.Text,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 14, 0, 7),
        Size = UDim2.new(1, -110, 0, 22),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Parent = self.DragHandle,
    })

    self.SubtitleLabel = Utility.Create("TextLabel", {
        Name = "Subtitle",
        Text = self.Subtitle,
        Font = Theme.Fonts.Medium,
        TextSize = Layout.FontSize.Subtitle,
        TextColor3 = theme.Subtext,
        BackgroundTransparency = 1,
        Active = false,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 14, 0, 31),
        Size = UDim2.new(1, -110, 0, 16),
        TextTruncate = Enum.TextTruncate.AtEnd,
        Visible = self.Subtitle ~= "",
        Parent = self.DragHandle,
    })

    self.MinimizeButton = self:_makeTitleButton({
        Text = "▾",
        Offset = -46,
        Callback = function()
            self:ToggleMinimize()
        end,
    })
    self.CloseButton = self:_makeTitleButton({
        Text = "✕",
        Offset = -10,
        Callback = function()
            self:Destroy()
        end,
    })
end

function Window:_makeTitleButton(opts)
    local theme = Theme.Get()
    local btn = Utility.Create("TextButton", {
        Name = "TitleButton",
        Text = opts.Text,
        Font = Theme.Fonts.Medium,
        TextSize = 16,
        TextColor3 = theme.Subtext,
        BackgroundColor3 = theme.SurfaceAlt,
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        AutoButtonColor = false,
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, opts.Offset, 0.5, 0),
        Size = UDim2.fromOffset(32, 32),
        ZIndex = 2,
        Parent = self.TitleBar,
    })
    Utility.Create("UICorner", { CornerRadius = UDim.new(0, 8), Parent = btn })

    local state = { hover = false, pressed = false }
    local function refresh()
        local t = Theme.Get()
        local color = t.SurfaceAlt
        if state.pressed then
            color = Utility.Darken(color, t.PressTint)
        elseif state.hover then
            color = Utility.Lighten(color, t.HoverTint)
        end
        btn.BackgroundColor3 = color
    end

    self.Connections[#self.Connections + 1] = btn.Activated:Connect(opts.Callback or function() end)
    self.Connections[#self.Connections + 1] = btn.MouseEnter:Connect(function()
        state.hover = true
        refresh()
    end)
    self.Connections[#self.Connections + 1] = btn.MouseLeave:Connect(function()
        state.hover = false
        refresh()
    end)
    self.Connections[#self.Connections + 1] = btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            state.pressed = true
            refresh()
        end
    end)
    self.Connections[#self.Connections + 1] = btn.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1
            or input.UserInputType == Enum.UserInputType.Touch then
            state.pressed = false
            refresh()
        end
    end)

    return btn
end

function Window:_buildTabBar(theme)
    self.TabBar = Utility.Create("ScrollingFrame", {
        Name = "TabBar",
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, Layout.TitleBarHeight),
        Size = UDim2.new(1, 0, 0, Layout.TabBarHeight),
        ScrollingDirection = Enum.ScrollingDirection.X,
        ScrollBarThickness = 0,
        AutomaticCanvasSize = Enum.AutomaticSize.X,
        CanvasSize = UDim2.fromScale(0, 0),
        ClipsDescendants = true,
        Parent = self.Shell,
    })
    Utility.Create("UIPadding", {
        PaddingLeft = UDim.new(0, 10),
        PaddingRight = UDim.new(0, 10),
        Parent = self.TabBar,
    })
    self.TabList = Utility.Create("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Horizontal,
        Padding = UDim.new(0, 6),
        VerticalAlignment = Enum.VerticalAlignment.Center,
        Parent = self.TabBar,
    })
end

function Window:_buildContent(theme)
    local contentTop = Layout.TitleBarHeight + Layout.TabBarHeight
    self.Content = Utility.Create("Frame", {
        Name = "Content",
        BackgroundColor3 = theme.Background,
        BorderSizePixel = 0,
        Position = UDim2.new(0, 0, 0, contentTop),
        Size = UDim2.new(1, 0, 1, -contentTop),
        ClipsDescendants = true,
        Parent = self.Shell,
    })
end

function Window:_center()
    local vp = Layout.GetViewport()
    local x = math.max(0, (vp.X - self.AbsWidth) / 2)
    local y = math.max(0, (vp.Y - self.AbsHeight) / 2)
    self:_setPositionAbs(x, y)
end

function Window:_setPositionAbs(x, y)
    self._posAbs = Vector2.new(x, y)
    self.Main.Position = UDim2.fromOffset(x, y)
    if self.Shadow then
        self.Shadow.Position = UDim2.fromOffset(x, y + 6)
    end
end

function Window:ApplyTheme(theme)
    if self.Destroyed then
        return
    end
    self.Main.BackgroundColor3 = theme.Background
    self.Shadow.BackgroundColor3 = theme.Shadow
    self.MainStroke.Color = theme.Border
    self.TitleBar.BackgroundColor3 = theme.Surface
    self.TitleLabel.TextColor3 = theme.Text
    self.SubtitleLabel.TextColor3 = theme.Subtext
    self.TabBar.BackgroundColor3 = theme.Background
    self.Content.BackgroundColor3 = theme.Background
    -- reset title buttons to idle colors
    self.MinimizeButton.BackgroundColor3 = theme.SurfaceAlt
    self.CloseButton.BackgroundColor3 = theme.SurfaceAlt
end

function Window:CreateTab(name)
    local tab = TabModule.new(self, name, #self.Tabs + 1)
    self.Tabs[#self.Tabs + 1] = tab
    if #self.Tabs == 1 then
        self:SetTab(tab)
    end
    return tab
end

function Window:SetTab(tabOrName)
    if self.Destroyed then
        return
    end
    local tab = tabOrName
    if type(tabOrName) == "string" then
        for i = 1, #self.Tabs do
            if self.Tabs[i].Name == tabOrName then
                tab = self.Tabs[i]
                break
            end
        end
    end
    if type(tab) ~= "table" then
        return
    end
    for i = 1, #self.Tabs do
        self.Tabs[i]:SetActive(self.Tabs[i] == tab)
    end
    self.ActiveTab = tab
end

function Window:GetTab()
    return self.ActiveTab
end

function Window:ToggleMinimize()
    if self.Minimized then
        self:Expand()
    else
        self:Minimize()
    end
end

function Window:Minimize()
    if self.Minimized or self.Destroyed then
        return
    end
    self.Minimized = true
    self.TabBar.Visible = false
    self.Content.Visible = false
    Overlay.CloseAll()
    local goal = UDim2.fromOffset(self.AbsWidth, self.AbsCollapsedHeight)
    Animation.Tween(self.Main, { Size = goal }, 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut)
    Animation.Tween(self.Shadow, { Size = goal }, 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut)
end

function Window:Expand()
    if not self.Minimized or self.Destroyed then
        return
    end
    self.Minimized = false
    self.TabBar.Visible = true
    self.Content.Visible = true
    local goal = UDim2.fromOffset(self.AbsWidth, self.AbsHeight)
    Animation.Tween(self.Main, { Size = goal }, 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut)
    Animation.Tween(self.Shadow, { Size = goal }, 0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.InOut)
end

function Window:SetTitle(text)
    self.Title = text
    self.TitleLabel.Text = text
end

function Window:SetSubtitle(text)
    self.Subtitle = text or ""
    self.SubtitleLabel.Text = self.Subtitle
    self.SubtitleLabel.Visible = self.Subtitle ~= ""
end

function Window:SetVisible(visible)
    self.ScreenGui.Enabled = visible
end

function Window:Notify(opts)
    return Notification.Notify(opts or {})
end

-- Nudge the window up while a TextBox is focused on mobile, so the virtual
-- keyboard doesn't cover the input. Position is restored on focus loss.
function Window:_onInputFocus(focused)
    if not Config.IsMobile() then
        return
    end
    if focused and not self.Minimized then
        self._preFocusPos = self._posAbs
        local vp = Layout.GetViewport()
        local bottom = self._posAbs.Y + self.Main.AbsoluteSize.Y
        local targetBottom = vp.Y * 0.55
        if bottom > targetBottom then
            local newY = targetBottom - self.Main.AbsoluteSize.Y
            if newY < 0 then
                newY = 0
            end
            self:_setPositionAbs(self._posAbs.X, newY)
        end
    elseif not focused and self._preFocusPos then
        self:_setPositionAbs(self._preFocusPos.X, self._preFocusPos.Y)
        self._preFocusPos = nil
    end
end

function Window:Destroy()
    if self.Destroyed then
        return
    end
    self.Destroyed = true
    for i = 1, #self.Tabs do
        self.Tabs[i]:Destroy()
    end
    self.Tabs = {}
    if self.Dragger then
        self.Dragger.Destroy()
        self.Dragger = nil
    end
    for i = 1, #self.Connections do
        self.Connections[i]:Disconnect()
    end
    self.Connections = {}
    if self._unsubscribeTheme then
        self._unsubscribeTheme()
        self._unsubscribeTheme = nil
    end
    if self.ScreenGui then
        self.ScreenGui:Destroy()
        self.ScreenGui = nil
    end
end

return Window
    end)

    -- ==================== init ====================
    _def("init", function(require)
--[[
    Lumen UI — entry point
    Public API:
        local Lumen = loadstring(game:HttpGet("..."))()

        local Window = Lumen:CreateWindow({ Title, Subtitle, Theme, Config })
        local Tab = Window:CreateTab("Main")
        local Section = Tab:CreateSection("Section")
        Section:CreateToggle({ ... })
        Lumen:Notify({ ... })
        Lumen:SetTheme(Lumen.Themes.Light)
]]

local Config = require("Core/Config")
local Theme = require("Core/Theme")
local Utility = require("Core/Utility")
local Layout = require("Core/Layout")
local Notification = require("UI/Notification")
local Window = require("UI/Window")

local Library = {}

Library.Name = "Lumen"
Library.Version = "1.0.0"

Library.Config = Config
Library.Themes = Theme.Themes
Library.Layout = Layout

local windows = {}

function Library.CreateWindow(options)
    local window = Window.new(options or {})
    windows[#windows + 1] = window
    return window
end

function Library.SetTheme(theme)
    Theme.Set(theme)
end

function Library.GetTheme()
    return Theme.Get()
end

function Library.Notify(opts)
    return Notification.Notify(opts or {})
end

function Library.DestroyAll()
    for i = 1, #windows do
        windows[i]:Destroy()
    end
    windows = {}
end

return Library
    end)

    return _require("init")
end)()

return Lumen
