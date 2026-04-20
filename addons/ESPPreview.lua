-- ═══════════════════════════════════════════════════════════════════════
-- ESPPreview — live 2D preview of the ESP box.
--
-- Replicates the exact structure of the in-game BillboardGui-based ESP as a
-- ScreenGui Frame, so the user can see how their current ESP settings look
-- without needing a visible enemy. Reads the same Toggles / Options the real
-- ESP reads (ESP, ESPBox, ESPBoxColor, ESPFill, ESPHealthbar, ESPName,
-- ESPDistance, ESPMovementState, ESPHeldWeapon, ESPTeams + their sub-options).
--
-- The preview box geometry (inner box + outer/fill/inner layers + 4 label
-- positions + 4 healthbar positions) is identical to the billboard; only the
-- root is a regular Frame of fixed pixel size, and "scale" fractions are
-- pre-computed for a reference distance so the layout matches what the user
-- sees in-game at ~15 studs.
--
-- The preview uses fake player data (name, distance, weapon, team) so label
-- toggles visibly affect the box even without a live target on screen.
--
-- Public API:
--   ESPPreview:SetLibrary(lib)
--   ESPPreview:BindTab(tab [, tab2, ...])   -- show preview on any bound tab
--   ESPPreview:Show() / :Hide() / :Toggle() -- manual control
--   ESPPreview:SetFakeData(tbl)             -- override displayed fake values
-- ═══════════════════════════════════════════════════════════════════════

local RunService   = game:GetService('RunService')
local TweenService = game:GetService('TweenService')

local ESPPreview = {}
ESPPreview.Library = nil
ESPPreview.Bound   = {}
ESPPreview._wantsVisible = false   -- user is on a bound tab
ESPPreview._visible = false        -- actual window state

-- Fake values used to fill the info labels. Users can override via SetFakeData.
ESPPreview.FakeData = {
    Name           = 'EnemyPlayer',
    Distance       = '42m',
    MovementState  = 'Move',
    HeldWeapon     = 'AK-47',
    Teams          = 'Terrorists',
}

local ESP_INFO_TYPES = { 'Name', 'Distance', 'MovementState', 'HeldWeapon', 'Teams' }

-- Inner box (the "character" region). Fixed base dimensions so the box always
-- renders at the same visible size regardless of which labels are enabled.
local BOX_W = 90
local BOX_H = 150

-- Default padding on each side when no labels are placed there. Small gap so
-- the box isn't flush against the panel edge.
local EDGE_PAD = 8
-- Extra gap between the box edge and a label sitting on that edge.
local LABEL_PAD = 6

-- Window chrome sizes.
local TITLE_H = 25   -- title bar + separator
local WIN_PAD = 8    -- pad around PreviewRoot inside the window Inner

local HB_TWEEN_INFO = TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

function ESPPreview:SetLibrary(lib)
    self.Library = lib
end

function ESPPreview:SetFakeData(tbl)
    if type(tbl) ~= 'table' then return end
    for k, v in tbl do self.FakeData[k] = v end
end

-- ───────── Window creation ─────────

local function buildWindow(self)
    local Library = self.Library
    assert(Library, 'ESPPreview: SetLibrary must be called before use')

    -- Root: draggable dark panel with a titlebar + preview content area.
    -- Initial size is a ballpark; the update loop resizes it to fit labels.
    local initW = BOX_W + 2 * (EDGE_PAD + 30) + 2 * WIN_PAD
    local initH = BOX_H + 2 * (EDGE_PAD + 10) + TITLE_H + WIN_PAD * 2
    local Outer = Instance.new('Frame')
    Outer.Name = 'ESPPreview'
    Outer.AnchorPoint = Vector2.new(0, 0)
    Outer.Position = UDim2.new(1, -initW - 60, 0, 80)
    Outer.Size = UDim2.fromOffset(initW, initH)
    Outer.BackgroundColor3 = Color3.new(0, 0, 0)
    Outer.BorderSizePixel = 0
    Outer.ZIndex = 40
    Outer.Visible = false
    Outer.Parent = Library.ScreenGui

    -- Accent glow: 6 concentric Frames growing outward with rising
    -- transparency. Same manual box-shadow technique used on the main Window
    -- and Watermark — Roblox has no native shadow on Frames.
    for i = 1, 6 do
        local g = Instance.new('Frame')
        g.Name = 'Glow' .. i
        g.BackgroundColor3 = Library.AccentColor
        g.BackgroundTransparency = 0.5 + i * 0.08
        g.BorderSizePixel = 0
        g.Position = UDim2.new(0, -i, 0, -i)
        g.Size = UDim2.new(1, i * 2, 1, i * 2)
        g.ZIndex = 39
        g.Parent = Outer
        Library:AddToRegistry(g, { BackgroundColor3 = 'AccentColor' })
    end

    local Border = Instance.new('Frame')
    Border.Position = UDim2.new(0, 1, 0, 1)
    Border.Size = UDim2.new(1, -2, 1, -2)
    Border.BackgroundColor3 = Library.OutlineColor
    Border.BorderSizePixel = 0
    Border.ZIndex = 41
    Border.Parent = Outer
    Library:AddToRegistry(Border, { BackgroundColor3 = 'OutlineColor' })

    local Inner = Instance.new('Frame')
    Inner.Position = UDim2.new(0, 1, 0, 1)
    Inner.Size = UDim2.new(1, -2, 1, -2)
    Inner.BackgroundColor3 = Library.MainColor
    Inner.BorderSizePixel = 0
    Inner.ZIndex = 42
    Inner.Parent = Border
    Library:AddToRegistry(Inner, { BackgroundColor3 = 'MainColor' })
    Library:ApplyGradient(Inner, 0.2)

    -- Accent line at top with double-sided fade (matches main menu groupboxes).
    local Accent = Instance.new('Frame')
    Accent.Size = UDim2.new(1, 0, 0, 1)
    Accent.BackgroundColor3 = Library.AccentColor
    Accent.BorderSizePixel = 0
    Accent.ZIndex = 43
    Accent.Parent = Inner
    Library:AddToRegistry(Accent, { BackgroundColor3 = 'AccentColor' })
    local aGrad = Instance.new('UIGradient')
    aGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.6),
        NumberSequenceKeypoint.new(0.5, 0),
        NumberSequenceKeypoint.new(1, 0.6),
    })
    aGrad.Parent = Accent

    local Title = Library:CreateLabel({
        Text = 'ESP Preview',
        TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
        Position = UDim2.new(0, 6, 0, 3),
        Size = UDim2.new(1, -12, 0, 16),
        ZIndex = 43,
        Parent = Inner,
    })

    local Sep = Instance.new('Frame')
    Sep.Position = UDim2.new(0, 4, 0, 20)
    Sep.Size = UDim2.new(1, -8, 0, 1)
    Sep.BackgroundColor3 = Library.OutlineColor
    Sep.BorderSizePixel = 0
    Sep.ZIndex = 43
    Sep.Parent = Inner
    Library:AddToRegistry(Sep, { BackgroundColor3 = 'OutlineColor' })

    -- Preview root. Sized dynamically in updatePreview to wrap box + labels.
    local PreviewRoot = Instance.new('Frame')
    PreviewRoot.Name = 'PreviewRoot'
    PreviewRoot.AnchorPoint = Vector2.new(0.5, 0)
    PreviewRoot.Position = UDim2.new(0.5, 0, 0, TITLE_H)
    PreviewRoot.Size = UDim2.fromOffset(initW - 2 * WIN_PAD, initH - TITLE_H - WIN_PAD)
    PreviewRoot.BackgroundTransparency = 1
    PreviewRoot.ClipsDescendants = false
    PreviewRoot.ZIndex = 44
    PreviewRoot.Parent = Inner

    Library:MakeDraggable(Outer, 24)

    return Outer, PreviewRoot
end

-- Build the ESP box structure into `root`. Mirrors main.lua createESPBillboard
-- exactly — same children, same UIGradients, same strokes — just without the
-- BillboardGui wrapper. Returns the refs table used by update().
local function buildESPBox(root, fontFace)
    fontFace = fontFace or Font.fromEnum(Enum.Font.Code)

    local function mkLabel(n, xA, yA)
        local l = Instance.new('TextLabel')
        l.Name = n
        l.BackgroundTransparency = 1
        l.BorderSizePixel = 0
        l.FontFace = fontFace
        l.TextSize = 12
        l.TextColor3 = Color3.new(1, 1, 1)
        l.TextStrokeTransparency = 0.3
        l.Text = ''
        l.TextXAlignment = xA
        l.TextYAlignment = yA
        l.ZIndex = 50
        l.Parent = root
        return l
    end
    local labelTop   = mkLabel('LabelTop',   Enum.TextXAlignment.Center, Enum.TextYAlignment.Bottom)
    local labelRight = mkLabel('LabelRight', Enum.TextXAlignment.Left,   Enum.TextYAlignment.Top)
    local labelLeft  = mkLabel('LabelLeft',  Enum.TextXAlignment.Right,  Enum.TextYAlignment.Top)
    local labelDown  = mkLabel('LabelDown',  Enum.TextXAlignment.Center, Enum.TextYAlignment.Top)

    local function mkHB(n, anc, pos, sz, rot)
        local f = Instance.new('Frame')
        f.Name = n; f.AnchorPoint = anc; f.BorderSizePixel = 0
        f.Position = pos; f.Size = sz; f.ZIndex = 48; f.Parent = root
        local g = Instance.new('UIGradient')
        g.Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(12, 255, 93)),
            ColorSequenceKeypoint.new(1, Color3.new(0, 0, 0)),
        })
        g.Rotation = rot; g.Parent = f
        local s = Instance.new('UIStroke')
        s.Color = Color3.new(0, 0, 0); s.Thickness = 1
        s.LineJoinMode = Enum.LineJoinMode.Miter; s.Parent = f
        return f, g
    end
    local hbTop,   hbTopGrad   = mkHB('HBTop',   Vector2.new(0, 0.9), UDim2.new(0.045, 0, 0, 0),     UDim2.new(0.91, 0, 0, 1),  0)
    local hbRight, hbRightGrad = mkHB('HBRight', Vector2.new(0, 0),   UDim2.new(0.999, 0, 0.025, 0), UDim2.new(0, 1, 0.95, 0), 90)
    local hbLeft,  hbLeftGrad  = mkHB('HBLeft',  Vector2.new(0.9, 0), UDim2.new(0, 0, 0.025, 0),     UDim2.new(0, 1, 0.95, 0), 90)
    local hbDown,  hbDownGrad  = mkHB('HBDown',  Vector2.new(0, 0),   UDim2.new(0.045, 0, 0.999, 0), UDim2.new(0.91, 0, 0, 1),  0)

    local outerBox = Instance.new('Frame')
    outerBox.Name = 'OuterBox'; outerBox.BackgroundTransparency = 1; outerBox.BorderSizePixel = 0
    outerBox.Position = UDim2.new(0.045, -1, 0.025, -1); outerBox.Size = UDim2.new(0.91, 2, 0.95, 2)
    outerBox.ZIndex = 46; outerBox.Parent = root
    local outlineStroke = Instance.new('UIStroke')
    outlineStroke.Name = 'Outline'; outlineStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    outlineStroke.Color = Color3.new(0, 0, 0); outlineStroke.Thickness = 1
    outlineStroke.LineJoinMode = Enum.LineJoinMode.Miter; outlineStroke.Parent = outerBox

    local fillBox = Instance.new('Frame')
    fillBox.Name = 'FillBox'; fillBox.BackgroundTransparency = 1; fillBox.BorderSizePixel = 0
    fillBox.Position = UDim2.new(0.045, 0, 0.025, 0); fillBox.Size = UDim2.new(0.91, 0, 0.95, 0)
    fillBox.ZIndex = 47; fillBox.Parent = root
    local fillGrad = Instance.new('UIGradient'); fillGrad.Name = 'Fill'; fillGrad.Enabled = false; fillGrad.Parent = fillBox
    local mainBoxStroke = Instance.new('UIStroke')
    mainBoxStroke.Name = 'MainBox'; mainBoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    mainBoxStroke.Color = Color3.new(1, 1, 1); mainBoxStroke.Thickness = 1
    mainBoxStroke.LineJoinMode = Enum.LineJoinMode.Miter; mainBoxStroke.Parent = fillBox
    local mainBoxGrad = Instance.new('UIGradient'); mainBoxGrad.Parent = mainBoxStroke

    local innerBox = Instance.new('Frame')
    innerBox.Name = 'InnerBox'; innerBox.BackgroundTransparency = 1; innerBox.BorderSizePixel = 0
    innerBox.Position = UDim2.new(0.045, 1, 0.025, 1); innerBox.Size = UDim2.new(0.91, -2, 0.95, -2)
    innerBox.ZIndex = 47; innerBox.Parent = root
    local inlineStroke = Instance.new('UIStroke')
    inlineStroke.Name = 'Inline'; inlineStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    inlineStroke.Color = Color3.new(0, 0, 0); inlineStroke.Thickness = 1
    inlineStroke.LineJoinMode = Enum.LineJoinMode.Miter; inlineStroke.Parent = innerBox

    local glowGrad = Instance.new('UIGradient')
    glowGrad.Name = 'Glow'; glowGrad.Rotation = 180
    glowGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.5, 1),
        NumberSequenceKeypoint.new(1, 0),
    })
    glowGrad.Enabled = false; glowGrad.Parent = fillBox

    return {
        fillBox = fillBox, outerBox = outerBox, innerBox = innerBox,
        fillGrad = fillGrad, mainBoxStroke = mainBoxStroke, mainBoxGrad = mainBoxGrad,
        glowGrad = glowGrad, inlineStroke = inlineStroke, outlineStroke = outlineStroke,
        labels     = { Top = labelTop, Right = labelRight, Left = labelLeft, Down = labelDown },
        healthbars = {
            Top   = { frame = hbTop,   grad = hbTopGrad   },
            Right = { frame = hbRight, grad = hbRightGrad },
            Left  = { frame = hbLeft,  grad = hbLeftGrad  },
            Down  = { frame = hbDown,  grad = hbDownGrad  },
        },
    }
end

-- Rotation state for box/fill gradients. Separate from the main ESP's rotation
-- so the preview advances even when the main ESP loop is idle (no players).
local boxRot, fillRot = 0, 0

-- Collect per-position label content up-front. Returned table has
-- { text, color, size } per position for the main update to apply AND the
-- resize math to measure required space.
local function collectLabelsToDraw(fakeData)
    local out = {
        Top   = { text = '', color = nil, size = 12 },
        Right = { text = '', color = nil, size = 12 },
        Left  = { text = '', color = nil, size = 12 },
        Down  = { text = '', color = nil, size = 12 },
    }
    for _, it in ESP_INFO_TYPES do
        local tn = 'ESP' .. it
        if Toggles[tn] and Toggles[tn].Value then
            local p = Options['ESP' .. it .. 'Pos'] and Options['ESP' .. it .. 'Pos'].Value or 'Top'
            local t = fakeData[it] or ''
            if t ~= '' then
                local entry = out[p]
                if entry then
                    local c = Options['ESP' .. it .. 'Color'] and Options['ESP' .. it .. 'Color'].Value or Color3.new(1, 1, 1)
                    local s = Options['ESP' .. it .. 'Size']  and Options['ESP' .. it .. 'Size'].Value  or 12
                    local sep = (p == 'Top' or p == 'Down') and ' | ' or '\n'
                    entry.text  = entry.text == '' and t or (entry.text .. sep .. t)
                    entry.color = entry.color or c
                    entry.size  = s
                end
            end
        end
    end
    return out
end

-- Measure pixel bounds the text will take. Returns (width, height) in pixels.
--
-- CRITICAL: GetTextSize expects an `Enum.Font` EnumItem for the font arg, NOT
-- a `Font` object (as returned by Font.fromEnum or Font.new). Passing a Font
-- object raises "Unable to cast Font to Font" every frame — the error spam
-- triggered BAC Alpha-3B (error-pattern anti-cheat) and kicked the user.
-- Always use the EnumItem directly. pcall wrapper prevents future type drift
-- from ever reaching BAC.
local function measureText(text, size)
    if not text or text == '' then return 0, 0 end
    local ok, b = pcall(game:GetService('TextService').GetTextSize,
        game:GetService('TextService'),
        text, size, Enum.Font.Code, Vector2.new(math.huge, math.huge))
    if not ok or not b then return 0, 0 end
    return b.X, b.Y
end

-- Live update of the preview box. Reads the same Options/Toggles the real
-- updateESP reads. Resizes Outer + PreviewRoot each frame to wrap the
-- box + whatever labels are currently enabled.
local function updatePreview(win, refs, fakeData, dt)
    local labels = collectLabelsToDraw(fakeData)

    -- Measure how much room each edge needs.
    local topW,  topH  = measureText(labels.Top.text,   labels.Top.size)
    local downW, downH = measureText(labels.Down.text,  labels.Down.size)
    local leftW, leftH = measureText(labels.Left.text,  labels.Left.size)
    local rightW,rightH= measureText(labels.Right.text, labels.Right.size)

    local marginT = (labels.Top.text  ~= '' and (topH + LABEL_PAD))  or EDGE_PAD
    local marginB = (labels.Down.text ~= '' and (downH + LABEL_PAD)) or EDGE_PAD
    local marginL = (labels.Left.text ~= '' and (leftW + LABEL_PAD)) or EDGE_PAD
    local marginR = (labels.Right.text~= '' and (rightW + LABEL_PAD))or EDGE_PAD

    -- Horizontal label text width also bounds the min preview width (so
    -- top/bottom labels aren't truncated when they're wider than the box).
    local minBoxW = math.max(BOX_W, topW, downW)

    local totalW = marginL + minBoxW + marginR
    local totalH = marginT + BOX_H  + marginB

    -- Resize the PreviewRoot + window Outer to wrap everything cleanly.
    win.previewRoot.Size = UDim2.fromOffset(totalW, totalH)
    local winW = totalW + 2 * WIN_PAD
    local winH = totalH + TITLE_H + WIN_PAD
    if win.outer.Size.X.Offset ~= winW or win.outer.Size.Y.Offset ~= winH then
        win.outer.Size = UDim2.fromOffset(winW, winH)
    end

    -- Compute scale fractions of the box region inside the preview root.
    local bx = marginL / totalW
    local by = marginT / totalH
    local bw = minBoxW / totalW
    local bh = BOX_H   / totalH

    -- Size / position the box layers + label anchors (same math as the
    -- real updateESP, just driven by our dynamic bx/by/bw/bh).
    refs.outerBox.Position = UDim2.new(bx, -1, by, -1); refs.outerBox.Size = UDim2.new(bw, 2, bh, 2)
    refs.fillBox.Position  = UDim2.new(bx, 0, by, 0);   refs.fillBox.Size  = UDim2.new(bw, 0, bh, 0)
    refs.innerBox.Position = UDim2.new(bx, 1, by, 1);   refs.innerBox.Size = UDim2.new(bw, -2, bh, -2)

    refs.labels.Top.Position   = UDim2.new(bx, 0, 0, 0);                 refs.labels.Top.Size   = UDim2.new(bw, 0, 0, marginT - 2)
    refs.labels.Down.Position  = UDim2.new(bx, 0, by + bh, 2);           refs.labels.Down.Size  = UDim2.new(bw, 0, 0, marginB - 2)
    refs.labels.Right.Position = UDim2.new(bx + bw, 2, by, 0);           refs.labels.Right.Size = UDim2.new(0, marginR - 2, bh, 0)
    refs.labels.Left.Position  = UDim2.new(bx, -(marginL - 2), by, 0);   refs.labels.Left.Size  = UDim2.new(0, marginL - 2, bh, 0)

    -- Fake HP fraction so healthbars don't appear full-size.
    local hpFrac = 0.68

    -- Box layers ---------------------------------------------------------
    local boxOn = Toggles.ESPBox and Toggles.ESPBox.Value
    refs.fillBox.Visible = boxOn; refs.outerBox.Visible = boxOn; refs.innerBox.Visible = boxOn
    if boxOn then
        local c1 = Options.ESPBoxColor and Options.ESPBoxColor.Value or Color3.new(1, 1, 1)
        if Toggles.ESPBoxGradient and Toggles.ESPBoxGradient.Value then
            local c2 = Options.ESPBoxColor2 and Options.ESPBoxColor2.Value or Color3.new(1, 0, 0)
            refs.mainBoxGrad.Enabled = true
            refs.mainBoxGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, c1), ColorSequenceKeypoint.new(1, c2),
            })
            if Toggles.ESPBoxRotation and Toggles.ESPBoxRotation.Value then
                boxRot = (boxRot + (Options.ESPBoxGradRot and Options.ESPBoxGradRot.Value or 90) * dt) % 360
            end
            refs.mainBoxGrad.Rotation = boxRot
            refs.mainBoxStroke.Color = Color3.new(1, 1, 1)
        else
            refs.mainBoxGrad.Enabled = false
            refs.mainBoxStroke.Color = c1
        end
    end

    if Toggles.ESPFill and Toggles.ESPFill.Value and boxOn then
        local fc = Options.ESPFillColor and Options.ESPFillColor.Value or Color3.new(1, 1, 1)
        refs.fillBox.BackgroundTransparency = Options.ESPFillTrans and Options.ESPFillTrans.Value or 0.8
        refs.fillBox.BackgroundColor3 = fc
        refs.fillGrad.Enabled = false; refs.glowGrad.Enabled = false
        local m = Options.ESPFillMode and Options.ESPFillMode.Value or 'Static'
        if m == 'Gradient' then
            local fc2 = Options.ESPFillColor2 and Options.ESPFillColor2.Value or Color3.new(1, 0, 0)
            refs.fillBox.BackgroundColor3 = Color3.new(1, 1, 1)
            refs.fillGrad.Enabled = true
            refs.fillGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, fc), ColorSequenceKeypoint.new(1, fc2),
            })
            if Toggles.ESPFillRotation and Toggles.ESPFillRotation.Value then
                fillRot = (fillRot + (Options.ESPFillGradRot and Options.ESPFillGradRot.Value or 90) * dt) % 360
            end
            refs.fillGrad.Rotation = fillRot
        elseif m == 'Glow' then
            local fc2 = Options.ESPFillColor2 and Options.ESPFillColor2.Value or Color3.new(1, 0, 0)
            refs.fillBox.BackgroundColor3 = Color3.new(1, 1, 1)
            refs.glowGrad.Enabled = true
            refs.glowGrad.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, fc), ColorSequenceKeypoint.new(1, fc2),
            })
        end
    else
        refs.fillBox.BackgroundTransparency = 1
        refs.fillGrad.Enabled = false; refs.glowGrad.Enabled = false
    end

    -- Healthbar ----------------------------------------------------------
    local hbOn  = Toggles.ESPHealthbar and Toggles.ESPHealthbar.Value
    local hbPos = Options.ESPHealthbarPos and Options.ESPHealthbarPos.Value or 'Top'
    local hbC   = Options.ESPHealthbarColor  and Options.ESPHealthbarColor.Value  or Color3.fromRGB(12, 255, 93)
    local hbC2  = Options.ESPHealthbarColor2 and Options.ESPHealthbarColor2.Value or Color3.new(1, 0, 0)
    for pos, hb in refs.healthbars do
        if hbOn and pos == hbPos then
            hb.frame.Visible = true
            local targetSize
            if pos == 'Top' then
                hb.frame.AnchorPoint = Vector2.new(0, 1)
                hb.frame.Position = UDim2.new(bx, 0, by, -5)
                targetSize = UDim2.new(bw * hpFrac, 0, 0, 1); hb.grad.Rotation = 0
            elseif pos == 'Down' then
                hb.frame.AnchorPoint = Vector2.new(0, 0)
                hb.frame.Position = UDim2.new(bx, 0, by + bh, 5)
                targetSize = UDim2.new(bw * hpFrac, 0, 0, 1); hb.grad.Rotation = 0
            elseif pos == 'Right' then
                hb.frame.AnchorPoint = Vector2.new(0, 1)
                hb.frame.Position = UDim2.new(bx + bw, 5, by + bh, 0)
                targetSize = UDim2.new(0, 1, bh * hpFrac, 0); hb.grad.Rotation = 90
            elseif pos == 'Left' then
                hb.frame.AnchorPoint = Vector2.new(1, 1)
                hb.frame.Position = UDim2.new(bx, -5, by + bh, 0)
                targetSize = UDim2.new(0, 1, bh * hpFrac, 0); hb.grad.Rotation = 90
            end
            if refs._hbTween then pcall(refs._hbTween.Cancel, refs._hbTween) end
            refs._hbTween = TweenService:Create(hb.frame, HB_TWEEN_INFO, { Size = targetSize })
            refs._hbTween:Play()
            local lerped = Color3.new(
                hbC.R + (hbC2.R - hbC.R) * (1 - hpFrac),
                hbC.G + (hbC2.G - hbC.G) * (1 - hpFrac),
                hbC.B + (hbC2.B - hbC.B) * (1 - hpFrac)
            )
            if Toggles.ESPHealthbarGradient and Toggles.ESPHealthbarGradient.Value then
                hb.grad.Enabled = true
                hb.grad.Color = ColorSequence.new({
                    ColorSequenceKeypoint.new(0, hbC), ColorSequenceKeypoint.new(1, hbC2),
                })
                hb.frame.BackgroundColor3 = Color3.new(1, 1, 1)
            else
                hb.grad.Enabled = false
                hb.frame.BackgroundColor3 = lerped
            end
        else
            hb.frame.Visible = false
        end
    end

    -- Labels: already collected up-front. Apply text/color/size to each
    -- position; hide positions without content.
    for pos, lbl in refs.labels do
        local entry = labels[pos]
        if entry and entry.text ~= '' then
            lbl.Text = entry.text
            lbl.TextColor3 = entry.color or Color3.new(1, 1, 1)
            lbl.TextSize = entry.size or 12
            lbl.Visible = true
        else
            lbl.Text = ''
            lbl.Visible = false
        end
    end
end

-- ───────── Visibility lifecycle ─────────

-- Effective visibility combines:
--   _wantsVisible — user is on a bound tab (managed by BindTabs)
--   menu open     — library-level toggle state
-- The window renders ONLY when both are true. Missing either one hides it.
local function applyVisibility(self)
    if not self._built or not self._window then return end
    local menuOpen = self.Library and self.Library.Toggled ~= false
    local show = self._wantsVisible and menuOpen
    self._visible = show
    self._window.Visible = show
end

local function ensureBuilt(self)
    if self._built then return end
    local outer, previewRoot = buildWindow(self)
    self._win = { outer = outer, previewRoot = previewRoot }
    self._window = outer
    self._previewRoot = previewRoot
    self._refs = buildESPBox(previewRoot, self.Library:GetActiveFont())
    self._built = true

    -- Per-frame preview update while visible. Registered with the library's
    -- signal list so :Unload cleans it up automatically.
    self._conn = RunService.RenderStepped:Connect(function(dt)
        if not self._visible or not self._window or not self._window.Parent then return end
        if not Toggles or not Options then return end
        updatePreview(self._win, self._refs, self.FakeData, dt)
    end)
    self.Library:GiveSignal(self._conn)

    -- Close-on-menu-close: watch Library.Toggled. Missing Heartbeat gate keeps
    -- the check lightweight (bool compare) and avoids piling work on RenderStepped.
    self._toggleConn = RunService.Heartbeat:Connect(function()
        local menuOpen = self.Library and self.Library.Toggled ~= false
        local shouldShow = self._wantsVisible and menuOpen
        if shouldShow ~= self._visible then
            applyVisibility(self)
        end
    end)
    self.Library:GiveSignal(self._toggleConn)

    -- Keep fonts in sync with library-wide font selection.
    self.Library:OnFontChanged(function(face)
        if not self._refs then return end
        for _, lbl in self._refs.labels do
            pcall(function() lbl.FontFace = face end)
        end
    end)
end

function ESPPreview:Show()
    ensureBuilt(self)
    self._wantsVisible = true
    applyVisibility(self)
end

function ESPPreview:Hide()
    self._wantsVisible = false
    applyVisibility(self)
end

function ESPPreview:Toggle()
    if self._wantsVisible then self:Hide() else self:Show() end
end

-- Attach the preview to a Window: walks every tab and wraps its ShowTab so
-- switching to a bound tab calls :Show() and switching to any other tab calls
-- :Hide(). Call this AFTER you've created all your tabs.
--
--   ESPPreview:BindTabs(Window, { Tabs.ESP })
--
-- The library itself doesn't track the owning Window, so it has to be passed
-- in. Each tab is hooked exactly once; safe to call BindTabs multiple times
-- (useful if more tabs are added later).
function ESPPreview:BindTabs(window, boundTabs)
    if not window or not window.Tabs then return end
    local set = {}
    for _, t in boundTabs or {} do set[t] = true; self.Bound[t] = true end
    for _, tab in window.Tabs do
        if tab._espPreviewHooked then continue end
        tab._espPreviewHooked = true
        local origShow = tab.ShowTab
        local bound = set[tab] or self.Bound[tab]
        tab.ShowTab = function(s, ...)
            local ret = origShow(s, ...)
            if bound then self:Show() else self:Hide() end
            return ret
        end
    end
end

-- Legacy single-tab binding. Works standalone but doesn't auto-hide when the
-- user switches to another tab — use :BindTabs(window, {...}) for that.
function ESPPreview:BindTab(tab)
    if not tab or tab._espPreviewHooked then return end
    tab._espPreviewHooked = true
    self.Bound[tab] = true
    local origShow = tab.ShowTab
    tab.ShowTab = function(s, ...)
        local ret = origShow(s, ...)
        self:Show()
        return ret
    end
end

return ESPPreview
