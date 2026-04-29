local InputService = game:GetService('UserInputService');
local TextService = game:GetService('TextService');
local CoreGui = game:GetService('CoreGui');
local Teams = game:GetService('Teams');
local Players = game:GetService('Players');
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService');
local RenderStepped = RunService.RenderStepped;
local LocalPlayer = Players.LocalPlayer;
local Mouse = LocalPlayer:GetMouse();

local ProtectGui = protectgui or (syn and syn.protect_gui) or (function() end);

local ScreenGui = Instance.new('ScreenGui');
ProtectGui(ScreenGui);

ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
ScreenGui.Parent = CoreGui;

local Toggles = {};
local Options = {};

getgenv().Toggles = Toggles;
getgenv().Options = Options;

local Library = {
    Registry = {};
    RegistryMap = {};

    HudRegistry = {};

    FontColor = Color3.fromRGB(185, 185, 185);
    MainColor = Color3.fromRGB(24, 24, 35);
    BackgroundColor = Color3.fromRGB(22, 22, 31);
    AccentColor = Color3.fromRGB(115, 70, 190);
    OutlineColor = Color3.fromRGB(45, 45, 45);
    RiskColor = Color3.fromRGB(220, 50, 50),

    Black = Color3.new(0, 0, 0);
    Font = Enum.Font.Code,

    OpenedFrames = {};
    DependencyBoxes = {};

    Signals = {};
    ScreenGui = ScreenGui;

    -- Public: reflects menu open/close state (set by Library:Toggle). Used by
    -- features like PlaceholderBox to decide whether to show even when empty.
    Toggled = false;

    -- Registry of user-spawned PlaceholderBoxes so Library:Toggle() can
    -- refresh their visibility on menu open/close.
    PlaceholderBoxes = {};

    -- Notification spawn corner: 'TopLeft' (default) / 'TopRight' / 'Middle'.
    -- Set via Library:SetNotificationPosition(pos).
    NotificationPosition = 'TopLeft';
};

local RainbowStep = 0
local Hue = 0

table.insert(Library.Signals, RenderStepped:Connect(function(Delta)
    RainbowStep = RainbowStep + Delta

    if RainbowStep >= (1 / 60) then
        RainbowStep = 0

        Hue = Hue + (1 / 400);

        if Hue > 1 then
            Hue = 0;
        end;

        Library.CurrentRainbowHue = Hue;
        Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1);
    end
end))

local function GetPlayersString()
    local PlayerList = Players:GetPlayers();

    for i = 1, #PlayerList do
        PlayerList[i] = PlayerList[i].Name;
    end;

    table.sort(PlayerList, function(str1, str2) return str1 < str2 end);

    return PlayerList;
end;

local function GetTeamsString()
    local TeamList = Teams:GetTeams();

    for i = 1, #TeamList do
        TeamList[i] = TeamList[i].Name;
    end;

    table.sort(TeamList, function(str1, str2) return str1 < str2 end);
    
    return TeamList;
end;

function Library:SafeCallback(f, ...)
    if (not f) then
        return;
    end;

    if not Library.NotifyOnError then
        return f(...);
    end;

    local success, event = pcall(f, ...);

    if not success then
        local _, i = event:find(":%d+: ");

        if not i then
            return Library:Notify(event);
        end;

        return Library:Notify(event:sub(i + 1), 3);
    end;
end;

function Library:AttemptSave()
    if Library.SaveManager then
        Library.SaveManager:Save();
    end;
end;

function Library:Create(Class, Properties)
    local _Instance = Class;

    if type(Class) == 'string' then
        _Instance = Instance.new(Class);
    end;

    for Property, Value in next, Properties do
        _Instance[Property] = Value;
    end;

    return _Instance;
end;

function Library:ApplyTextStroke(Inst)
    Inst.TextStrokeTransparency = 1;

    Library:Create('UIStroke', {
        Color = Color3.new(0, 0, 0);
        Thickness = 1;
        LineJoinMode = Enum.LineJoinMode.Miter;
        Parent = Inst;
    });
end;

-- Apply a subtle top→bottom transparency gradient to any Frame so the UI has
-- depth instead of looking flat. `strength` is the bottom transparency (0-1),
-- default 0.35 — higher values darken the bottom more.
function Library:ApplyGradient(Inst, strength)
    local s = strength or 0.35;
    return Library:Create('UIGradient', {
        Rotation = 90;
        Color = ColorSequence.new(Color3.new(1, 1, 1));
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0);
            NumberSequenceKeypoint.new(1, s);
        });
        Parent = Inst;
    });
end;

-- ═══════════════════════════════════════════════════════════════════
-- UI Polish Helpers (scale-pop, ripple, shimmer, inner shadow, etc.)
--
-- Each helper adds a small visual effect to an existing Frame without
-- changing its layout. Kept together so the call sites below stay lean.
-- ═══════════════════════════════════════════════════════════════════

-- Scale-pop: tween a UIScale child on MouseEnter/Leave. Gives a subtle "bump"
-- when hovering interactive elements (buttons, toggles, sliders, dropdowns).
function Library:AddScalePop(Frame, hoverScale, duration)
    local scale = Frame:FindFirstChildOfClass('UIScale')
        or Library:Create('UIScale', { Scale = 1, Parent = Frame });
    local target = hoverScale or 1.03;
    local info = TweenInfo.new(duration or 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
    Frame.MouseEnter:Connect(function()
        TweenService:Create(scale, info, { Scale = target }):Play();
    end);
    Frame.MouseLeave:Connect(function()
        TweenService:Create(scale, info, { Scale = 1 }):Play();
    end);
    return scale;
end;

-- Ripple: on MouseButton1 click, spawn a circular Frame at the click point
-- that expands + fades out. Attaches to a clickable Frame and uses its
-- AbsolutePosition to convert the mouse location into frame-local pixels.
function Library:AddRipple(Frame, rippleColor)
    Frame.ClipsDescendants = true;
    local color = rippleColor or Color3.new(1, 1, 1);
    Frame.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1
            and Input.UserInputType ~= Enum.UserInputType.Touch then return end;
        local relX = Input.Position.X - Frame.AbsolutePosition.X;
        local relY = Input.Position.Y - Frame.AbsolutePosition.Y;

        local ripple = Instance.new('Frame');
        ripple.BackgroundColor3 = color;
        ripple.BackgroundTransparency = 0.7;
        ripple.BorderSizePixel = 0;
        ripple.AnchorPoint = Vector2.new(0.5, 0.5);
        ripple.Position = UDim2.fromOffset(relX, relY);
        ripple.Size = UDim2.fromOffset(0, 0);
        ripple.ZIndex = Frame.ZIndex + 1;
        ripple.Parent = Frame;
        Instance.new('UICorner', ripple).CornerRadius = UDim.new(1, 0);

        -- Expand to cover the frame, fade to transparent.
        local maxDim = math.max(Frame.AbsoluteSize.X, Frame.AbsoluteSize.Y) * 2.2;
        local info = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
        TweenService:Create(ripple, info, {
            Size = UDim2.fromOffset(maxDim, maxDim),
            BackgroundTransparency = 1,
        }):Play();
        task.delay(0.5, function()
            pcall(ripple.Destroy, ripple);
        end);
    end);
end;

-- Inner shadow: 4 thin gradient bars along the edges of a Frame. Each bar is
-- colored black with a UIGradient that fades from the edge inward, giving
-- the frame a subtle "inset" depth.
function Library:AddInnerShadow(Frame, strength)
    local t = strength or 0.6;
    local z = (Frame.ZIndex or 1) + 1;
    local function mk(pos, size, rot)
        local f = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderSizePixel = 0;
            Position = pos;
            Size = size;
            ZIndex = z;
            Parent = Frame;
        });
        Library:Create('UIGradient', {
            Rotation = rot;
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, t),
                NumberSequenceKeypoint.new(1, 1),
            });
            Parent = f;
        });
        return f;
    end;
    mk(UDim2.new(0, 0, 0, 0), UDim2.new(1, 0, 0, 6), 90);     -- top: fade down
    mk(UDim2.new(0, 0, 1, -6), UDim2.new(1, 0, 0, 6), -90);   -- bottom: fade up
    mk(UDim2.new(0, 0, 0, 0), UDim2.new(0, 6, 1, 0), 0);      -- left: fade right
    mk(UDim2.new(1, -6, 0, 0), UDim2.new(0, 6, 1, 0), 180);   -- right: fade left
end;

-- Double-sided fade gradient — used for divider lines, accent underlines, etc.
function Library:ApplyDoubleFade(Inst, rotation)
    return Library:Create('UIGradient', {
        Rotation = rotation or 0;
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.2, 0.4),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(0.8, 0.4),
            NumberSequenceKeypoint.new(1, 1),
        });
        Parent = Inst;
    });
end;

-- Shimmer: animated UIGradient that loops across a Frame. Used on slider
-- fills for the "progress bar shimmer" effect. Returns the gradient so the
-- caller can Disconnect or modify if needed.
function Library:AddShimmer(Frame, period)
    local grad = Library:Create('UIGradient', {
        Rotation = 20;
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.45, 1),
            NumberSequenceKeypoint.new(0.5, 0.65),
            NumberSequenceKeypoint.new(0.55, 1),
            NumberSequenceKeypoint.new(1, 1),
        });
        Parent = Frame;
    });
    local p = period or 2.2;
    table.insert(Library.Signals, RenderStepped:Connect(function()
        local t = (tick() % p) / p;
        grad.Offset = Vector2.new(t * 2 - 1, 0); -- sweep across the frame
    end));
    return grad;
end;

-- ═══════════════════════════════════════════════════════════════════
-- Custom Font System
--
-- Download TTF files from a remote URL, cache them on disk, register them
-- as Font objects, and apply globally to every TextLabel/TextBox in the
-- menu ScreenGui. Used by :BuildFontSection to surface a font dropdown in
-- the Settings tab.
--
-- Public API:
--   Library:RegisterFont(name, url)                — download + register one font
--   Library:RegisterFontsFromRepo(baseUrl, list)   — bulk register (name → baseUrl .. name .. ".ttf")
--   Library:SetFont(name | nil)                    — apply font to everything (nil = default)
--   Library:GetActiveFont()                        — returns current Font object (never nil)
--   Library:BuildFontSection(groupbox)             — adds font dropdown to a groupbox
--
-- The default font is Library.Font (an EnumItem). Library.CurrentFont holds
-- the custom Font object (or nil). CreateLabel uses FontFace so both types
-- work without a branch.
-- ═══════════════════════════════════════════════════════════════════

Library.Fonts = {};                                     -- [name] = Font object
Library.FontFolder = 'sanyui/fonts';                    -- on-disk cache path
Library.DefaultFontFace = Font.fromEnum(Enum.Font.Code);
Library.CurrentFont = nil;                              -- nil = use DefaultFontFace

do
    -- Ensure cache folder exists. pcall: some executors lack isfolder.
    pcall(function()
        local parts = Library.FontFolder:split('/');
        local path = '';
        for i = 1, #parts do
            path = (i == 1) and parts[i] or (path .. '/' .. parts[i]);
            if not isfolder(path) then makefolder(path) end;
        end;
    end);
end;

function Library:GetActiveFont()
    return Library.CurrentFont or Library.DefaultFontFace;
end;

-- Download one TTF + register it. Writes the TTF + a small JSON family descriptor
-- to FontFolder so Roblox can resolve the custom Font via getcustomasset. Safe
-- to call for already-registered names (returns cached).
function Library:RegisterFont(name, url)
    if Library.Fonts[name] then return Library.Fonts[name] end;
    if name == 'Default' or not url then return nil end;

    local ok, fnt = pcall(function()
        local ttfPath = Library.FontFolder .. '/' .. name .. '.ttf';
        if not isfile(ttfPath) then
            writefile(ttfPath, game:HttpGet(url));
        end;
        local ttfAsset = getcustomasset(ttfPath);
        local jsonBody = '{"name":"' .. name .. '","faces":[{"name":"Regular","weight":400,"style":"normal","assetId":"' .. ttfAsset .. '"}]}';
        local jsonPath = Library.FontFolder .. '/' .. name .. '.json';
        writefile(jsonPath, jsonBody);
        return Font.new(getcustomasset(jsonPath), Enum.FontWeight.Regular);
    end);

    if ok and fnt then
        Library.Fonts[name] = fnt;
        return fnt;
    end;
    return nil;
end;

-- Bulk register from a base URL. List is either `{ 'Name1', 'Name2' }` or a
-- map `{ Name1 = 'url1', Name2 = 'url2' }`. Array form appends ".ttf" to the
-- base URL; map form uses each value as the full URL.
function Library:RegisterFontsFromRepo(baseUrl, list)
    for k, v in list do
        if type(k) == 'number' then
            Library:RegisterFont(v, baseUrl .. v .. '.ttf');
        else
            Library:RegisterFont(k, v);
        end;
    end;
end;

-- Swap active font. Passing nil restores the default. Reapplies to every
-- text instance under Library.ScreenGui.
function Library:SetFont(name)
    local newFont;
    if not name or name == 'Default' then
        newFont = nil;
    else
        newFont = Library.Fonts[name];
        if not newFont then return end;
    end;
    Library.CurrentFont = newFont;
    local face = Library:GetActiveFont();
    if Library.ScreenGui then
        for _, desc in Library.ScreenGui:GetDescendants() do
            if desc:IsA('TextLabel') or desc:IsA('TextBox') or desc:IsA('TextButton') then
                pcall(function() desc.FontFace = face end);
            end;
        end;
    end;
    -- Notify listeners (e.g. the script's ESP code) so they can re-apply to
    -- text instances that live outside ScreenGui.
    if Library.FontListeners then
        for _, cb in Library.FontListeners do
            pcall(cb, face, name);
        end;
    end;
end;

Library.FontListeners = {};
-- External code registers a callback to be notified when the user changes font.
-- Used by the script to apply the active font to ESP billboards, OOV markers, etc.
function Library:OnFontChanged(callback)
    if type(callback) == 'function' then
        table.insert(Library.FontListeners, callback);
    end;
end;

function Library:BuildFontSection(container)
    local names = { 'Default' };
    for k in Library.Fonts do table.insert(names, k) end;
    table.sort(names, function(a, b)
        if a == 'Default' then return true end;
        if b == 'Default' then return false end;
        return a < b;
    end);

    container:AddDropdown('LibraryFont', {
        Text = 'Font';
        Values = names;
        Default = 1;
        Callback = function(val)
            Library:SetFont(val);
        end;
    });
end;

function Library:CreateLabel(Properties, IsHud)
    local _Instance = Library:Create('TextLabel', {
        BackgroundTransparency = 1;
        FontFace = Library:GetActiveFont();
        TextColor3 = Library.FontColor;
        TextSize = 16;
        TextStrokeTransparency = 0;
    });

    Library:ApplyTextStroke(_Instance);

    Library:AddToRegistry(_Instance, {
        TextColor3 = 'FontColor';
    }, IsHud);

    return Library:Create(_Instance, Properties);
end;

-- Auto-apply font to newly-created TextBoxes (TextLabels go through CreateLabel).
-- Also catches any external TextLabel/TextButton that gets added to the ScreenGui.
do
    local applied = setmetatable({}, { __mode = 'k' });
    table.insert(Library.Signals, ScreenGui.DescendantAdded:Connect(function(desc)
        if applied[desc] then return end;
        if desc:IsA('TextLabel') or desc:IsA('TextBox') or desc:IsA('TextButton') then
            applied[desc] = true;
            task.defer(function()
                pcall(function() desc.FontFace = Library:GetActiveFont() end);
            end);
        end;
    end));
end;

-- Registry of every draggable frame. Each entry is { frame = … }. Used by
-- the drag logic for inter-window collision so two menu panels can't overlap.
Library.Draggables = {};

-- Clean drag implementation.
--
-- 1. MouseMovement goes through UserInputService.InputChanged (global) — the
--    frame-local signal stops firing as soon as the cursor leaves the frame
--    during fast drags.
-- 2. Position writes are COALESCED: InputChanged only stashes the latest
--    target offset, a single RenderStepped applies it once per frame. The
--    main menu has 1500+ descendants and Roblox recomputes absolute
--    positions for all of them on every parent Position write — multiple
--    writes per frame (mouse samples ~200 Hz) were the actual lag source.
-- 3. Other registered draggables are collision-checked each frame so menu
--    windows can't overlap — they snap to the nearest edge.
--
-- End-of-drag is tied to the originating Input.Changed so simultaneous
-- draggables don't cancel each other.
function Library:MakeDraggable(Frame, Cutoff)
    Frame.Active = true;

    local entry = { frame = Frame };
    table.insert(Library.Draggables, entry);

    -- AABB block against every other visible draggable.
    -- The previous version picked the "smallest push" axis, which flips the
    -- window to the opposite side of an obstacle once the cursor crosses the
    -- center — felt buggy to the user. This version instead blocks on a
    -- per-axis basis: we accept the movement on an axis only if, moving from
    -- the current Frame position to the target on just that axis, the Frame
    -- still stays out of the other window's rect. You can slide along an
    -- edge but you can't push into a window.
    local function resolveCollision(newX, newY)
        local size = Frame.AbsoluteSize;
        local w, h = size.X, size.Y;
        local curPos = Frame.AbsolutePosition;
        local curX, curY = curPos.X, curPos.Y;

        local function overlaps(x, y, oPos, oSize)
            return x < oPos.X + oSize.X and x + w > oPos.X
                and y < oPos.Y + oSize.Y and y + h > oPos.Y;
        end;

        local x, y = newX, newY;

        for _, other in ipairs(Library.Draggables) do
            if other ~= entry and other.frame and other.frame.Parent and other.frame.Visible then
                local oPos = other.frame.AbsolutePosition;
                local oSize = other.frame.AbsoluteSize;

                -- Try X move (keep current Y). If that overlaps, clamp X to
                -- the near edge of the obstacle — whichever side we started
                -- on decides whether we stop at obstacle's left or right edge.
                if overlaps(x, curY, oPos, oSize) then
                    if curX + w <= oPos.X then
                        x = oPos.X - w;
                    elseif curX >= oPos.X + oSize.X then
                        x = oPos.X + oSize.X;
                    else
                        x = curX; -- already overlapping horizontally: no-op on X
                    end;
                end;

                -- Try Y move with the possibly-clamped X.
                if overlaps(x, y, oPos, oSize) then
                    if curY + h <= oPos.Y then
                        y = oPos.Y - h;
                    elseif curY >= oPos.Y + oSize.Y then
                        y = oPos.Y + oSize.Y;
                    else
                        y = curY;
                    end;
                end;
            end;
        end;

        return x, y;
    end;

    Frame.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1
            and Input.UserInputType ~= Enum.UserInputType.Touch then
            return;
        end;

        local relY = Input.Position.Y - Frame.AbsolutePosition.Y;
        if relY > (Cutoff or 40) then return end;

        -- Normalize to pure-offset position in absolute screen space so that
        -- pendingX / pendingY match the coordinate system resolveCollision
        -- operates in (AbsolutePosition). Without this, frames with scale=1
        -- anchoring (e.g. right-edge anchored addons like ESPPreview) fed
        -- mixed scale+offset values into resolveCollision and the AABB test
        -- saw bogus coordinates — collisions silently never triggered.
        local absPos = Frame.AbsolutePosition;
        Frame.AnchorPoint = Vector2.new(0, 0);
        Frame.Position = UDim2.fromOffset(absPos.X, absPos.Y);

        local dragStart = Input.Position;
        local pendingX, pendingY = absPos.X, absPos.Y;
        local dirty = false;

        local moveConn, renderConn, endConn;

        moveConn = InputService.InputChanged:Connect(function(moveInput)
            if moveInput.UserInputType ~= Enum.UserInputType.MouseMovement
                and moveInput.UserInputType ~= Enum.UserInputType.Touch then
                return;
            end;
            -- Stash the target; the per-frame handler writes Position.
            local delta = moveInput.Position - dragStart;
            pendingX = absPos.X + delta.X;
            pendingY = absPos.Y + delta.Y;
            dirty = true;
        end);

        renderConn = RunService.RenderStepped:Connect(function()
            if not dirty then return end;
            dirty = false;
            local x, y = resolveCollision(pendingX, pendingY);
            Frame.Position = UDim2.fromOffset(x, y);
        end);

        endConn = Input.Changed:Connect(function()
            if Input.UserInputState == Enum.UserInputState.End then
                if moveConn then moveConn:Disconnect() end;
                if renderConn then renderConn:Disconnect() end;
                if endConn then endConn:Disconnect() end;
            end;
        end);
    end);
end;

function Library:AddToolTip(InfoStr, HoverInstance)
    local X, Y = Library:GetTextBounds(InfoStr, Library.Font, 14);
    local Tooltip = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor,
        BorderColor3 = Library.OutlineColor,
        BackgroundTransparency = 1,

        Size = UDim2.fromOffset(X + 5, Y + 4),
        ZIndex = 100,
        Parent = Library.ScreenGui,

        Visible = false,
    })

    local Label = Library:CreateLabel({
        Position = UDim2.fromOffset(3, 1),
        Size = UDim2.fromOffset(X, Y);
        TextSize = 14;
        Text = InfoStr,
        TextColor3 = Library.FontColor,
        TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = Tooltip.ZIndex + 1,

        Parent = Tooltip;
    });

    Library:AddToRegistry(Tooltip, {
        BackgroundColor3 = 'MainColor';
        BorderColor3 = 'OutlineColor';
    });

    Library:AddToRegistry(Label, {
        TextColor3 = 'FontColor',
    });

    local IsHovering = false;
    local showToken = 0;
    local fadeInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

    HoverInstance.MouseEnter:Connect(function()
        if Library:MouseIsOverOpenedFrame() then
            return
        end

        IsHovering = true
        showToken = showToken + 1
        local myToken = showToken

        -- 300 ms delay so tooltips don't flash while the cursor is just passing through.
        task.delay(0.3, function()
            if not IsHovering or myToken ~= showToken then return end

            Tooltip.Position = UDim2.fromOffset(Mouse.X + 15, Mouse.Y + 12)
            Tooltip.BackgroundTransparency = 1
            Label.TextTransparency = 1
            Tooltip.Visible = true

            TweenService:Create(Tooltip, fadeInfo, { BackgroundTransparency = 0 }):Play()
            TweenService:Create(Label, fadeInfo, { TextTransparency = 0 }):Play()

            while IsHovering and myToken == showToken do
                RunService.Heartbeat:Wait()
                Tooltip.Position = UDim2.fromOffset(Mouse.X + 15, Mouse.Y + 12)
            end
        end)
    end)

    HoverInstance.MouseLeave:Connect(function()
        IsHovering = false
        showToken = showToken + 1
        local myToken = showToken

        local fadeOut = TweenService:Create(Tooltip, fadeInfo, { BackgroundTransparency = 1 })
        TweenService:Create(Label, fadeInfo, { TextTransparency = 1 }):Play()
        fadeOut:Play()
        fadeOut.Completed:Connect(function()
            if myToken == showToken then
                Tooltip.Visible = false
            end
        end)
    end)
end

-- Atlanta-style smooth hover. Instead of instant color swap, color properties
-- tween toward their hover/rest targets via TweenService. The registry is
-- updated with the symbolic color name so theme swaps still work.
--
-- `Properties` / `PropertiesDefault` map property name → either a string
-- (looked up on Library, e.g. "AccentColor") or a Color3 literal.
function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
    local fadeInfo = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);

    local function resolveGoals(Props)
        local Reg = Library.RegistryMap[Instance];
        local goals = {};
        for Property, ColorIdx in next, Props do
            local resolved = Library[ColorIdx] or ColorIdx;
            goals[Property] = resolved;
            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
        return goals;
    end;

    HighlightInstance.MouseEnter:Connect(function()
        TweenService:Create(Instance, fadeInfo, resolveGoals(Properties)):Play();
    end);

    HighlightInstance.MouseLeave:Connect(function()
        TweenService:Create(Instance, fadeInfo, resolveGoals(PropertiesDefault)):Play();
    end);
end;

function Library:MouseIsOverOpenedFrame()
    for Frame, _ in next, Library.OpenedFrames do
        local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

        if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
            and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

            return true;
        end;
    end;
end;

function Library:IsMouseOverFrame(Frame)
    local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

    if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
        and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

        return true;
    end;
end;

function Library:UpdateDependencyBoxes()
    for _, Depbox in next, Library.DependencyBoxes do
        Depbox:Update();
    end;
end;

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
    return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB;
end;

function Library:GetTextBounds(Text, Font, Size, Resolution)
    -- Resolve to a Font INSTANCE — the library auto-applies
    -- Library:GetActiveFont() to every TextLabel under ScreenGui (see
    -- SetFont + OnFontChanged), so width measurements should track the
    -- active face. Passing the legacy Library.Font (Enum.Font.Code) into
    -- GetTextSize would undersize labels rendered with custom fonts whose
    -- glyphs are wider, leaving empty padding on the right side of
    -- notifications, watermarks, and any other auto-sized container that
    -- relies on these bounds. The sole API that accepts a Font instance is
    -- GetTextBoundsAsync; GetTextSize only takes Enum.Font.
    local face
    if typeof(Font) == 'Font' then
        face = Font
    else
        face = Library:GetActiveFont()
    end

    -- GetTextBoundsAsync yields once per font asset to load; subsequent
    -- calls hit the engine cache. Wrapped in pcall so a load failure
    -- (invalid asset, restricted thread, etc.) falls back to the legacy
    -- GetTextSize path instead of returning nil to the caller.
    local ok, bounds = pcall(function()
        local params = Instance.new('GetTextBoundsParams')
        params.Text = Text
        params.Font = face
        params.Size = Size
        params.Width = (Resolution or Vector2.new(1920, 1080)).X
        return TextService:GetTextBoundsAsync(params)
    end)
    if ok and bounds then return bounds.X, bounds.Y end

    -- Fallback: legacy Enum.Font path. Less accurate for custom fonts but
    -- guaranteed not to error or return nil.
    local enumFont = (typeof(Font) == 'EnumItem') and Font or Library.Font
    local b = TextService:GetTextSize(Text, Size, enumFont,
        Resolution or Vector2.new(1920, 1080))
    return b.X, b.Y
end;

function Library:GetDarkerColor(Color)
    local H, S, V = Color3.toHSV(Color);
    return Color3.fromHSV(H, S, V / 1.5);
end;
Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);

function Library:AddToRegistry(Instance, Properties, IsHud)
    local Idx = #Library.Registry + 1;
    local Data = {
        Instance = Instance;
        Properties = Properties;
        Idx = Idx;
    };

    table.insert(Library.Registry, Data);
    Library.RegistryMap[Instance] = Data;

    if IsHud then
        table.insert(Library.HudRegistry, Data);
    end;
end;

function Library:RemoveFromRegistry(Instance)
    local Data = Library.RegistryMap[Instance];

    if Data then
        for Idx = #Library.Registry, 1, -1 do
            if Library.Registry[Idx] == Data then
                table.remove(Library.Registry, Idx);
            end;
        end;

        for Idx = #Library.HudRegistry, 1, -1 do
            if Library.HudRegistry[Idx] == Data then
                table.remove(Library.HudRegistry, Idx);
            end;
        end;

        Library.RegistryMap[Instance] = nil;
    end;
end;

function Library:UpdateColorsUsingRegistry()
    -- TODO: Could have an 'active' list of objects
    -- where the active list only contains Visible objects.

    -- IMPL: Could setup .Changed events on the AddToRegistry function
    -- that listens for the 'Visible' propert being changed.
    -- Visible: true => Add to active list, and call UpdateColors function
    -- Visible: false => Remove from active list.

    -- The above would be especially efficient for a rainbow menu color or live color-changing.

    for Idx, Object in next, Library.Registry do
        for Property, ColorIdx in next, Object.Properties do
            if type(ColorIdx) == 'string' then
                Object.Instance[Property] = Library[ColorIdx];
            elseif type(ColorIdx) == 'function' then
                Object.Instance[Property] = ColorIdx()
            end
        end;
    end;
end;

function Library:GiveSignal(Signal)
    -- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
    table.insert(Library.Signals, Signal)
end

function Library:Unload()
    -- Unload all of the signals
    for Idx = #Library.Signals, 1, -1 do
        local Connection = table.remove(Library.Signals, Idx)
        Connection:Disconnect()
    end

     -- Call our unload callback, maybe to undo some hooks etc
    if Library.OnUnload then
        Library.OnUnload()
    end

    -- Clean up the menu blur so Lighting isn't left modified after unload.
    if Library.MenuBlur then
        pcall(Library.MenuBlur.Destroy, Library.MenuBlur)
        Library.MenuBlur = nil
    end

    ScreenGui:Destroy()
end

function Library:OnUnload(Callback)
    Library.OnUnload = Callback
end

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
    if Library.RegistryMap[Instance] then
        Library:RemoveFromRegistry(Instance);
    end;
end))

local BaseAddons = {};

do
    local Funcs = {};

    function Funcs:AddColorPicker(Idx, Info)
        local ToggleLabel = self.TextLabel;
        -- local Container = self.Container;

        assert(Info.Default, 'AddColorPicker: Missing default value.');

        local ColorPicker = {
            Value = Info.Default;
            Transparency = Info.Transparency or 0;
            Type = 'ColorPicker';
            Title = type(Info.Title) == 'string' and Info.Title or 'Color picker',
            Callback = Info.Callback or function(Color) end;
        };

        function ColorPicker:SetHSVFromRGB(Color)
            local H, S, V = Color3.toHSV(Color);

            ColorPicker.Hue = H;
            ColorPicker.Sat = S;
            ColorPicker.Vib = V;
        end;

        ColorPicker:SetHSVFromRGB(ColorPicker.Value);

        local DisplayFrame = Library:Create('Frame', {
            BackgroundColor3 = ColorPicker.Value;
            BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(0, 28, 0, 14);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        local CheckerFrame = Library:Create('Frame', {
            BorderSizePixel = 0;
            Size = UDim2.new(0, 27, 0, 13);
            ZIndex = 5;
            BackgroundColor3 = Color3.fromRGB(40, 40, 40);
            Visible = not not Info.Transparency;
            Parent = DisplayFrame;
        });

        -- 1/16/23
        -- Rewrote this to be placed inside the Library ScreenGui
        -- There was some issue which caused RelativeOffset to be way off
        -- Thus the color picker would never show

        local PickerFrameOuter = Library:Create('Frame', {
            Name = 'Color';
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18),
            Size = UDim2.fromOffset(230, Info.Transparency and 271 or 253);
            Visible = false;
            ZIndex = 15;
            Parent = ScreenGui,
        });

        local function UpdatePickerPosition()
            PickerFrameOuter.Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 18);
        end;

        DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(UpdatePickerPosition);
        DisplayFrame:GetPropertyChangedSignal('AbsoluteSize'):Connect(UpdatePickerPosition);

        -- Per-frame tracking while open (ScrollingFrame resize causes 1-frame lag in AbsolutePosition signals)
        local PickerTrackConn = nil;

        local PickerFrameInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 16;
            Parent = PickerFrameOuter;
        });

        local Highlight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, 1);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local SatVibMapOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.new(0, 4, 0, 25);
            Size = UDim2.new(0, 200, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local SatVibMapInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Parent = SatVibMapOuter;
        });

        local SatVibMap = Library:Create('Frame', {
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            BackgroundColor3 = Color3.new(1, 0, 0);
            Parent = SatVibMapInner;
        });

        Library:Create('UIGradient', {
            Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
                ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1))
            });
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 1)
            });
            Parent = SatVibMap;
        });

        local SatVibOverlay = Library:Create('Frame', {
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            BackgroundColor3 = Color3.new(0, 0, 0);
            Parent = SatVibMap;
        });

        Library:Create('UIGradient', {
            Rotation = 90;
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(1, 0)
            });
            Parent = SatVibOverlay;
        });

        local CursorOuter = Library:Create('Frame', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Size = UDim2.new(0, 6, 0, 6);
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderSizePixel = 0;
            ZIndex = 19;
            Parent = SatVibMap;
        });

        local CursorInner = Library:Create('Frame', {
            Size = UDim2.new(0, 4, 0, 4);
            Position = UDim2.new(0, 1, 0, 1);
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderSizePixel = 0;
            ZIndex = 20;
            Parent = CursorOuter;
        })

        local HueSelectorOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.new(0, 208, 0, 25);
            Size = UDim2.new(0, 15, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local HueSelectorInner = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Parent = HueSelectorOuter;
        });

        local HueCursor = Library:Create('Frame', { 
            BackgroundColor3 = Color3.new(1, 1, 1);
            AnchorPoint = Vector2.new(0, 0.5);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, 0, 0, 1);
            ZIndex = 18;
            Parent = HueSelectorInner;
        });

        local HueBoxOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(4, 228),
            Size = UDim2.new(0.5, -6, 0, 20),
            ZIndex = 18,
            Parent = PickerFrameInner;
        });

        local HueBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18,
            Parent = HueBoxOuter;
        });

        local HueBox = Library:Create('TextBox', {
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);
            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(100, 100, 100);
            PlaceholderText = 'Hex color',
            Text = '#FFFFFF',
            TextColor3 = Library.FontColor;
            TextSize = 14;
            TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 20,
            Parent = HueBoxInner;
        });

        Library:ApplyTextStroke(HueBox);

        local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
            Position = UDim2.new(0.5, 2, 0, 228),
            Size = UDim2.new(0.5, -6, 0, 20),
            Parent = PickerFrameInner
        });

        local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild('TextBox'), {
            Text = '255, 255, 255',
            PlaceholderText = 'RGB color',
            TextColor3 = Library.FontColor
        });

        local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor;
        
        if Info.Transparency then 
            TransparencyBoxOuter = Library:Create('Frame', {
                BorderColor3 = Color3.new(0, 0, 0);
                Position = UDim2.fromOffset(4, 251);
                Size = UDim2.new(1, -8, 0, 15);
                ZIndex = 19;
                Parent = PickerFrameInner;
            });

            TransparencyBoxInner = Library:Create('Frame', {
                BackgroundColor3 = ColorPicker.Value;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 19;
                Parent = TransparencyBoxOuter;
            });

            Library:AddToRegistry(TransparencyBoxInner, { BorderColor3 = 'OutlineColor' });

            Library:Create('UIGradient', {
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.8),
                    NumberSequenceKeypoint.new(1, 0)
                });
                Parent = TransparencyBoxInner;
            });

            TransparencyCursor = Library:Create('Frame', { 
                BackgroundColor3 = Color3.new(1, 1, 1);
                AnchorPoint = Vector2.new(0.5, 0);
                BorderColor3 = Color3.new(0, 0, 0);
                Size = UDim2.new(0, 1, 1, 0);
                ZIndex = 21;
                Parent = TransparencyBoxInner;
            });
        end;

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 14);
            Position = UDim2.fromOffset(5, 5);
            TextXAlignment = Enum.TextXAlignment.Left;
            TextSize = 14;
            Text = ColorPicker.Title,--Info.Default;
            TextWrapped = false;
            ZIndex = 16;
            Parent = PickerFrameInner;
        });


        local ContextMenu = {}
        do
            ContextMenu.Options = {}
            ContextMenu.Container = Library:Create('Frame', {
                BorderColor3 = Color3.new(),
                ZIndex = 14,

                Visible = false,
                Parent = ScreenGui
            })

            ContextMenu.Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.fromScale(1, 1);
                ZIndex = 15;
                Parent = ContextMenu.Container;
            });

            Library:Create('UIListLayout', {
                Name = 'Layout',
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = ContextMenu.Inner;
            });

            Library:Create('UIPadding', {
                Name = 'Padding',
                PaddingLeft = UDim.new(0, 4),
                Parent = ContextMenu.Inner,
            });

            local function updateMenuPosition()
                ContextMenu.Container.Position = UDim2.fromOffset(
                    (DisplayFrame.AbsolutePosition.X + DisplayFrame.AbsoluteSize.X) + 4,
                    DisplayFrame.AbsolutePosition.Y + 1
                )
            end

            local function updateMenuSize()
                local menuWidth = 60
                for i, label in next, ContextMenu.Inner:GetChildren() do
                    if label:IsA('TextLabel') then
                        menuWidth = math.max(menuWidth, label.TextBounds.X)
                    end
                end

                ContextMenu.Container.Size = UDim2.fromOffset(
                    menuWidth + 8,
                    ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 4
                )
            end

            DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(updateMenuPosition)
            ContextMenu.Inner.Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(updateMenuSize)

            task.spawn(updateMenuPosition)
            task.spawn(updateMenuSize)

            Library:AddToRegistry(ContextMenu.Inner, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            function ContextMenu:Show()
                self.Container.Visible = true
            end

            function ContextMenu:Hide()
                self.Container.Visible = false
            end

            function ContextMenu:AddOption(Str, Callback)
                if type(Callback) ~= 'function' then
                    Callback = function() end
                end

                local Button = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, 0, 0, 15);
                    TextSize = 13;
                    Text = Str;
                    ZIndex = 16;
                    Parent = self.Inner;
                    TextXAlignment = Enum.TextXAlignment.Left,
                });

                Library:OnHighlight(Button, Button, 
                    { TextColor3 = 'AccentColor' },
                    { TextColor3 = 'FontColor' }
                );

                Button.InputBegan:Connect(function(Input)
                    if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                        return
                    end

                    Callback()
                end)
            end

            ContextMenu:AddOption('Copy color', function()
                Library.ColorClipboard = ColorPicker.Value
                Library:Notify('Copied color!', 2)
            end)

            ContextMenu:AddOption('Paste color', function()
                if not Library.ColorClipboard then
                    return Library:Notify('You have not copied a color!', 2)
                end
                ColorPicker:SetValueRGB(Library.ColorClipboard)
            end)


            ContextMenu:AddOption('Copy HEX', function()
                pcall(setclipboard, ColorPicker.Value:ToHex())
                Library:Notify('Copied hex code to clipboard!', 2)
            end)

            ContextMenu:AddOption('Copy RGB', function()
                pcall(setclipboard, table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', '))
                Library:Notify('Copied RGB values to clipboard!', 2)
            end)

        end

        Library:AddToRegistry(PickerFrameInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(Highlight, { BackgroundColor3 = 'AccentColor'; });
        Library:AddToRegistry(SatVibMapInner, { BackgroundColor3 = 'BackgroundColor'; BorderColor3 = 'OutlineColor'; });

        Library:AddToRegistry(HueBoxInner, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = 'MainColor'; BorderColor3 = 'OutlineColor'; });
        Library:AddToRegistry(RgbBox, { TextColor3 = 'FontColor', });
        Library:AddToRegistry(HueBox, { TextColor3 = 'FontColor', });

        local SequenceTable = {};

        for Hue = 0, 1, 0.1 do
            table.insert(SequenceTable, ColorSequenceKeypoint.new(Hue, Color3.fromHSV(Hue, 1, 1)));
        end;

        local HueSelectorGradient = Library:Create('UIGradient', {
            Color = ColorSequence.new(SequenceTable);
            Rotation = 90;
            Parent = HueSelectorInner;
        });

        HueBox.FocusLost:Connect(function(enter)
            if enter then
                local success, result = pcall(Color3.fromHex, HueBox.Text)
                if success and typeof(result) == 'Color3' then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result)
                end
            end

            ColorPicker:Display()
        end)

        RgbBox.FocusLost:Connect(function(enter)
            if enter then
                local r, g, b = RgbBox.Text:match('(%d+),%s*(%d+),%s*(%d+)')
                if r and g and b then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
                end
            end

            ColorPicker:Display()
        end)

        function ColorPicker:Display()
            ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib);
            SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1);

            Library:Create(DisplayFrame, {
                BackgroundColor3 = ColorPicker.Value;
                BackgroundTransparency = ColorPicker.Transparency;
                BorderColor3 = Library:GetDarkerColor(ColorPicker.Value);
            });

            if TransparencyBoxInner then
                TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value;
                TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0, 0);
            end;

            CursorOuter.Position = UDim2.new(ColorPicker.Sat, 0, 1 - ColorPicker.Vib, 0);
            HueCursor.Position = UDim2.new(0, 0, ColorPicker.Hue, 0);

            HueBox.Text = '#' .. ColorPicker.Value:ToHex()
            RgbBox.Text = table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', ')

            Library:SafeCallback(ColorPicker.Callback, ColorPicker.Value);
            Library:SafeCallback(ColorPicker.Changed, ColorPicker.Value);
        end;

        function ColorPicker:OnChanged(Func)
            ColorPicker.Changed = Func;
            Func(ColorPicker.Value)
        end;

        function ColorPicker:Show()
            for Frame, Val in next, Library.OpenedFrames do
                if Frame.Name == 'Color' then
                    Frame.Visible = false;
                    Library.OpenedFrames[Frame] = nil;
                end;
            end;

            UpdatePickerPosition();
            PickerFrameOuter.Visible = true;
            Library.OpenedFrames[PickerFrameOuter] = true;

            -- Track position every frame while open so resize/scroll is always correct
            if not PickerTrackConn then
                PickerTrackConn = RenderStepped:Connect(function()
                    if not PickerFrameOuter.Parent then
                        PickerTrackConn:Disconnect();
                        PickerTrackConn = nil;
                        return;
                    end;
                    UpdatePickerPosition();
                end);
            end;
        end;

        function ColorPicker:Hide()
            PickerFrameOuter.Visible = false;
            Library.OpenedFrames[PickerFrameOuter] = nil;
            if PickerTrackConn then
                PickerTrackConn:Disconnect();
                PickerTrackConn = nil;
            end;
        end;

        function ColorPicker:SetValue(HSV, Transparency)
            local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3]);

            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        function ColorPicker:SetValueRGB(Color, Transparency)
            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        SatVibMap.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    local MinX = SatVibMap.AbsolutePosition.X;
                    local MaxX = MinX + SatVibMap.AbsoluteSize.X;
                    local MouseX = math.clamp(Mouse.X, MinX, MaxX);

                    local MinY = SatVibMap.AbsolutePosition.Y;
                    local MaxY = MinY + SatVibMap.AbsoluteSize.Y;
                    local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

                    ColorPicker.Sat = (MouseX - MinX) / (MaxX - MinX);
                    ColorPicker.Vib = 1 - ((MouseY - MinY) / (MaxY - MinY));
                    ColorPicker:Display();

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        HueSelectorInner.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    local MinY = HueSelectorInner.AbsolutePosition.Y;
                    local MaxY = MinY + HueSelectorInner.AbsoluteSize.Y;
                    local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

                    ColorPicker.Hue = ((MouseY - MinY) / (MaxY - MinY));
                    ColorPicker:Display();

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        DisplayFrame.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                if PickerFrameOuter.Visible then
                    ColorPicker:Hide()
                else
                    ContextMenu:Hide()
                    ColorPicker:Show()
                end;
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ContextMenu:Show()
                ColorPicker:Hide()
            end
        end);

        if TransparencyBoxInner then
            TransparencyBoxInner.InputBegan:Connect(function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                    while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                        local MinX = TransparencyBoxInner.AbsolutePosition.X;
                        local MaxX = MinX + TransparencyBoxInner.AbsoluteSize.X;
                        local MouseX = math.clamp(Mouse.X, MinX, MaxX);

                        ColorPicker.Transparency = 1 - ((MouseX - MinX) / (MaxX - MinX));

                        ColorPicker:Display();

                        RenderStepped:Wait();
                    end;

                    Library:AttemptSave();
                end;
            end);
        end;

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    ColorPicker:Hide();
                end;

                if not Library:IsMouseOverFrame(ContextMenu.Container) then
                    ContextMenu:Hide()
                end
            end;

            if Input.UserInputType == Enum.UserInputType.MouseButton2 and ContextMenu.Container.Visible then
                if not Library:IsMouseOverFrame(ContextMenu.Container) and not Library:IsMouseOverFrame(DisplayFrame) then
                    ContextMenu:Hide()
                end
            end
        end))

        ColorPicker:Display();
        ColorPicker.DisplayFrame = DisplayFrame

        Options[Idx] = ColorPicker;

        return self;
    end;

    function Funcs:AddKeyPicker(Idx, Info)
        local ParentObj = self;
        local ToggleLabel = self.TextLabel;
        local Container = self.Container;

        assert(Info.Default, 'AddKeyPicker: Missing default value.');

        local KeyPicker = {
            Value = Info.Default;
            Toggled = false;
            Mode = Info.Mode or 'Toggle'; -- Always, Toggle, Hold
            Type = 'KeyPicker';
            Callback = Info.Callback or function(Value) end;
            ChangedCallback = Info.ChangedCallback or function(New) end;

            SyncToggleState = Info.SyncToggleState or false;
        };

        if KeyPicker.SyncToggleState then
            Info.Modes = { 'Toggle' }
            Info.Mode = 'Toggle'
        end

        -- Pill-style keybind badge: rounded corners + subtle accent tint on the outer ring.
        local PickOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderSizePixel = 0;
            Size = UDim2.new(0, 30, 0, 16);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        Library:Create('UICorner', {
            CornerRadius = UDim.new(0, 4);
            Parent = PickOuter;
        });

        local PickInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            BorderSizePixel = 0;
            Size = UDim2.new(1, -2, 1, -2);
            Position = UDim2.fromOffset(1, 1);
            ZIndex = 7;
            Parent = PickOuter;
        });

        Library:Create('UICorner', {
            CornerRadius = UDim.new(0, 3);
            Parent = PickInner;
        });

        Library:AddToRegistry(PickInner, {
            BackgroundColor3 = 'BackgroundColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 13;
            Text = Info.Default;
            TextWrapped = true;
            ZIndex = 8;
            Parent = PickInner;
        });

        local ModeSelectOuter = Library:Create('Frame', {
            BorderColor3 = Color3.new(0, 0, 0);
            Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
            Size = UDim2.new(0, 60, 0, 45 + 2);
            Visible = false;
            ZIndex = 14;
            Parent = ScreenGui;
        });

        local function UpdateModeSelectPosition()
            ModeSelectOuter.Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 4, ToggleLabel.AbsolutePosition.Y + 1);
        end;

        ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(UpdateModeSelectPosition);
        ToggleLabel:GetPropertyChangedSignal('AbsoluteSize'):Connect(UpdateModeSelectPosition);

        local ModeSelectInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 15;
            Parent = ModeSelectOuter;
        });

        Library:AddToRegistry(ModeSelectInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ModeSelectInner;
        });

        local ContainerLabel = Library:CreateLabel({
            TextXAlignment = Enum.TextXAlignment.Left;
            Size = UDim2.new(1, 0, 0, 18);
            TextSize = 13;
            Visible = false;
            ZIndex = 110;
            Parent = Library.KeybindContainer;
        },  true);

        local Modes = Info.Modes or { 'Always', 'Toggle', 'Hold' };
        local ModeButtons = {};

        for Idx, Mode in next, Modes do
            local ModeButton = {};

            local Label = Library:CreateLabel({
                Active = false;
                Size = UDim2.new(1, 0, 0, 15);
                TextSize = 13;
                Text = Mode;
                ZIndex = 16;
                Parent = ModeSelectInner;
            });

            function ModeButton:Select()
                for _, Button in next, ModeButtons do
                    Button:Deselect();
                end;

                KeyPicker.Mode = Mode;

                Label.TextColor3 = Library.AccentColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';

                ModeSelectOuter.Visible = false;
            end;

            function ModeButton:Deselect()
                KeyPicker.Mode = nil;

                Label.TextColor3 = Library.FontColor;
                Library.RegistryMap[Label].Properties.TextColor3 = 'FontColor';
            end;

            Label.InputBegan:Connect(function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                    ModeButton:Select();
                    Library:AttemptSave();
                end;
            end);

            if Mode == KeyPicker.Mode then
                ModeButton:Select();
            end;

            ModeButtons[Mode] = ModeButton;
        end;

        function KeyPicker:Update()
            if Info.NoUI then
                return;
            end;

            local State = KeyPicker:GetState();

            ContainerLabel.Text = string.format('[%s] %s (%s)', KeyPicker.Value, Info.Text, KeyPicker.Mode);

            -- Visible only while the bind is "active": Hold mode = key is
            -- held, Toggle mode = toggle is on, Always mode = always.
            -- GetState() already encodes that. InputBegan/InputEnded both
            -- call Update so Hold-mode visibility flips live with keypress.
            -- Empty HUD collapses to just the title bar (size recompute
            -- below) — matches the requested minimal look when nothing's
            -- active.
            ContainerLabel.Visible = State;
            ContainerLabel.TextColor3 = State and Library.AccentColor or Library.FontColor;

            Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and 'AccentColor' or 'FontColor';

            local YSize = 0
            local XSize = 0

            for _, Label in next, Library.KeybindContainer:GetChildren() do
                if Label:IsA('TextLabel') and Label.Visible then
                    YSize = YSize + 18;
                    if (Label.TextBounds.X > XSize) then
                        XSize = Label.TextBounds.X
                    end
                end;
            end;

            Library.KeybindFrame.Size = UDim2.new(0, math.max(XSize + 16, 180), 0, YSize + 28)
        end;

        function KeyPicker:GetState()
            if KeyPicker.Mode == 'Always' then
                return true;
            elseif KeyPicker.Mode == 'Hold' then
                if KeyPicker.Value == 'None' then
                    return false;
                end

                local Key = KeyPicker.Value;

                if Key == 'MB1' or Key == 'MB2' then
                    return Key == 'MB1' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                        or Key == 'MB2' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2);
                else
                    return InputService:IsKeyDown(Enum.KeyCode[KeyPicker.Value]);
                end;
            else
                return KeyPicker.Toggled;
            end;
        end;

        function KeyPicker:SetValue(Data)
            local Key, Mode = Data[1], Data[2];
            DisplayLabel.Text = Key;
            KeyPicker.Value = Key;
            ModeButtons[Mode]:Select();
            KeyPicker:Update();
        end;

        function KeyPicker:OnClick(Callback)
            KeyPicker.Clicked = Callback
        end

        function KeyPicker:OnChanged(Callback)
            KeyPicker.Changed = Callback
            Callback(KeyPicker.Value)
        end

        if ParentObj.Addons then
            table.insert(ParentObj.Addons, KeyPicker)
        end

        function KeyPicker:DoClick()
            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                ParentObj:SetValue(not ParentObj.Value)
            end

            Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
            Library:SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
        end

        local Picking = false;

        PickOuter.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                Picking = true;

                DisplayLabel.Text = '';

                local Break;
                local Text = '';

                task.spawn(function()
                    while (not Break) do
                        if Text == '...' then
                            Text = '';
                        end;

                        Text = Text .. '.';
                        DisplayLabel.Text = Text;

                        task.wait(0.4);
                    end;
                end);

                task.wait(0.2);

                local Event;
                Event = InputService.InputBegan:Connect(function(Input)
                    local Key;

                    if Input.UserInputType == Enum.UserInputType.Keyboard then
                        Key = Input.KeyCode.Name;
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
                        Key = 'MB1';
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
                        Key = 'MB2';
                    end;

                    Break = true;
                    Picking = false;

                    DisplayLabel.Text = Key;
                    KeyPicker.Value = Key;

                    Library:SafeCallback(KeyPicker.ChangedCallback, Input.KeyCode or Input.UserInputType)
                    Library:SafeCallback(KeyPicker.Changed, Input.KeyCode or Input.UserInputType)

                    Library:AttemptSave();

                    Event:Disconnect();
                end);
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ModeSelectOuter.Visible = true;
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if (not Picking) then
                if KeyPicker.Mode == 'Toggle' then
                    local Key = KeyPicker.Value;

                    if Key == 'MB1' or Key == 'MB2' then
                        if Key == 'MB1' and Input.UserInputType == Enum.UserInputType.MouseButton1
                        or Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2 then
                            KeyPicker.Toggled = not KeyPicker.Toggled
                            KeyPicker:DoClick()
                        end;
                    elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                        if Input.KeyCode.Name == Key then
                            KeyPicker.Toggled = not KeyPicker.Toggled;
                            KeyPicker:DoClick()
                        end;
                    end;
                end;

                KeyPicker:Update();
            end;

            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    ModeSelectOuter.Visible = false;
                end;
            end;
        end))

        Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
            if (not Picking) then
                KeyPicker:Update();
            end;
        end))

        KeyPicker:Update();

        Options[Idx] = KeyPicker;

        return self;
    end;

    BaseAddons.__index = Funcs;
    BaseAddons.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

local BaseGroupbox = {};

do
    local Funcs = {};

    function Funcs:AddBlank(Size)
        local Groupbox = self;
        local Container = Groupbox.Container;

        Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, Size);
            ZIndex = 1;
            Parent = Container;
        });
    end;

    function Funcs:AddLabel(Text, DoesWrap)
        local Label = {};

        local Groupbox = self;
        local Container = Groupbox.Container;

        local TextLabel = Library:CreateLabel({
            Size = UDim2.new(1, -4, 0, 15);
            TextSize = 14;
            Text = Text;
            TextWrapped = DoesWrap or false,
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        if DoesWrap then
            local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
            TextLabel.Size = UDim2.new(1, -4, 0, Y)
        else
            Library:Create('UIListLayout', {
                Padding = UDim.new(0, 4);
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Right;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TextLabel;
            });
        end

        Label.TextLabel = TextLabel;
        Label.Container = Container;

        function Label:SetText(Text)
            TextLabel.Text = Text

            if DoesWrap then
                local Y = select(2, Library:GetTextBounds(Text, Library.Font, 14, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
                TextLabel.Size = UDim2.new(1, -4, 0, Y)
            end

            Groupbox:Resize();
        end

        if (not DoesWrap) then
            setmetatable(Label, BaseAddons);
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Label;
    end;

    function Funcs:AddButton(...)
        -- TODO: Eventually redo this
        local Button = {};
        local function ProcessButtonParams(Class, Obj, ...)
            local Props = select(1, ...)
            if type(Props) == 'table' then
                Obj.Text = Props.Text
                Obj.Func = Props.Func
                Obj.DoubleClick = Props.DoubleClick
                Obj.Tooltip = Props.Tooltip
            else
                Obj.Text = select(1, ...)
                Obj.Func = select(2, ...)
            end

            assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
        end

        ProcessButtonParams('Button', Button, ...)

        local Groupbox = self;
        local Container = Groupbox.Container;

        local function CreateBaseButton(Button)
            local Outer = Library:Create('Frame', {
                BackgroundColor3 = Color3.new(0, 0, 0);
                BorderColor3 = Color3.new(0, 0, 0);
                Size = UDim2.new(1, -4, 0, 20);
                ZIndex = 5;
            });

            local Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderColor3 = Library.OutlineColor;
                BorderMode = Enum.BorderMode.Inset;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 6;
                Parent = Outer;
            });

            local Label = Library:CreateLabel({
                Size = UDim2.new(1, 0, 1, 0);
                TextSize = 14;
                Text = Button.Text;
                ZIndex = 6;
                Parent = Inner;
            });

            Library:AddToRegistry(Outer, {
                BorderColor3 = 'Black';
            });

            Library:AddToRegistry(Inner, {
                BackgroundColor3 = 'BackgroundColor';
                BorderColor3 = 'OutlineColor';
            });

            Library:ApplyGradient(Inner);

            Library:OnHighlight(Outer, Outer,
                { BorderColor3 = 'AccentColor' },
                { BorderColor3 = 'Black' }
            );

            Library:AddRipple(Inner, Library.AccentColor);

            return Outer, Inner, Label
        end

        local function InitEvents(Button)
            local function WaitForEvent(event, timeout, validator)
                local bindable = Instance.new('BindableEvent')
                local connection = event:Once(function(...)

                    if type(validator) == 'function' and validator(...) then
                        bindable:Fire(true)
                    else
                        bindable:Fire(false)
                    end
                end)
                task.delay(timeout, function()
                    connection:disconnect()
                    bindable:Fire(false)
                end)
                return bindable.Event:Wait()
            end

            local function ValidateClick(Input)
                if Library:MouseIsOverOpenedFrame() then
                    return false
                end

                if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                    return false
                end

                return true
            end

            Button.Outer.InputBegan:Connect(function(Input)
                if not ValidateClick(Input) then return end
                if Button.Locked then return end

                if Button.DoubleClick then
                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'AccentColor' })

                    Button.Label.TextColor3 = Library.AccentColor
                    Button.Label.Text = 'Are you sure?'
                    Button.Locked = true

                    local clicked = WaitForEvent(Button.Outer.InputBegan, 0.5, ValidateClick)

                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'FontColor' })

                    Button.Label.TextColor3 = Library.FontColor
                    Button.Label.Text = Button.Text
                    task.defer(rawset, Button, 'Locked', false)

                    if clicked then
                        Library:SafeCallback(Button.Func)
                    end

                    return
                end

                Library:SafeCallback(Button.Func);
            end)
        end

        Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
        Button.Outer.Parent = Container

        InitEvents(Button)

        function Button:AddTooltip(tooltip)
            if type(tooltip) == 'string' then
                Library:AddToolTip(tooltip, self.Outer)
            end
            return self
        end


        function Button:AddButton(...)
            local SubButton = {}

            ProcessButtonParams('SubButton', SubButton, ...)

            self.Outer.Size = UDim2.new(0.5, -2, 0, 20)

            SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)

            SubButton.Outer.Position = UDim2.new(1, 3, 0, 0)
            SubButton.Outer.Size = UDim2.new(1, -3, 1, 0)
            SubButton.Outer.Parent = self.Outer

            function SubButton:AddTooltip(tooltip)
                if type(tooltip) == 'string' then
                    Library:AddToolTip(tooltip, self.Outer)
                end
                return SubButton
            end

            if type(SubButton.Tooltip) == 'string' then
                SubButton:AddTooltip(SubButton.Tooltip)
            end

            InitEvents(SubButton)
            return SubButton
        end

        if type(Button.Tooltip) == 'string' then
            Button:AddTooltip(Button.Tooltip)
        end

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        return Button;
    end;

    function Funcs:AddDivider()
        local Groupbox = self;
        local Container = self.Container

        local Divider = {
            Type = 'Divider',
        }

        Groupbox:AddBlank(4);
        local DividerOuter = Library:Create('Frame', {
            BackgroundColor3 = Library.OutlineColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, -4, 0, 1);
            ZIndex = 5;
            Parent = Container;
        });

        local DividerInner = DividerOuter; -- kept for compatibility

        Library:AddToRegistry(DividerOuter, {
            BackgroundColor3 = 'OutlineColor';
        });

        -- Symmetric fade — divider edges melt into the groupbox instead of cutting hard.
        Library:ApplyDoubleFade(DividerOuter, 90);

        Groupbox:AddBlank(4);
        Groupbox:Resize();
    end

    function Funcs:AddInput(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Textbox = {
            Value = Info.Default or '';
            Numeric = Info.Numeric or false;
            Finished = Info.Finished or false;
            Type = 'Input';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local InputLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 15);
            TextSize = 14;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        Groupbox:AddBlank(1);

        local TextBoxOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Container;
        });

        local TextBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = TextBoxOuter;
        });

        Library:AddToRegistry(TextBoxInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:ApplyGradient(TextBoxInner);

        Library:OnHighlight(TextBoxOuter, TextBoxOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, TextBoxOuter)
        end

        local Container = Library:Create('Frame', {
            BackgroundTransparency = 1;
            ClipsDescendants = true;

            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);

            ZIndex = 7;
            Parent = TextBoxInner;
        })

        local Box = Library:Create('TextBox', {
            BackgroundTransparency = 1;

            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromScale(5, 1),

            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(100, 100, 100);
            PlaceholderText = Info.Placeholder or '';

            Text = Info.Default or '';
            TextColor3 = Library.FontColor;
            TextSize = 14;
            TextStrokeTransparency = 0;
            TextXAlignment = Enum.TextXAlignment.Left;

            ZIndex = 7;
            Parent = Container;
        });

        Library:ApplyTextStroke(Box);

        function Textbox:SetValue(Text)
            if Info.MaxLength and #Text > Info.MaxLength then
                Text = Text:sub(1, Info.MaxLength);
            end;

            if Textbox.Numeric then
                if (not tonumber(Text)) and Text:len() > 0 then
                    Text = Textbox.Value
                end
            end

            Textbox.Value = Text;
            Box.Text = Text;

            Library:SafeCallback(Textbox.Callback, Textbox.Value);
            Library:SafeCallback(Textbox.Changed, Textbox.Value);
        end;

        if Textbox.Finished then
            Box.FocusLost:Connect(function(enter)
                if not enter then return end

                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end)
        else
            Box:GetPropertyChangedSignal('Text'):Connect(function()
                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end);
        end

        -- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
        -- thank you nicemike40 :)

        local function Update()
            local PADDING = 2
            local reveal = Container.AbsoluteSize.X

            if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
                -- we aren't focused, or we fit so be normal
                Box.Position = UDim2.new(0, PADDING, 0, 0)
            else
                -- we are focused and don't fit, so adjust position
                local cursor = Box.CursorPosition
                if cursor ~= -1 then
                    -- calculate pixel width of text from start to cursor
                    local subtext = string.sub(Box.Text, 1, cursor-1)
                    local width = TextService:GetTextSize(subtext, Box.TextSize, Box.Font, Vector2.new(math.huge, math.huge)).X

                    -- check if we're inside the box with the cursor
                    local currentCursorPos = Box.Position.X.Offset + width

                    -- adjust if necessary
                    if currentCursorPos < PADDING then
                        Box.Position = UDim2.fromOffset(PADDING-width, 0)
                    elseif currentCursorPos > reveal - PADDING - 1 then
                        Box.Position = UDim2.fromOffset(reveal-width-PADDING-1, 0)
                    end
                end
            end
        end

        task.spawn(Update)

        Box:GetPropertyChangedSignal('Text'):Connect(Update)
        Box:GetPropertyChangedSignal('CursorPosition'):Connect(Update)
        Box.FocusLost:Connect(Update)
        Box.Focused:Connect(Update)

        Library:AddToRegistry(Box, {
            TextColor3 = 'FontColor';
        });

        function Textbox:OnChanged(Func)
            Textbox.Changed = Func;
            Func(Textbox.Value);
        end;

        Groupbox:AddBlank(5);
        Groupbox:Resize();

        Options[Idx] = Textbox;

        return Textbox;
    end;

    function Funcs:AddToggle(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Toggle = {
            Value = Info.Default or false;
            Type = 'Toggle';

            Callback = Info.Callback or function(Value) end;
            Addons = {},
            Risky = Info.Risky,
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local ToggleOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(0, 10, 0, 10);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(ToggleOuter, {
            BorderColor3 = 'Black';
        });

        local ToggleInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = ToggleOuter;
        });

        Library:AddToRegistry(ToggleInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        -- Accent overlay for Atlanta-style fade in/out on toggle. Sits on top
        -- of ToggleInner with BackgroundTransparency tweened between 0 (on)
        -- and 1 (off). ToggleInner's BackgroundColor stays neutral so the
        -- fade is pure alpha — no color-swap snap.
        local ToggleAccent = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            BackgroundTransparency = Toggle.Value and 0 or 1;
            AnchorPoint = Vector2.new(0.5, 0.5);
            Position = UDim2.new(0.5, 0, 0.5, 0);
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 7;
            Parent = ToggleInner;
        });
        Library:AddToRegistry(ToggleAccent, { BackgroundColor3 = 'AccentColor' });
        -- Subtle vertical gradient on the accent — mirrors Atlanta's toggle polish.
        Library:Create('UIGradient', {
            Rotation = 90;
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0),
                NumberSequenceKeypoint.new(1, 0.3),
            });
            Parent = ToggleAccent;
        });
        -- UIScale child driven by Toggle:Display. Empty toggle = scale 0,
        -- filled toggle = scale 1 with a tiny overshoot (back-out easing).
        -- Combined with the transparency tween this gives a "check pops in"
        -- effect instead of a flat alpha fade.
        local toggleScale = Library:Create('UIScale', {
            Scale = Toggle.Value and 1 or 0;
            Parent = ToggleAccent;
        });

        local ToggleLabel = Library:CreateLabel({
            Size = UDim2.new(0, Container.AbsoluteSize.X - 20, 1, 0);
            Position = UDim2.new(1, 6, 0, 0);
            TextSize = 14;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 6;
            Parent = ToggleInner;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 4);
            FillDirection = Enum.FillDirection.Horizontal;
            HorizontalAlignment = Enum.HorizontalAlignment.Right;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ToggleLabel;
        });

        Container:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
            ToggleLabel.Size = UDim2.new(0, Container.AbsoluteSize.X - 20, 1, 0);
        end);

        local ToggleRegion = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(0, 170, 1, 0);
            ZIndex = 8;
            Parent = ToggleOuter;
        });

        Library:OnHighlight(ToggleRegion, ToggleOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        function Toggle:UpdateColors()
            Toggle:Display();
        end;

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, ToggleRegion)
        end

        local ToggleFadeInfo = TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
        -- Back-out easing on the scale tween gives a tiny overshoot on fill-in,
        -- so the checkmark "pops" rather than just growing linearly.
        local ToggleScaleInfo = TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out);

        function Toggle:Display()
            -- Keep ToggleInner's base color neutral; the overlay handles the
            -- on/off visual via a faded transparency tween.
            ToggleInner.BorderColor3 = Toggle.Value and Library.AccentColorDark or Library.OutlineColor;
            Library.RegistryMap[ToggleInner].Properties.BorderColor3 = Toggle.Value and 'AccentColorDark' or 'OutlineColor';

            TweenService:Create(ToggleAccent, ToggleFadeInfo, {
                BackgroundTransparency = Toggle.Value and 0 or 1;
            }):Play();
            TweenService:Create(toggleScale, ToggleScaleInfo, {
                Scale = Toggle.Value and 1 or 0;
            }):Play();
        end;

        function Toggle:OnChanged(Func)
            Toggle.Changed = Func;
            Func(Toggle.Value);
        end;

        function Toggle:SetValue(Bool)
            Bool = (not not Bool);

            Toggle.Value = Bool;
            Toggle:Display();

            for _, Addon in next, Toggle.Addons do
                if Addon.Type == 'KeyPicker' and Addon.SyncToggleState then
                    Addon.Toggled = Bool
                    Addon:Update()
                end
            end

            Library:SafeCallback(Toggle.Callback, Toggle.Value);
            Library:SafeCallback(Toggle.Changed, Toggle.Value);
            Library:UpdateDependencyBoxes();
        end;

        ToggleRegion.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                Toggle:SetValue(not Toggle.Value) -- Why was it not like this from the start?
                Library:AttemptSave();
            end;
        end);

        if Toggle.Risky then
            Library:RemoveFromRegistry(ToggleLabel)
            ToggleLabel.TextColor3 = Library.RiskColor
            Library:AddToRegistry(ToggleLabel, { TextColor3 = 'RiskColor' })
        end

        Toggle:Display();
        Groupbox:AddBlank(Info.BlankSize or 5 + 2);
        Groupbox:Resize();

        Toggle.TextLabel = ToggleLabel;
        Toggle.Container = Container;
        setmetatable(Toggle, BaseAddons);

        Toggles[Idx] = Toggle;

        Library:UpdateDependencyBoxes();

        return Toggle;
    end;

    function Funcs:AddSlider(Idx, Info)
        assert(Info.Default, 'AddSlider: Missing default value.');
        assert(Info.Text, 'AddSlider: Missing slider text.');
        assert(Info.Min, 'AddSlider: Missing minimum value.');
        assert(Info.Max, 'AddSlider: Missing maximum value.');
        assert(Info.Rounding, 'AddSlider: Missing rounding value.');

        local Slider = {
            Value = Info.Default;
            Min = Info.Min;
            Max = Info.Max;
            Rounding = Info.Rounding;
            Type = 'Slider';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        if not Info.Compact then
            Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 10);
                TextSize = 14;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        local SliderOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 10);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(SliderOuter, {
            BorderColor3 = 'Black';
        });

        local SliderInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = SliderOuter;
        });

        Library:AddToRegistry(SliderInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:ApplyGradient(SliderInner, 0.25);

        local Fill = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderColor3 = Library.AccentColorDark;
            Size = UDim2.new(0, 0, 1, 0);
            ZIndex = 7;
            Parent = SliderInner;
        });

        Library:AddToRegistry(Fill, {
            BackgroundColor3 = 'AccentColor';
            BorderColor3 = 'AccentColorDark';
        });

        -- Slider fill gradient (fade from left to right)
        Library:Create('UIGradient', {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 0.35),
                NumberSequenceKeypoint.new(1, 0)
            });
            Parent = Fill;
        });

        local HideBorderRight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.new(1, 0, 0, 0);
            Size = UDim2.new(0, 1, 1, 0);
            ZIndex = 8;
            Parent = Fill;
        });

        Library:AddToRegistry(HideBorderRight, {
            BackgroundColor3 = 'AccentColor';
        });

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = 12;
            Text = 'Infinite';
            ZIndex = 9;
            Parent = SliderInner;
        });

        Library:OnHighlight(SliderOuter, SliderOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, SliderOuter)
        end

        function Slider:UpdateColors()
            Fill.BackgroundColor3 = Library.AccentColor;
            Fill.BorderColor3 = Library.AccentColorDark;
        end;

        local function GetSliderMaxSize()
            return math.max(SliderInner.AbsoluteSize.X - 2, 1);
        end;

        -- Re-display when container resizes so fill stays proportionally correct
        SliderInner:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
            Slider:Display();
        end);

        function Slider:Display()
            local Suffix = Info.Suffix or '';
            local MaxSize = GetSliderMaxSize();

            if Info.Compact then
                DisplayLabel.Text = Info.Text .. ': ' .. Slider.Value .. Suffix
            elseif Info.HideMax then
                DisplayLabel.Text = string.format('%s', Slider.Value .. Suffix)
            else
                DisplayLabel.Text = string.format('%s/%s', Slider.Value .. Suffix, Slider.Max .. Suffix);
            end

            local X = math.ceil(Library:MapValue(Slider.Value, Slider.Min, Slider.Max, 0, MaxSize));
            Fill.Size = UDim2.new(0, X, 1, 0);

            HideBorderRight.Visible = not (X == MaxSize or X == 0);
        end;

        function Slider:OnChanged(Func)
            Slider.Changed = Func;
            Func(Slider.Value);
        end;

        local function Round(Value)
            if Slider.Rounding == 0 then
                return math.floor(Value);
            end;


            return tonumber(string.format('%.' .. Slider.Rounding .. 'f', Value))
        end;

        function Slider:GetValueFromXOffset(X)
            return Round(Library:MapValue(X, 0, GetSliderMaxSize(), Slider.Min, Slider.Max));
        end;

        function Slider:SetValue(Str)
            local Num = tonumber(Str);

            if (not Num) then
                return;
            end;

            Num = math.clamp(Num, Slider.Min, Slider.Max);

            Slider.Value = Num;
            Slider:Display();

            Library:SafeCallback(Slider.Callback, Slider.Value);
            Library:SafeCallback(Slider.Changed, Slider.Value);
        end;

        SliderInner.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                local mPos = Mouse.X;
                local gPos = Fill.Size.X.Offset;
                local Diff = mPos - (Fill.AbsolutePosition.X + gPos);

                while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                    local nMPos = Mouse.X;
                    local nX = math.clamp(gPos + (nMPos - mPos) + Diff, 0, GetSliderMaxSize());

                    local nValue = Slider:GetValueFromXOffset(nX);
                    local OldValue = Slider.Value;
                    Slider.Value = nValue;

                    Slider:Display();

                    if nValue ~= OldValue then
                        Library:SafeCallback(Slider.Callback, Slider.Value);
                        Library:SafeCallback(Slider.Changed, Slider.Value);
                    end;

                    RenderStepped:Wait();
                end;

                Library:AttemptSave();
            end;
        end);

        Slider:Display();
        Groupbox:AddBlank(Info.BlankSize or 6);
        Groupbox:Resize();

        Options[Idx] = Slider;

        return Slider;
    end;

    function Funcs:AddDropdown(Idx, Info)
        if Info.SpecialType == 'Player' then
            Info.Values = GetPlayersString();
            Info.AllowNull = true;
        elseif Info.SpecialType == 'Team' then
            Info.Values = GetTeamsString();
            Info.AllowNull = true;
        end;

        assert(Info.Values, 'AddDropdown: Missing dropdown value list.');
        assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional.')

        if (not Info.Text) then
            Info.Compact = true;
        end;

        local Dropdown = {
            Values = Info.Values;
            Value = Info.Multi and {};
            Multi = Info.Multi;
            Type = 'Dropdown';
            SpecialType = Info.SpecialType; -- can be either 'Player' or 'Team'
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local RelativeOffset = 0;

        if not Info.Compact then
            local DropdownLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 10);
                TextSize = 14;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(3);
        end

        for _, Element in next, Container:GetChildren() do
            if not Element:IsA('UIListLayout') then
                RelativeOffset = RelativeOffset + Element.Size.Y.Offset;
            end;
        end;

        local DropdownOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            Size = UDim2.new(1, -4, 0, 20);
            ZIndex = 5;
            Parent = Container;
        });

        Library:AddToRegistry(DropdownOuter, {
            BorderColor3 = 'Black';
        });

        local DropdownInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DropdownOuter;
        });

        Library:AddToRegistry(DropdownInner, {
            BackgroundColor3 = 'BackgroundColor';
            BorderColor3 = 'OutlineColor';
        });

        Library:ApplyGradient(DropdownInner);

        local DropdownArrow = Library:CreateLabel({
            AnchorPoint = Vector2.new(0, 0.5);
            BackgroundTransparency = 1;
            Position = UDim2.new(1, -16, 0.5, 0);
            Size = UDim2.new(0, 12, 0, 12);
            Text = '+';
            TextSize = 14;
            TextColor3 = Library.FontColor;
            ZIndex = 8;
            Parent = DropdownInner;
        });

        local ItemList = Library:CreateLabel({
            Position = UDim2.new(0, 5, 0, 0);
            Size = UDim2.new(1, -5, 1, 0);
            TextSize = 14;
            Text = '--';
            TextXAlignment = Enum.TextXAlignment.Left;
            TextWrapped = true;
            ZIndex = 7;
            Parent = DropdownInner;
        });

        Library:OnHighlight(DropdownOuter, DropdownOuter,
            { BorderColor3 = 'AccentColor' },
            { BorderColor3 = 'Black' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, DropdownOuter)
        end

        local MAX_DROPDOWN_ITEMS = 8;

        local ListOuter = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BorderColor3 = Color3.new(0, 0, 0);
            ZIndex = 20;
            Visible = false;
            Parent = ScreenGui;
        });

        local function RecalculateListPosition()
            ListOuter.Position = UDim2.fromOffset(DropdownOuter.AbsolutePosition.X, DropdownOuter.AbsolutePosition.Y + DropdownOuter.Size.Y.Offset + 1);
        end;

        local function RecalculateListSize(YSize)
            ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, YSize or (MAX_DROPDOWN_ITEMS * 20 + 2))
        end;

        RecalculateListPosition();
        RecalculateListSize();

        DropdownOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(RecalculateListPosition);
        DropdownOuter:GetPropertyChangedSignal('AbsoluteSize'):Connect(function()
            RecalculateListPosition();
            RecalculateListSize();
        end);

        local ListInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderColor3 = Library.OutlineColor;
            BorderMode = Enum.BorderMode.Inset;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListOuter;
        });

        Library:AddToRegistry(ListInner, {
            BackgroundColor3 = 'MainColor';
            BorderColor3 = 'OutlineColor';
        });

        local Scrolling = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            CanvasSize = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 21;
            Parent = ListInner;

            TopImage = '',
            BottomImage = '',

            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Library.AccentColor,
        });

        Library:AddToRegistry(Scrolling, {
            ScrollBarImageColor3 = 'AccentColor'
        })

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 0);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Scrolling;
        });

        function Dropdown:Display()
            local Values = Dropdown.Values;
            local Str = '';

            if Info.Multi then
                for Idx, Value in next, Values do
                    if Dropdown.Value[Value] then
                        Str = Str .. Value .. ', ';
                    end;
                end;

                Str = Str:sub(1, #Str - 2);
            else
                Str = Dropdown.Value or '';
            end;

            ItemList.Text = (Str == '' and '--' or Str);
        end;

        function Dropdown:GetActiveValues()
            if Info.Multi then
                local T = {};

                for Value, Bool in next, Dropdown.Value do
                    table.insert(T, Value);
                end;

                return T;
            else
                return Dropdown.Value and 1 or 0;
            end;
        end;

        function Dropdown:BuildDropdownList()
            local Values = Dropdown.Values;
            local Buttons = {};

            for _, Element in next, Scrolling:GetChildren() do
                if not Element:IsA('UIListLayout') then
                    Element:Destroy();
                end;
            end;

            local Count = 0;

            for Idx, Value in next, Values do
                local Table = {};

                Count = Count + 1;

                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Library.OutlineColor;
                    BorderMode = Enum.BorderMode.Middle;
                    Size = UDim2.new(1, -1, 0, 20);
                    ZIndex = 23;
                    Active = true,
                    Parent = Scrolling;
                });

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                    BorderColor3 = 'OutlineColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, -6, 1, 0);
                    Position = UDim2.new(0, 6, 0, 0);
                    TextSize = 14;
                    Text = Value;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    ZIndex = 25;
                    Parent = Button;
                });

                Library:OnHighlight(Button, Button,
                    { BorderColor3 = 'AccentColor', ZIndex = 24 },
                    { BorderColor3 = 'OutlineColor', ZIndex = 23 }
                );

                local Selected;

                if Info.Multi then
                    Selected = Dropdown.Value[Value];
                else
                    Selected = Dropdown.Value == Value;
                end;

                function Table:UpdateButton()
                    if Info.Multi then
                        Selected = Dropdown.Value[Value];
                    else
                        Selected = Dropdown.Value == Value;
                    end;

                    ButtonLabel.TextColor3 = Selected and Library.AccentColor or Library.FontColor;
                    Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and 'AccentColor' or 'FontColor';
                end;

                ButtonLabel.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                        local Try = not Selected;

                        if Dropdown:GetActiveValues() == 1 and (not Try) and (not Info.AllowNull) then
                        else
                            if Info.Multi then
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value[Value] = true;
                                else
                                    Dropdown.Value[Value] = nil;
                                end;
                            else
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value = Value;
                                else
                                    Dropdown.Value = nil;
                                end;

                                for _, OtherButton in next, Buttons do
                                    OtherButton:UpdateButton();
                                end;
                            end;

                            Table:UpdateButton();
                            Dropdown:Display();

                            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
                            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);

                            Library:AttemptSave();
                        end;
                    end;
                end);

                Table:UpdateButton();
                Dropdown:Display();

                Buttons[Button] = Table;
            end;

            Scrolling.CanvasSize = UDim2.fromOffset(0, (Count * 20) + 1);

            local Y = math.clamp(Count * 20, 0, MAX_DROPDOWN_ITEMS * 20) + 1;
            RecalculateListSize(Y);
        end;

        function Dropdown:SetValues(NewValues)
            if NewValues then
                Dropdown.Values = NewValues;
            end;

            Dropdown:BuildDropdownList();
        end;

        function Dropdown:OpenDropdown()
            ListOuter.Visible = true;
            Library.OpenedFrames[ListOuter] = true;
            DropdownArrow.Text = '-';
        end;

        function Dropdown:CloseDropdown()
            ListOuter.Visible = false;
            Library.OpenedFrames[ListOuter] = nil;
            DropdownArrow.Text = '+';
        end;

        function Dropdown:OnChanged(Func)
            Dropdown.Changed = Func;
            Func(Dropdown.Value);
        end;

        function Dropdown:SetValue(Val)
            if Dropdown.Multi then
                local nTable = {};

                for Value, Bool in next, Val do
                    if table.find(Dropdown.Values, Value) then
                        nTable[Value] = true
                    end;
                end;

                Dropdown.Value = nTable;
            else
                if (not Val) then
                    Dropdown.Value = nil;
                elseif table.find(Dropdown.Values, Val) then
                    Dropdown.Value = Val;
                end;
            end;

            Dropdown:BuildDropdownList();

            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);
        end;

        DropdownOuter.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                if ListOuter.Visible then
                    Dropdown:CloseDropdown();
                else
                    Dropdown:OpenDropdown();
                end;
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    Dropdown:CloseDropdown();
                end;
            end;
        end));

        Dropdown:BuildDropdownList();
        Dropdown:Display();

        local Defaults = {}

        if type(Info.Default) == 'string' then
            local Idx = table.find(Dropdown.Values, Info.Default)
            if Idx then
                table.insert(Defaults, Idx)
            end
        elseif type(Info.Default) == 'table' then
            for _, Value in next, Info.Default do
                local Idx = table.find(Dropdown.Values, Value)
                if Idx then
                    table.insert(Defaults, Idx)
                end
            end
        elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] ~= nil then
            table.insert(Defaults, Info.Default)
        end

        if next(Defaults) then
            for i = 1, #Defaults do
                local Index = Defaults[i]
                if Info.Multi then
                    Dropdown.Value[Dropdown.Values[Index]] = true
                else
                    Dropdown.Value = Dropdown.Values[Index];
                end

                if (not Info.Multi) then break end
            end

            Dropdown:BuildDropdownList();
            Dropdown:Display();
        end

        Groupbox:AddBlank(Info.BlankSize or 5);
        Groupbox:Resize();

        Options[Idx] = Dropdown;

        return Dropdown;
    end;

    function Funcs:AddDependencyBox()
        local Depbox = {
            Dependencies = {};
        };
        
        local Groupbox = self;
        local Container = Groupbox.Container;

        local Holder = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, 0);
            Visible = false;
            Parent = Container;
        });

        local Frame = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 1, 0);
            Visible = true;
            Parent = Holder;
        });

        local Layout = Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Frame;
        });

        function Depbox:Resize()
            Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y);
            Groupbox:Resize();
        end;

        Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            Depbox:Resize();
        end);

        Holder:GetPropertyChangedSignal('Visible'):Connect(function()
            Depbox:Resize();
        end);

        function Depbox:Update()
            for _, Dependency in next, Depbox.Dependencies do
                local Elem = Dependency[1];
                local Value = Dependency[2];

                if Elem.Type == 'Toggle' and Elem.Value ~= Value then
                    Holder.Visible = false;
                    Depbox:Resize();
                    return;
                end;
            end;

            Holder.Visible = true;
            Depbox:Resize();
        end;

        function Depbox:SetupDependencies(Dependencies)
            for _, Dependency in next, Dependencies do
                assert(type(Dependency) == 'table', 'SetupDependencies: Dependency is not of type `table`.');
                assert(Dependency[1], 'SetupDependencies: Dependency is missing element argument.');
                assert(Dependency[2] ~= nil, 'SetupDependencies: Dependency is missing value argument.');
            end;

            Depbox.Dependencies = Dependencies;
            Depbox:Update();
        end;

        Depbox.Container = Frame;

        setmetatable(Depbox, BaseGroupbox);

        table.insert(Library.DependencyBoxes, Depbox);

        return Depbox;
    end;

    BaseGroupbox.__index = Funcs;
    BaseGroupbox.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

-- < Create other UI elements >
do
    Library.NotificationArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        AnchorPoint = Vector2.new(0, 0);
        Position = UDim2.new(0, 100, 0, 40);
        Size = UDim2.new(0, 300, 0, 400);
        ZIndex = 100;
        Parent = ScreenGui;
    });

    Library.NotificationLayout = Library:Create('UIListLayout', {
        Padding = UDim.new(0, 4);
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        HorizontalAlignment = Enum.HorizontalAlignment.Left;
        Parent = Library.NotificationArea;
    });

    -- Watermark with glow
    local WatermarkOuter = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        AnchorPoint = Vector2.new(1, 0);
        Position = UDim2.new(1, -10, 0, 10);
        Size = UDim2.new(0, 213, 0, 25);
        ZIndex = 200;
        Visible = false;
        Parent = ScreenGui;
    });

    -- Watermark glow
    for i = 1, 4 do
        local WmGlow = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BackgroundTransparency = 0.5 + i * 0.1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, -i, 0, -i);
            Size = UDim2.new(1, i * 2, 1, i * 2);
            ZIndex = 199;
            Parent = WatermarkOuter;
        });
        Library:AddToRegistry(WmGlow, { BackgroundColor3 = 'AccentColor' }, true);
    end;

    local WatermarkBorder1 = Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 201;
        Parent = WatermarkOuter;
    });

    Library:AddToRegistry(WatermarkBorder1, {
        BackgroundColor3 = 'OutlineColor';
    });

    local WatermarkBorder2 = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 202;
        Parent = WatermarkBorder1;
    });

    local WatermarkInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 203;
        Parent = WatermarkBorder2;
    });

    Library:AddToRegistry(WatermarkInner, {
        BackgroundColor3 = 'MainColor';
    });

    -- Accent line at top of watermark
    local WatermarkTopAccent = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 205;
        Parent = WatermarkInner;
    });

    Library:AddToRegistry(WatermarkTopAccent, {
        BackgroundColor3 = 'AccentColor';
    });

    local WatermarkLabel = Library:CreateLabel({
        Position = UDim2.new(0, 5, 0, 2);
        Size = UDim2.new(1, -10, 1, -2);
        TextSize = 14;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 204;
        Parent = WatermarkInner;
    });

    Library.Watermark = WatermarkOuter;
    Library.WatermarkText = WatermarkLabel;
    Library:MakeDraggable(Library.Watermark);



    -- Keybinds panel with glow
    local KeybindOuter = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 10, 0.5, 0);
        AnchorPoint = Vector2.new(0, 0.5);
        Size = UDim2.new(0, 180, 0, 22);
        Visible = false;
        ZIndex = 100;
        Parent = ScreenGui;
    });

    -- Keybinds glow
    for i = 1, 4 do
        local KbGlow = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BackgroundTransparency = 0.5 + i * 0.1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, -i, 0, -i);
            Size = UDim2.new(1, i * 2, 1, i * 2);
            ZIndex = 99;
            Parent = KeybindOuter;
        });
        Library:AddToRegistry(KbGlow, { BackgroundColor3 = 'AccentColor' }, true);
    end;

    local KeybindBorder1 = Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 101;
        Parent = KeybindOuter;
    });

    Library:AddToRegistry(KeybindBorder1, {
        BackgroundColor3 = 'OutlineColor';
    }, true);

    local KeybindBorder2 = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 102;
        Parent = KeybindBorder1;
    });

    local KeybindInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 103;
        Parent = KeybindBorder2;
    });

    Library:AddToRegistry(KeybindInner, {
        BackgroundColor3 = 'MainColor';
    }, true);

    -- Accent line at top of keybinds
    local KeybindTopAccent = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 105;
        Parent = KeybindInner;
    });

    Library:AddToRegistry(KeybindTopAccent, {
        BackgroundColor3 = 'AccentColor';
    });

    local KeybindLabel = Library:CreateLabel({
        Size = UDim2.new(1, 0, 0, 18);
        Position = UDim2.fromOffset(5, 3),
        TextXAlignment = Enum.TextXAlignment.Left,
        Text = 'keybinds';
        TextSize = 13;
        ZIndex = 106;
        Parent = KeybindInner;
    });

    -- Separator under title
    local KeybindSep = Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 4, 0, 20);
        Size = UDim2.new(1, -8, 0, 1);
        ZIndex = 106;
        Parent = KeybindInner;
    });

    Library:AddToRegistry(KeybindSep, {
        BackgroundColor3 = 'OutlineColor';
    }, true);

    local KeybindContainer = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Size = UDim2.new(1, 0, 1, -22);
        Position = UDim2.new(0, 0, 0, 22);
        ZIndex = 1;
        Parent = KeybindInner;
    });

    Library:Create('UIListLayout', {
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = KeybindContainer;
    });

    Library:Create('UIPadding', {
        PaddingLeft = UDim.new(0, 5),
        PaddingRight = UDim.new(0, 5),
        Parent = KeybindContainer,
    })

    Library.KeybindFrame = KeybindOuter;
    Library.KeybindContainer = KeybindContainer;
    Library:MakeDraggable(KeybindOuter);
end;

function Library:SetWatermarkVisibility(Bool)
    Library.Watermark.Visible = Bool;
end;

function Library:SetWatermark(Text)
    local X, Y = Library:GetTextBounds(Text, Library.Font, 14);
    Library.Watermark.Size = UDim2.new(0, X + 20, 0, 25);
    Library:SetWatermarkVisibility(true)

    Library.WatermarkText.Text = Text;
end;

-- Reposition the notification spawn area. Valid: 'TopLeft', 'TopRight', 'Middle'.
-- Individual notify animations pick their AnchorPoint at spawn from the current value.
function Library:SetNotificationPosition(Pos)
    if Pos ~= 'TopLeft' and Pos ~= 'TopRight' and Pos ~= 'Middle' then
        return;
    end;

    Library.NotificationPosition = Pos;
    local Area = Library.NotificationArea;
    local Layout = Library.NotificationLayout;
    if not Area or not Layout then return end;

    if Pos == 'TopLeft' then
        Area.AnchorPoint = Vector2.new(0, 0);
        Area.Position = UDim2.new(0, 100, 0, 40);
        Layout.HorizontalAlignment = Enum.HorizontalAlignment.Left;
    elseif Pos == 'TopRight' then
        Area.AnchorPoint = Vector2.new(1, 0);
        Area.Position = UDim2.new(1, -10, 0, 40);
        Layout.HorizontalAlignment = Enum.HorizontalAlignment.Right;
    elseif Pos == 'Middle' then
        -- "~50px below screen center" per spec
        Area.AnchorPoint = Vector2.new(0.5, 0);
        Area.Position = UDim2.new(0.5, 0, 0.5, 50);
        Layout.HorizontalAlignment = Enum.HorizontalAlignment.Center;
    end;

    -- Re-anchor any currently-alive notifications so they don't drift.
    for _, child in Area:GetChildren() do
        if child:IsA('Frame') then
            local ax = 0;
            if Pos == 'TopRight' then ax = 1;
            elseif Pos == 'Middle' then ax = 0.5; end;
            child.AnchorPoint = Vector2.new(ax, 0);
        end;
    end;
end;

-- Spawn a draggable, empty on-screen container that the user can fill with
-- text labels at runtime (e.g. spectator list, killfeed, custom HUD).
--
-- Config:
--   Title     : optional string shown as header. Omit for a fully blank box.
--   Position  : UDim2, initial placement. Defaults to top-right area below watermark.
--   Width     : pixel width, default 200.
--   LabelSize : per-label height in pixels, default 14.
--
-- Returned object exposes:
--   :AddLabel(text, color) -> handle  { :SetText(t), :SetColor(c), :Remove() }
--   :Clear()                          remove all labels
--   :SetVisible(bool)                 user toggle (empty+menu-closed still hides)
--   :SetTitle(text)                   update/inject title text (no-op if no Title set)
--   :Destroy()                        tear down and unregister
--   .Frame / .Content                 raw instances for advanced use
--
-- Visibility rule: shown when (user-enabled) AND (has labels OR menu is open).
-- This lets the user drag the box while the menu is visible even if it has no
-- content yet, and keeps it hidden in-game when nothing interesting to show.
function Library:CreatePlaceholderBox(Config)
    Config = Config or {};
    local Title = Config.Title;
    local Width = Config.Width or 200;
    local LabelSize = Config.LabelSize or 14;
    -- Auto-stack vertically when caller doesn't provide a Position so
    -- multiple PlaceholderBoxes (Spectators + Movement Graph + future
    -- HUDs) don't all spawn on top of each other in the top-right
    -- corner. Counter is monotonic — Box:Destroy doesn't free its slot,
    -- but boxes destroyed before the next spawn keep the layout
    -- predictable when the user re-enables them.
    Library._phSpawnCount = Library._phSpawnCount or 0;
    local Position;
    if Config.Position then
        Position = Config.Position;
    else
        local idx = Library._phSpawnCount;
        Library._phSpawnCount = idx + 1;
        -- Right-align column, ~120px vertical gap so even a 4-label box
        -- doesn't overlap the next one. First box at y=50, second y=170.
        Position = UDim2.new(1, -(Width + 30), 0, 50 + idx * 120);
    end;

    local HeaderPadding = Title and 20 or 4;
    local FooterPadding = 4;

    local Outer = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = Position;
        Size = UDim2.new(0, Width, 0, HeaderPadding + FooterPadding);
        ZIndex = 195;
        Parent = Library.ScreenGui;
    });

    -- Accent glow halo (same pattern as watermark).
    for i = 1, 4 do
        local Glow = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BackgroundTransparency = 0.5 + i * 0.1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, -i, 0, -i);
            Size = UDim2.new(1, i * 2, 1, i * 2);
            ZIndex = 194;
            Parent = Outer;
        });
        Library:AddToRegistry(Glow, { BackgroundColor3 = 'AccentColor' }, true);
    end;

    local Border1 = Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 196;
        Parent = Outer;
    });
    Library:AddToRegistry(Border1, { BackgroundColor3 = 'OutlineColor' });

    local Border2 = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 197;
        Parent = Border1;
    });

    local Inner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 198;
        Parent = Border2;
    });
    Library:AddToRegistry(Inner, { BackgroundColor3 = 'MainColor' });

    local TopAccent = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 200;
        Parent = Inner;
    });
    Library:AddToRegistry(TopAccent, { BackgroundColor3 = 'AccentColor' });

    local TitleLabel;
    if Title then
        TitleLabel = Library:CreateLabel({
            Position = UDim2.new(0, 6, 0, 3);
            Size = UDim2.new(1, -12, 0, 14);
            Text = Title;
            TextSize = 13;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 199;
            Parent = Inner;
        });
    end;

    -- Labels live in a list-layout container so adds/removes auto-stack.
    local Content = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 6, 0, HeaderPadding);
        Size = UDim2.new(1, -12, 1, -(HeaderPadding + FooterPadding));
        ZIndex = 199;
        Parent = Inner;
    });

    Library:Create('UIListLayout', {
        Padding = UDim.new(0, 2);
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        HorizontalAlignment = Enum.HorizontalAlignment.Left;
        Parent = Content;
    });

    -- Full-surface drag (cutoff > box height = grab anywhere).
    Library:MakeDraggable(Outer, 10000);

    local Box = {
        Frame = Outer;
        Content = Content;
        Title = TitleLabel;
        _labels = {};
        _enabled = true;
    };

    local function refreshSize()
        local count = #Box._labels;
        local labelsHeight = count * (LabelSize + 2);
        if count == 0 then labelsHeight = 6 end; -- min height so empty box stays grabbable
        Outer.Size = UDim2.new(0, Width, 0, HeaderPadding + labelsHeight + FooterPadding);
    end;

    local function refreshVisibility()
        Outer.Visible = Box._enabled and (#Box._labels > 0 or Library.Toggled == true);
    end;
    Box._refreshVisibility = refreshVisibility;

    function Box:AddLabel(text, color)
        local lbl = Library:CreateLabel({
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, LabelSize);
            Text = text or '';
            TextColor3 = color or Color3.new(1, 1, 1);
            TextSize = 13;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 199;
            LayoutOrder = #self._labels + 1;
            Parent = Content;
        });
        table.insert(self._labels, lbl);

        local handle = { Instance = lbl };
        function handle:SetText(t) if lbl.Parent then lbl.Text = t end end;
        function handle:SetColor(c) if lbl.Parent then lbl.TextColor3 = c end end;
        function handle:Remove()
            for i, v in Box._labels do
                if v == lbl then
                    table.remove(Box._labels, i);
                    break;
                end;
            end;
            pcall(lbl.Destroy, lbl);
            refreshSize();
            refreshVisibility();
        end;

        refreshSize();
        refreshVisibility();
        return handle;
    end;

    function Box:Clear()
        for _, lbl in self._labels do
            pcall(lbl.Destroy, lbl);
        end;
        self._labels = {};
        refreshSize();
        refreshVisibility();
    end;

    function Box:SetVisible(bool)
        self._enabled = bool and true or false;
        refreshVisibility();
    end;

    function Box:SetTitle(text)
        if TitleLabel then
            TitleLabel.Text = text;
        end;
    end;

    function Box:Destroy()
        for i, b in Library.PlaceholderBoxes do
            if b == self then
                table.remove(Library.PlaceholderBoxes, i);
                break;
            end;
        end;
        pcall(Outer.Destroy, Outer);
    end;

    table.insert(Library.PlaceholderBoxes, Box);
    refreshSize();
    refreshVisibility();

    return Box;
end;

function Library:Notify(Text, Time)
    local XSize, YSize = Library:GetTextBounds(Text, Library.Font, 14);

    YSize = YSize + 7
    local Duration = Time or 5;
    local FinalW = XSize + 8 + 4;

    -- AnchorPoint.X follows NotificationPosition so the tween-grow animation
    -- keeps the correct edge fixed (left-anchored grows right, right-anchored
    -- grows left, center-anchored grows outward from center).
    local anchorX = 0;
    if Library.NotificationPosition == 'TopRight' then
        anchorX = 1;
    elseif Library.NotificationPosition == 'Middle' then
        anchorX = 0.5;
    end;

    local NotifyOuter = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        AnchorPoint = Vector2.new(anchorX, 0);
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(0, 0, 0, YSize);
        ClipsDescendants = false;
        BackgroundTransparency = 1;
        ZIndex = 100;
        Parent = Library.NotificationArea;
    });

    -- Glow: 4 layered accent frames, increasing size + transparency outward.
    -- Same technique as Window/Watermark — manual box-shadow (Roblox has no
    -- native shadow on Frames). Fades in with the notification body.
    local GlowFrames = {};
    for i = 1, 4 do
        local G = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, -i, 0, -i);
            Size = UDim2.new(1, i * 2, 1, i * 2);
            ZIndex = 99;
            Parent = NotifyOuter;
        });
        Library:AddToRegistry(G, { BackgroundColor3 = 'AccentColor' }, true);
        GlowFrames[i] = { frame = G, targetTrans = 0.5 + i * 0.1 };
    end;

    -- Body: black outline → outline-color ring → inner panel with gradient
    local NotifyBorder = Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 100;
        Parent = NotifyOuter;
    });
    Library:AddToRegistry(NotifyBorder, { BackgroundColor3 = 'OutlineColor' }, true);

    local NotifyInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ClipsDescendants = true;
        ZIndex = 101;
        Parent = NotifyBorder;
    });
    Library:AddToRegistry(NotifyInner, { BackgroundColor3 = 'MainColor' }, true);

    -- Subtle top-to-bottom gradient polish on the inner panel.
    Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
        });
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 0.25),
        });
        Rotation = 90;
        Parent = NotifyInner;
    });

    local NotifyLabel = Library:CreateLabel({
        Position = UDim2.new(0, 6, 0, 3);
        Size = UDim2.new(1, -8, 1, -3);
        Text = Text;
        TextXAlignment = Enum.TextXAlignment.Left;
        TextSize = 14;
        TextTransparency = 1;
        ZIndex = 103;
        Parent = NotifyInner;
    });
    -- Fade the label's UIStroke in sync with the text.
    local LabelStroke;
    for _, c in NotifyLabel:GetChildren() do
        if c:IsA('UIStroke') then LabelStroke = c; break end;
    end;
    if LabelStroke then LabelStroke.Transparency = 1 end;

    -- Top accent line with left→right shimmer gradient
    local TopColor = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 104;
        Parent = NotifyInner;
    });
    Library:AddToRegistry(TopColor, { BackgroundColor3 = 'AccentColor' }, true);
    Library:Create('UIGradient', {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.4),
            NumberSequenceKeypoint.new(0.5, 0),
            NumberSequenceKeypoint.new(1, 0.4),
        });
        Parent = TopColor;
    });

    -- Bottom countdown bar: shrinks from full width to zero over Duration.
    local BottomBar = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        BackgroundTransparency = 1;
        AnchorPoint = Vector2.new(0, 1);
        Position = UDim2.new(0, 0, 1, 0);
        Size = UDim2.new(1, 0, 0, 1);
        ZIndex = 104;
        Parent = NotifyInner;
    });
    Library:AddToRegistry(BottomBar, { BackgroundColor3 = 'AccentColor' }, true);

    -- Grow width first (Quad Out), then fade everything in. Two-phase animation
    -- keeps the slide feel but adds the Atlanta-style fade polish.
    local FadeIn = TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out);
    pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, FinalW, 0, YSize), 'Out', 'Quad', 0.35, true);

    TweenService:Create(NotifyOuter, FadeIn, { BackgroundTransparency = 0 }):Play();
    TweenService:Create(NotifyBorder, FadeIn, { BackgroundTransparency = 0 }):Play();
    TweenService:Create(NotifyInner, FadeIn, { BackgroundTransparency = 0 }):Play();
    TweenService:Create(TopColor, FadeIn, { BackgroundTransparency = 0 }):Play();
    TweenService:Create(BottomBar, FadeIn, { BackgroundTransparency = 0 }):Play();
    TweenService:Create(NotifyLabel, FadeIn, { TextTransparency = 0 }):Play();
    if LabelStroke then
        TweenService:Create(LabelStroke, FadeIn, { Transparency = 0 }):Play();
    end;
    for _, g in GlowFrames do
        TweenService:Create(g.frame, FadeIn, { BackgroundTransparency = g.targetTrans }):Play();
    end;

    task.spawn(function()
        -- Start the countdown bar drain as soon as fade-in finishes.
        task.wait(0.35);
        TweenService:Create(BottomBar,
            TweenInfo.new(Duration, Enum.EasingStyle.Linear),
            { Size = UDim2.new(0, 0, 0, 1) }):Play();

        task.wait(Duration);

        -- Fade everything out in parallel (Atlanta-style full-descendant fade).
        local FadeOut = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In);
        TweenService:Create(NotifyOuter, FadeOut, { BackgroundTransparency = 1 }):Play();
        TweenService:Create(NotifyBorder, FadeOut, { BackgroundTransparency = 1 }):Play();
        TweenService:Create(NotifyInner, FadeOut, { BackgroundTransparency = 1 }):Play();
        TweenService:Create(TopColor, FadeOut, { BackgroundTransparency = 1 }):Play();
        TweenService:Create(BottomBar, FadeOut, { BackgroundTransparency = 1 }):Play();
        TweenService:Create(NotifyLabel, FadeOut, { TextTransparency = 1 }):Play();
        if LabelStroke then
            TweenService:Create(LabelStroke, FadeOut, { Transparency = 1 }):Play();
        end;
        for _, g in GlowFrames do
            TweenService:Create(g.frame, FadeOut, { BackgroundTransparency = 1 }):Play();
        end;
        -- Shrink width simultaneously for the Linoria-style collapse feel.
        pcall(NotifyOuter.TweenSize, NotifyOuter, UDim2.new(0, 0, 0, YSize), 'In', 'Quad', 0.5, true);

        task.wait(0.5);

        NotifyOuter:Destroy();
    end);
end;

function Library:ShowLoader(Config)
    Config = Config or {};
    Config.Title = Config.Title or 'Loader';
    Config.Subtitle = Config.Subtitle or '';
    Config.ScriptName = Config.ScriptName or 'Script';
    Config.GameName = Config.GameName or 'Game';
    Config.Version = Config.Version or '1.0.0';
    Config.LoadTime = Config.LoadTime or 2;
    Config.Callback = Config.Callback or function() end;
    Config.Patchnotes = Config.Patchnotes or {};

    local HasPatchnotes = #Config.Patchnotes > 0;
    local LoaderWidth = HasPatchnotes and 560 or 320;
    local PanelW = HasPatchnotes and 280 or 316;

    -- Dedicated ScreenGui for the loader + intro with IgnoreGuiInset=true so
    -- the content isn't cut off by the Roblox topbar (health, chat, etc.).
    -- Parented directly to CoreGui via ProtectGui, destroyed after callback.
    local LoaderScreenGui = Instance.new('ScreenGui');
    ProtectGui(LoaderScreenGui);
    LoaderScreenGui.Name = 'NachtaraLoader';
    LoaderScreenGui.IgnoreGuiInset = true;
    LoaderScreenGui.ResetOnSpawn = false;
    LoaderScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
    LoaderScreenGui.DisplayOrder = 9999;
    LoaderScreenGui.Parent = CoreGui;

    local LoaderGui = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0.5, 0.5);
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = UDim2.fromScale(0.5, 0.5);
        Size = UDim2.fromOffset(LoaderWidth, 220);
        ZIndex = 500;
        Parent = LoaderScreenGui;
    });

    -- Glow
    for i = 1, 6 do
        local G = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BackgroundTransparency = 0.5 + i * 0.08;
            BorderSizePixel = 0;
            Position = UDim2.new(0, -i, 0, -i);
            Size = UDim2.new(1, i * 2, 1, i * 2);
            ZIndex = 499;
            Parent = LoaderGui;
        });
        Library:AddToRegistry(G, { BackgroundColor3 = 'AccentColor' });
    end;

    -- Border layers
    local LBorder1 = Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 501;
        Parent = LoaderGui;
    });
    Library:AddToRegistry(LBorder1, { BackgroundColor3 = 'OutlineColor' });

    local LBorder2 = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 501;
        Parent = LBorder1;
    });

    local LInner = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 502;
        Parent = LBorder2;
    });
    Library:AddToRegistry(LInner, { BackgroundColor3 = 'BackgroundColor' });

    -- Accent line top
    local LAccent = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 510;
        Parent = LInner;
    });
    Library:AddToRegistry(LAccent, { BackgroundColor3 = 'AccentColor' });

    -- Title
    Library:CreateLabel({
        Position = UDim2.new(0, 0, 0, 12);
        Size = UDim2.fromOffset(PanelW, 20);
        Text = Config.Title;
        TextSize = 16;
        TextColor3 = Color3.new(1, 1, 1);
        ZIndex = 510;
        Parent = LInner;
    });

    -- Subtitle
    Library:CreateLabel({
        Position = UDim2.new(0, 0, 0, 32);
        Size = UDim2.fromOffset(PanelW, 14);
        Text = Config.Subtitle;
        TextSize = 13;
        TextColor3 = Library.FontColor;
        ZIndex = 510;
        Parent = LInner;
    });

    -- Info fields container
    local InfoContainer = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 10, 0, 56);
        Size = UDim2.fromOffset(PanelW - 20, 52);
        ZIndex = 505;
        Parent = LInner;
    });
    Library:AddToRegistry(InfoContainer, { BackgroundColor3 = 'MainColor' });

    -- Script name row
    Library:CreateLabel({
        Position = UDim2.new(0, 8, 0, 4);
        Size = UDim2.new(0.4, 0, 0, 20);
        Text = 'Script';
        TextSize = 13;
        TextXAlignment = Enum.TextXAlignment.Left;
        TextColor3 = Library.FontColor;
        ZIndex = 510;
        Parent = InfoContainer;
    });

    Library:CreateLabel({
        Position = UDim2.new(0.4, 0, 0, 4);
        Size = UDim2.new(0.6, -8, 0, 20);
        Text = Config.ScriptName;
        TextSize = 13;
        TextXAlignment = Enum.TextXAlignment.Right;
        TextColor3 = Library.AccentColor;
        ZIndex = 510;
        Parent = InfoContainer;
    });

    -- Separator
    Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 6, 0, 26);
        Size = UDim2.new(1, -12, 0, 1);
        ZIndex = 510;
        Parent = InfoContainer;
    });

    -- Game name row
    Library:CreateLabel({
        Position = UDim2.new(0, 8, 0, 28);
        Size = UDim2.new(0.4, 0, 0, 20);
        Text = 'Game';
        TextSize = 13;
        TextXAlignment = Enum.TextXAlignment.Left;
        TextColor3 = Library.FontColor;
        ZIndex = 510;
        Parent = InfoContainer;
    });

    Library:CreateLabel({
        Position = UDim2.new(0.4, 0, 0, 28);
        Size = UDim2.new(0.6, -8, 0, 20);
        Text = Config.GameName;
        TextSize = 13;
        TextXAlignment = Enum.TextXAlignment.Right;
        TextColor3 = Library.AccentColor;
        ZIndex = 510;
        Parent = InfoContainer;
    });

    -- Version label
    Library:CreateLabel({
        Position = UDim2.new(0, 0, 0, 116);
        Size = UDim2.fromOffset(PanelW, 14);
        Text = 'v' .. Config.Version;
        TextSize = 12;
        TextColor3 = Color3.fromRGB(80, 80, 80);
        ZIndex = 510;
        Parent = LInner;
    });

    -- Progress bar (hidden until Load is pressed)
    local ProgressOuter = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 10, 1, -52);
        Size = UDim2.fromOffset(PanelW - 20, 8);
        ZIndex = 505;
        Visible = false;
        Parent = LInner;
    });

    local ProgressInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 506;
        Parent = ProgressOuter;
    });
    Library:AddToRegistry(ProgressInner, { BackgroundColor3 = 'MainColor' });

    local ProgressFill = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Size = UDim2.new(0, 0, 1, 0);
        ZIndex = 507;
        Parent = ProgressInner;
    });
    Library:AddToRegistry(ProgressFill, { BackgroundColor3 = 'AccentColor' });

    Library:Create('UIGradient', {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.3),
            NumberSequenceKeypoint.new(1, 0)
        });
        Parent = ProgressFill;
    });

    -- Status text (hidden until Load is pressed)
    local StatusLabel = Library:CreateLabel({
        Position = UDim2.new(0, 10, 1, -38);
        Size = UDim2.fromOffset(PanelW - 20, 14);
        Text = '';
        TextSize = 12;
        TextXAlignment = Enum.TextXAlignment.Left;
        TextColor3 = Library.FontColor;
        ZIndex = 510;
        Visible = false;
        Parent = LInner;
    });

    -- Load button — same structure as AddButton: black outer border, accent fill, inset outline
    local LoadBtnOuter = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderColor3 = Color3.new(0, 0, 0);
        Position = UDim2.new(0, 10, 1, -42);
        Size = UDim2.fromOffset(PanelW - 20, 20);
        ZIndex = 505;
        Active = true;
        Parent = LInner;
    });

    local LoadBtnInner = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderColor3 = Library:GetDarkerColor(Library.AccentColor);
        BorderMode = Enum.BorderMode.Inset;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 506;
        Parent = LoadBtnOuter;
    });
    Library:AddToRegistry(LoadBtnInner, { BackgroundColor3 = 'AccentColor' });

    local LoadBtnLabel = Library:CreateLabel({
        Size = UDim2.new(1, 0, 1, 0);
        Text = 'Load';
        TextSize = 14;
        TextColor3 = Color3.new(1, 1, 1);
        ZIndex = 510;
        Parent = LoadBtnInner;
    });

    -- Hover: outer border glows accent (same as OnHighlight in AddButton)
    LoadBtnOuter.MouseEnter:Connect(function()
        LoadBtnOuter.BorderColor3 = Library.AccentColor;
    end);
    LoadBtnOuter.MouseLeave:Connect(function()
        LoadBtnOuter.BorderColor3 = Color3.new(0, 0, 0);
    end);

    -- RIGHT PANEL: Patchnotes/Changelog
    if HasPatchnotes then
        -- Vertical separator
        Library:Create('Frame', {
            BackgroundColor3 = Library.OutlineColor;
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(PanelW + 4, 10);
            Size = UDim2.new(0, 1, 1, -20);
            ZIndex = 510;
            Parent = LInner;
        });

        -- Changelog header
        Library:CreateLabel({
            Position = UDim2.fromOffset(PanelW + 14, 12);
            Size = UDim2.new(1, -(PanelW + 24), 0, 16);
            Text = 'Changelog';
            TextSize = 13;
            TextXAlignment = Enum.TextXAlignment.Left;
            TextColor3 = Color3.new(1, 1, 1);
            ZIndex = 510;
            Parent = LInner;
        });

        -- Accent underline under header
        Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(PanelW + 14, 30);
            Size = UDim2.new(1, -(PanelW + 24), 0, 1);
            ZIndex = 510;
            Parent = LInner;
        });

        -- Scrollable patchnotes list
        local PatchScroll = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(PanelW + 14, 36);
            Size = UDim2.new(1, -(PanelW + 24), 1, -46);
            ScrollBarThickness = 3;
            ScrollBarImageColor3 = Library.AccentColor;
            CanvasSize = UDim2.fromOffset(0, 0);
            ZIndex = 510;
            Parent = LInner;
        });

        local PatchLayout = Library:Create('UIListLayout', {
            Padding = UDim.new(0, 10);
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = PatchScroll;
        });

        for i, Note in next, Config.Patchnotes do
            local Changes = Note.Changes or Note.changes or {};
            -- Calculate entry height: 14 header + 2 gap + 13*n changes + 2*(n-1) gaps
            local ChangesH = #Changes > 0 and (2 + #Changes * 13 + math.max(0, #Changes - 1) * 2) or 0;
            local EntryH = 14 + ChangesH;

            local EntryFrame = Library:Create('Frame', {
                BackgroundTransparency = 1;
                BorderSizePixel = 0;
                Size = UDim2.new(1, -4, 0, EntryH);
                LayoutOrder = i;
                ZIndex = 510;
                Parent = PatchScroll;
            });

            -- Version
            Library:CreateLabel({
                Position = UDim2.fromOffset(0, 0);
                Size = UDim2.fromOffset(90, 14);
                Text = Note.Version or Note.version or 'v?';
                TextSize = 12;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextColor3 = Library.AccentColor;
                ZIndex = 511;
                Parent = EntryFrame;
            });

            -- Date
            Library:CreateLabel({
                Position = UDim2.new(0, 92, 0, 0);
                Size = UDim2.new(1, -92, 0, 14);
                Text = Note.Date or Note.date or '';
                TextSize = 11;
                TextXAlignment = Enum.TextXAlignment.Right;
                TextColor3 = Color3.fromRGB(70, 70, 70);
                ZIndex = 511;
                Parent = EntryFrame;
            });

            -- Change lines
            local ChangeY = 16;
            for _, Change in next, Changes do
                Library:CreateLabel({
                    Position = UDim2.fromOffset(0, ChangeY);
                    Size = UDim2.new(1, 0, 0, 13);
                    Text = '• ' .. Change;
                    TextSize = 11;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    TextColor3 = Library.FontColor;
                    ZIndex = 511;
                    Parent = EntryFrame;
                });
                ChangeY = ChangeY + 15;
            end;
        end;

        -- Update canvas size whenever layout changes (no task.defer to avoid blocking issues)
        PatchLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            PatchScroll.CanvasSize = UDim2.fromOffset(0, PatchLayout.AbsoluteContentSize.Y + 4);
        end);
    end;

    -- Load logic
    local Loading = false;
    local ResumeEvent = Instance.new('BindableEvent');

    LoadBtnOuter.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 or Loading then return end;
        Loading = true;

        -- Fade out button
        TweenService:Create(LoadBtnInner, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { BackgroundTransparency = 1 }):Play();
        TweenService:Create(LoadBtnLabel, TweenInfo.new(0.18, Enum.EasingStyle.Quad), { TextTransparency = 1 }):Play();
        task.wait(0.2);
        LoadBtnOuter.Visible = false;

        -- Reveal progress bar and status
        ProgressOuter.Visible = true;
        StatusLabel.Visible = true;
        StatusLabel.TextTransparency = 1;
        TweenService:Create(StatusLabel, TweenInfo.new(0.25), { TextTransparency = 0 }):Play();

        -- Loading stages
        local Stages = Config.Stages or {
            { 0.15, 'Initializing...' },
            { 0.35, 'Loading modules...' },
            { 0.55, 'Setting up hooks...' },
            { 0.75, 'Preparing UI...' },
            { 0.90, 'Finalizing...' },
            { 1.00, 'Done!' },
        };

        local TotalTime = Config.LoadTime;
        local StageTime = TotalTime / #Stages;

        for _, Stage in next, Stages do
            local TargetProgress = Stage[1];
            local Text = Stage[2];
            StatusLabel.Text = Text;

            TweenService:Create(ProgressFill, TweenInfo.new(StageTime * 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Size = UDim2.new(TargetProgress, 0, 1, 0);
            }):Play();

            task.wait(StageTime);
        end;

        task.wait(0.3);

        -- Fade out everything
        for _, Desc in next, LoaderGui:GetDescendants() do
            if Desc:IsA('Frame') then
                TweenService:Create(Desc, TweenInfo.new(0.3, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 }):Play();
            elseif Desc:IsA('TextLabel') then
                TweenService:Create(Desc, TweenInfo.new(0.3, Enum.EasingStyle.Linear), { TextTransparency = 1 }):Play();
            elseif Desc:IsA('UIStroke') then
                TweenService:Create(Desc, TweenInfo.new(0.3, Enum.EasingStyle.Linear), { Transparency = 1 }):Play();
            end;
        end;
        TweenService:Create(LoaderGui, TweenInfo.new(0.3, Enum.EasingStyle.Linear), { BackgroundTransparency = 1 }):Play();

        task.wait(0.35);
        LoaderGui:Destroy();

        ResumeEvent:Fire();
    end);

    -- Block the calling thread until Load is pressed + animation finishes
    ResumeEvent.Event:Wait();
    ResumeEvent:Destroy();

    -- ═══════════════════════════════════════════════════════════════════
    -- Intro sequence: dark tint + camera blur + title fade.
    -- Runs AFTER the loader finishes, BEFORE the UI callback creates the
    -- window — so the user sees: progress bar → cinematic intro → UI opens.
    -- ═══════════════════════════════════════════════════════════════════
    do
        local IntroInfo = TweenInfo.new(1.0, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out);

        local Tint = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(0, 0, 0);
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.fromScale(1, 1);
            ZIndex = 480;
            Parent = LoaderScreenGui;
        });

        local Blur;
        pcall(function()
            Blur = Instance.new('BlurEffect');
            Blur.Size = 0;
            Blur.Parent = game:GetService('Lighting');
        end);

        local function mkIntroLabel(text, yOff, color, size, order)
            local l = Library:CreateLabel({
                Text = text;
                TextColor3 = color;
                TextSize = size;
                TextTransparency = 1;
                TextXAlignment = Enum.TextXAlignment.Center;
                AnchorPoint = Vector2.new(0.5, 0.5);
                Position = UDim2.new(0.5, 0, 0.5, yOff);
                Size = UDim2.fromOffset(400, size + 6);
                ZIndex = 481;
                Parent = Tint;
            });
            local stroke;
            for _, c in l:GetChildren() do
                if c:IsA('UIStroke') then stroke = c; stroke.Transparency = 1; break end;
            end;
            return { label = l, stroke = stroke, order = order };
        end;

        local introLabels = {
            mkIntroLabel(Config.Title, -22, Color3.fromRGB(230, 230, 230), 16, 1),
            mkIntroLabel(Config.ScriptName .. ' loaded', 0, Library.AccentColor, 13, 2),
            mkIntroLabel('press ' .. (Config.IntroKey or 'RightShift') .. ' to show/hide menu', 22, Color3.fromRGB(120, 120, 120), 12, 3),
        };

        TweenService:Create(Tint, IntroInfo, { BackgroundTransparency = 0.55 }):Play();
        if Blur then
            TweenService:Create(Blur, IntroInfo, { Size = 22 }):Play();
        end;
        for _, entry in introLabels do
            task.delay((entry.order - 1) * 0.08, function()
                TweenService:Create(entry.label, IntroInfo, { TextTransparency = 0 }):Play();
                if entry.stroke then
                    TweenService:Create(entry.stroke, IntroInfo, { Transparency = 0 }):Play();
                end;
            end);
        end;

        -- Fade-in takes 1.0s, hold for IntroDuration (default 1.4s), fade-out 1.0s.
        task.wait(1.0 + (Config.IntroDuration or 1.4));

        for _, entry in introLabels do
            TweenService:Create(entry.label, IntroInfo, { TextTransparency = 1 }):Play();
            if entry.stroke then
                TweenService:Create(entry.stroke, IntroInfo, { Transparency = 1 }):Play();
            end;
        end;
        TweenService:Create(Tint, IntroInfo, { BackgroundTransparency = 1 }):Play();
        if Blur then
            TweenService:Create(Blur, IntroInfo, { Size = 0 }):Play();
        end;

        task.delay(1.1, function()
            pcall(Tint.Destroy, Tint);
            if Blur then pcall(Blur.Destroy, Blur); end;
            -- Tear down the dedicated loader ScreenGui once everything inside has finished.
            pcall(LoaderScreenGui.Destroy, LoaderScreenGui);
        end);

        -- Overlap intro fade-out with UI creation so the window fades in behind the dimming intro.
        task.wait(0.35);
    end

    Library:SafeCallback(Config.Callback);
end;

function Library:CreateWindow(...)
    local Arguments = { ... }
    local Config = { AnchorPoint = Vector2.zero }

    if type(...) == 'table' then
        Config = ...;
    else
        Config.Title = Arguments[1]
        Config.AutoShow = Arguments[2] or false;
    end

    if type(Config.Title) ~= 'string' then Config.Title = 'No title' end
    if type(Config.TabPadding) ~= 'number' then Config.TabPadding = 0 end
    if type(Config.MenuFadeTime) ~= 'number' then Config.MenuFadeTime = 0.2 end

    if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50) end
    if typeof(Config.Size) ~= 'UDim2' then Config.Size = UDim2.fromOffset(610, 530) end

    if Config.Center then
        Config.AnchorPoint = Vector2.new(0.5, 0.5)
        Config.Position = UDim2.fromScale(0.5, 0.5)
    end

    local Window = {
        Tabs = {};
    };

    -- Outer is a plain Frame so the 6 glow layers (positioned at -i,-i with
    -- size 1+2i x 1+2i) render outside its bounds. A CanvasGroup clips to its
    -- own size — using one here swallowed the glow entirely.
    --
    -- The fadeable content lives inside FadeGroup (CanvasGroup) below: that
    -- gives us the single-tween GroupTransparency fade path. The glow frames
    -- sit alongside the FadeGroup, so they render, but they don't participate
    -- in the fade — close is instant anyway, so that's fine.
    local Outer = Library:Create('Frame', {
        AnchorPoint = Config.AnchorPoint,
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = Config.Position,
        Size = Config.Size,
        Visible = false;
        ZIndex = 1;
        Parent = ScreenGui;
    });

    Library:MakeDraggable(Outer, 26);

    -- Outer glow effect (accent-colored shadow around window)
    for i = 1, 6 do
        local GlowFrame = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BackgroundTransparency = 0.5 + i * 0.08;
            BorderSizePixel = 0;
            Position = UDim2.new(0, -i, 0, -i);
            Size = UDim2.new(1, i * 2, 1, i * 2);
            ZIndex = 0;
            Parent = Outer;
        });

        Library:AddToRegistry(GlowFrame, {
            BackgroundColor3 = 'AccentColor';
        });
    end;

    -- Fade layer — holds the actual menu content. Single tween on
    -- GroupTransparency fades ~1500 descendants atomically instead of
    -- allocating a Tween per descendant.
    local FadeGroup = Library:Create('CanvasGroup', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 1, 0);
        GroupTransparency = 1;
        ZIndex = 1;
        Parent = Outer;
    });

    -- 3-layer border: Black > Dark gray > Black > Background
    local Border1 = Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 1;
        Parent = FadeGroup;
    });

    Library:AddToRegistry(Border1, {
        BackgroundColor3 = 'OutlineColor';
    });

    local Border2 = Library:Create('Frame', {
        BackgroundColor3 = Color3.new(0, 0, 0);
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 1;
        Parent = Border1;
    });

    local Inner = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 1, 0, 1);
        Size = UDim2.new(1, -2, 1, -2);
        ZIndex = 1;
        Parent = Border2;
    });

    Library:AddToRegistry(Inner, {
        BackgroundColor3 = 'BackgroundColor';
    });

    -- Overall menu body gradient: subtle top→bottom darken for depth.
    Library:ApplyGradient(Inner, 0.15);

    -- Animated accent gradient line at the very top
    local TopAccent = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 0, 2);
        ZIndex = 5;
        Parent = Inner;
    });

    Library:AddToRegistry(TopAccent, {
        BackgroundColor3 = 'AccentColor';
    });

    -- Shimmer gradient on accent line (unique visual)
    -- Static double-sided fade on the accent line (was animated — removed
    -- because any per-frame UIGradient.Offset write inside the FadeGroup
    -- CanvasGroup forces the whole menu canvas to re-rasterize that frame,
    -- which caused constant drag/resize lag).
    Library:Create('UIGradient', {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0.25),
            NumberSequenceKeypoint.new(0.4, 0),
            NumberSequenceKeypoint.new(0.6, 0),
            NumberSequenceKeypoint.new(1, 0.25)
        });
        Parent = TopAccent;
    });

    -- Title bar area (GS-style: title centered, no tabs here)
    local TitleBar = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 2);
        Size = UDim2.new(1, 0, 0, 20);
        ZIndex = 1;
        Parent = Inner;
    });

    Library:AddToRegistry(TitleBar, {
        BackgroundColor3 = 'MainColor';
    });

    -- Subtle gradient on title bar
    Library:Create('UIGradient', {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
            ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1))
        });
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(1, 0.15)
        });
        Parent = TitleBar;
    });

    local WindowLabel = Library:CreateLabel({
        Position = UDim2.new(0, 7, 0, 0);
        Size = UDim2.new(1, -14, 1, 0);
        Text = Config.Title or '';
        TextSize = 13;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 2;
        Parent = TitleBar;
    });

    -- Separator line under titlebar
    local TitleSep = Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 22);
        Size = UDim2.new(1, 0, 0, 1);
        ZIndex = 2;
        Parent = Inner;
    });

    Library:AddToRegistry(TitleSep, {
        BackgroundColor3 = 'OutlineColor';
    });

    -- Horizontal tab bar
    local TabBarHeight = 22;

    local TabBar = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 23);
        Size = UDim2.new(1, 0, 0, TabBarHeight);
        ZIndex = 3;
        Parent = Inner;
    });

    Library:AddToRegistry(TabBar, {
        BackgroundColor3 = 'MainColor';
    });

    Library:ApplyGradient(TabBar, 0.3);

    -- Tab bar bottom separator
    Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 1, 0);
        Size = UDim2.new(1, 0, 0, 1);
        ZIndex = 4;
        Parent = TabBar;
    });

    -- Tab buttons container (horizontal)
    local TabArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 5;
        Parent = TabBar;
    });

    local TabListLayout = Library:Create('UIListLayout', {
        Padding = UDim.new(0, 0);
        FillDirection = Enum.FillDirection.Horizontal;
        HorizontalAlignment = Enum.HorizontalAlignment.Center;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = TabArea;
    });

    -- Content area
    local ContentY = 23 + TabBarHeight + 1;

    local TabContainer = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, ContentY);
        Size = UDim2.new(1, 0, 1, -(ContentY + 4));
        ZIndex = 2;
        Parent = Inner;
    });

    Library:AddToRegistry(TabContainer, {
        BackgroundColor3 = 'BackgroundColor';
    });

    -- Resize handle at bottom-right corner
    local ResizeHandle = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(1, -16, 1, -16);
        Size = UDim2.new(0, 16, 0, 16);
        ZIndex = 10;
        Parent = Outer;
    });

    -- Visual grip indicator with hover highlight
    local ResizeDots = {};
    for i = 0, 2 do
        for j = 0, i do
            local Dot = Library:Create('Frame', {
                BackgroundColor3 = Library.OutlineColor;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 12 - i * 4, 0, 12 - j * 4);
                Size = UDim2.new(0, 2, 0, 2);
                ZIndex = 11;
                Parent = ResizeHandle;
            });
            table.insert(ResizeDots, Dot);
        end;
    end;

    ResizeHandle.MouseEnter:Connect(function()
        for _, Dot in next, ResizeDots do
            Dot.BackgroundColor3 = Library.AccentColor;
        end;
    end);

    ResizeHandle.MouseLeave:Connect(function()
        for _, Dot in next, ResizeDots do
            Dot.BackgroundColor3 = Library.OutlineColor;
        end;
    end);

    -- Resize logic
    local MinSize = Vector2.new(450, 350);
    local MaxSize = Vector2.new(900, 700);

    ResizeHandle.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            local StartMouse = Vector2.new(Mouse.X, Mouse.Y);
            local StartSize = Vector2.new(Outer.Size.X.Offset, Outer.Size.Y.Offset);
            local OrigAnchor = Outer.AnchorPoint;

            -- Pin the top-left corner so resize only extends right/down
            local TopLeft = Vector2.new(
                Outer.AbsolutePosition.X,
                Outer.AbsolutePosition.Y
            );

            -- Temporarily set AnchorPoint to 0,0 for correct resize behavior
            Outer.AnchorPoint = Vector2.new(0, 0);
            Outer.Position = UDim2.fromOffset(TopLeft.X, TopLeft.Y);

            while InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
                local Delta = Vector2.new(Mouse.X - StartMouse.X, Mouse.Y - StartMouse.Y);
                local NewW = math.clamp(StartSize.X + Delta.X, MinSize.X, MaxSize.X);
                local NewH = math.clamp(StartSize.Y + Delta.Y, MinSize.Y, MaxSize.Y);

                Outer.Size = UDim2.fromOffset(NewW, NewH);

                RenderStepped:Wait();
            end;
        end;
    end);

    ResizeHandle.Active = true;

    function Window:SetWindowTitle(Title)
        WindowLabel.Text = Title;
    end;

    function Window:AddTab(Name)
        local Tab = {
            Groupboxes = {};
            Tabboxes = {};
        };

        -- Horizontal tab button
        local TabButton = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(0, 100, 1, 0);
            Active = true;
            ZIndex = 6;
            Parent = TabArea;
        });

        local TabButtonLabel = Library:CreateLabel({
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            Text = Name;
            TextSize = 14;
            TextColor3 = Color3.fromRGB(120, 120, 120);
            ZIndex = 7;
            Parent = TabButton;
        });

        -- Active tab underline: accent-colored bar with a transparency gradient
        -- that fades outward on both sides (opaque in center → transparent at
        -- the edges). Mirrors the reference screenshot's aesthetic.
        local TabUnderline = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 0, 1, -1);
            Size = UDim2.new(1, 0, 0, 1);
            ZIndex = 8;
            Visible = false;
            Parent = TabButton;
        });

        Library:AddToRegistry(TabUnderline, {
            BackgroundColor3 = 'AccentColor';
        });

        -- Horizontal transparency ramp: edges=1 (invisible), center=0 (full accent).
        -- Two symmetric ramps from both ends give the double-sided fade.
        Library:Create('UIGradient', {
            Transparency = NumberSequence.new({
                NumberSequenceKeypoint.new(0, 1),
                NumberSequenceKeypoint.new(0.2, 0.4),
                NumberSequenceKeypoint.new(0.5, 0),
                NumberSequenceKeypoint.new(0.8, 0.4),
                NumberSequenceKeypoint.new(1, 1),
            });
            Parent = TabUnderline;
        });

        -- Tab connector (covers separator line when active, creating seamless transition)
        local TabConnector = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 0, 1, 0);
            Size = UDim2.new(1, 0, 0, 1);
            ZIndex = 8;
            Visible = false;
            Parent = TabButton;
        });

        Library:AddToRegistry(TabConnector, {
            BackgroundColor3 = 'BackgroundColor';
        });

        Library:RemoveFromRegistry(TabButtonLabel);
        Library:AddToRegistry(TabButtonLabel, {
            TextColor3 = Color3.fromRGB(120, 120, 120);
        });

        -- Resize all tab buttons to fill width evenly
        local function ResizeTabButtons()
            local Count = 0;
            for _, Child in next, TabArea:GetChildren() do
                if not Child:IsA('UIListLayout') then
                    Count = Count + 1;
                end;
            end;
            if Count == 0 then Count = 1; end;
            for _, Child in next, TabArea:GetChildren() do
                if not Child:IsA('UIListLayout') then
                    Child.Size = UDim2.new(1 / Count, 0, 1, 0);
                end;
            end;
        end;
        ResizeTabButtons();

        local TabFrame = Library:Create('Frame', {
            Name = 'TabFrame',
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            Visible = false;
            ZIndex = 2;
            Parent = TabContainer;
        });

        local LeftSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 7, 0, 7);
            Size = UDim2.new(0.5, -11, 1, -7);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = '';
            TopImage = '';
            ScrollBarThickness = 0;
            ZIndex = 2;
            Parent = TabFrame;
        });

        local RightSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0.5, 5, 0, 7);
            Size = UDim2.new(0.5, -11, 1, -7);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = '';
            TopImage = '';
            ScrollBarThickness = 0;
            ZIndex = 2;
            Parent = TabFrame;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 8);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = LeftSide;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 8);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = RightSide;
        });

        for _, Side in next, { LeftSide, RightSide } do
            Side:WaitForChild('UIListLayout'):GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
                Side.CanvasSize = UDim2.fromOffset(0, Side.UIListLayout.AbsoluteContentSize.Y);
            end);
        end;

        function Tab:ShowTab()
            for _, Tab in next, Window.Tabs do
                Tab:HideTab();
            end;

            TabButtonLabel.TextColor3 = Color3.fromRGB(255, 255, 255);
            Library.RegistryMap[TabButtonLabel].Properties.TextColor3 = Color3.fromRGB(255, 255, 255);
            TabUnderline.Visible = true;
            TabConnector.Visible = true;
            TabFrame.Visible = true;
        end;

        function Tab:HideTab()
            TabButtonLabel.TextColor3 = Color3.fromRGB(120, 120, 120);
            Library.RegistryMap[TabButtonLabel].Properties.TextColor3 = Color3.fromRGB(120, 120, 120);
            TabUnderline.Visible = false;
            TabConnector.Visible = false;
            TabFrame.Visible = false;
        end;

        function Tab:SetLayoutOrder(Position)
            TabButton.LayoutOrder = Position;
            TabListLayout:ApplyLayout();
        end;

        function Tab:AddGroupbox(Info)
            local Groupbox = {};

            -- GS-style groupbox: Black > OutlineColor > Black > MainColor
            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Color3.new(0, 0, 0);
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 507 + 2);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            local BoxBorder = Library:Create('Frame', {
                BackgroundColor3 = Library.OutlineColor;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 1, 0, 1);
                Size = UDim2.new(1, -2, 1, -2);
                ZIndex = 3;
                Parent = BoxOuter;
            });

            Library:AddToRegistry(BoxBorder, {
                BackgroundColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxBorder;
            });

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'MainColor';
            });

            Library:ApplyGradient(BoxInner, 0.2);

            -- Accent line at top of groupbox with double-sided fade
            local BoxAccent = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 0, 0, 0);
                Size = UDim2.new(1, 0, 0, 1);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddToRegistry(BoxAccent, {
                BackgroundColor3 = 'AccentColor';
            });

            Library:Create('UIGradient', {
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.6),
                    NumberSequenceKeypoint.new(0.5, 0),
                    NumberSequenceKeypoint.new(1, 0.6),
                });
                Parent = BoxAccent;
            });

            local GroupboxLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 16);
                Position = UDim2.new(0, 6, 0, 3);
                TextSize = 13;
                Text = Info.Name;
                TextXAlignment = Enum.TextXAlignment.Left;
                ZIndex = 5;
                Parent = BoxInner;
            });

            -- GS-style separator under groupbox title
            local GroupSep = Library:Create('Frame', {
                BackgroundColor3 = Library.OutlineColor;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 4, 0, 20);
                Size = UDim2.new(1, -8, 0, 1);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddToRegistry(GroupSep, {
                BackgroundColor3 = 'OutlineColor';
            });

            local Container = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 4, 0, 24);
                Size = UDim2.new(1, -4, 1, -24);
                ZIndex = 1;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = Container;
            });

            function Groupbox:Resize()
                local Size = 0;

                for _, Element in next, Groupbox.Container:GetChildren() do
                    if (not Element:IsA('UIListLayout')) and Element.Visible then
                        Size = Size + Element.Size.Y.Offset;
                    end;
                end;

                BoxOuter.Size = UDim2.new(1, 0, 0, 24 + Size + 4);
            end;

            Groupbox.Container = Container;
            setmetatable(Groupbox, BaseGroupbox);

            Groupbox:AddBlank(3);
            Groupbox:Resize();

            Tab.Groupboxes[Info.Name] = Groupbox;

            return Groupbox;
        end;

        function Tab:AddLeftGroupbox(Name)
            return Tab:AddGroupbox({ Side = 1; Name = Name; });
        end;

        function Tab:AddRightGroupbox(Name)
            return Tab:AddGroupbox({ Side = 2; Name = Name; });
        end;

        function Tab:AddTabbox(Info)
            local Tabbox = {
                Tabs = {};
            };

            -- GS-style tabbox: Black > OutlineColor > Black > MainColor
            local BoxOuter = Library:Create('Frame', {
                BackgroundColor3 = Color3.new(0, 0, 0);
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 0);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            local BoxBorder = Library:Create('Frame', {
                BackgroundColor3 = Library.OutlineColor;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 1, 0, 1);
                Size = UDim2.new(1, -2, 1, -2);
                ZIndex = 3;
                Parent = BoxOuter;
            });

            Library:AddToRegistry(BoxBorder, {
                BackgroundColor3 = 'OutlineColor';
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, -2, 1, -2);
                Position = UDim2.new(0, 1, 0, 1);
                ZIndex = 4;
                Parent = BoxBorder;
            });

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'MainColor';
            });

            Library:ApplyGradient(BoxInner, 0.2);

            -- Accent line at top of tabbox with double-sided fade
            local TabboxAccent = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 0, 0, 0);
                Size = UDim2.new(1, 0, 0, 1);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddToRegistry(TabboxAccent, {
                BackgroundColor3 = 'AccentColor';
            });

            Library:Create('UIGradient', {
                Transparency = NumberSequence.new({
                    NumberSequenceKeypoint.new(0, 0.6),
                    NumberSequenceKeypoint.new(0.5, 0),
                    NumberSequenceKeypoint.new(1, 0.6),
                });
                Parent = TabboxAccent;
            });

            local TabboxButtons = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 0, 0, 1);
                Size = UDim2.new(1, 0, 0, 18);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Left;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TabboxButtons;
            });

            function Tabbox:AddTab(Name)
                local Tab = {};

                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BorderColor3 = Color3.new(0, 0, 0);
                    BorderSizePixel = 0;
                    Size = UDim2.new(0.5, 0, 1, 0);
                    ZIndex = 6;
                    Parent = TabboxButtons;
                });

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                });

                -- Vertical gradient on each tab button for depth.
                local ButtonGradient = Library:Create('UIGradient', {
                    Rotation = 90;
                    Color = ColorSequence.new(Color3.new(1, 1, 1));
                    Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 0);
                        NumberSequenceKeypoint.new(1, 0.35);
                    });
                    Parent = Button;
                });

                local ButtonLabel = Library:CreateLabel({
                    Size = UDim2.new(1, 0, 1, 0);
                    TextSize = 14;
                    Text = Name;
                    TextColor3 = Color3.fromRGB(130, 130, 130);
                    TextXAlignment = Enum.TextXAlignment.Center;
                    ZIndex = 7;
                    Parent = Button;
                });
                Library:RemoveFromRegistry(ButtonLabel);
                Library:AddToRegistry(ButtonLabel, {
                    TextColor3 = Color3.fromRGB(130, 130, 130);
                });

                -- Double-sided-fade accent underline on the active tab.
                local TabAccent = Library:Create('Frame', {
                    BackgroundColor3 = Library.AccentColor;
                    BorderSizePixel = 0;
                    AnchorPoint = Vector2.new(0, 1);
                    Position = UDim2.new(0, 0, 1, 0);
                    Size = UDim2.new(1, 0, 0, 1);
                    Visible = false;
                    ZIndex = 10;
                    Parent = Button;
                });
                Library:AddToRegistry(TabAccent, { BackgroundColor3 = 'AccentColor' });
                Library:Create('UIGradient', {
                    Transparency = NumberSequence.new({
                        NumberSequenceKeypoint.new(0, 1),
                        NumberSequenceKeypoint.new(0.25, 0.5),
                        NumberSequenceKeypoint.new(0.5, 0),
                        NumberSequenceKeypoint.new(0.75, 0.5),
                        NumberSequenceKeypoint.new(1, 1),
                    });
                    Parent = TabAccent;
                });

                local Block = Library:Create('Frame', {
                    BackgroundColor3 = Library.BackgroundColor;
                    BorderSizePixel = 0;
                    Position = UDim2.new(0, 0, 1, 0);
                    Size = UDim2.new(1, 0, 0, 1);
                    Visible = false;
                    ZIndex = 9;
                    Parent = Button;
                });

                Library:AddToRegistry(Block, {
                    BackgroundColor3 = 'BackgroundColor';
                });

                local Container = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    Position = UDim2.new(0, 4, 0, 20);
                    Size = UDim2.new(1, -4, 1, -20);
                    ZIndex = 1;
                    Visible = false;
                    Parent = BoxInner;
                });

                Library:Create('UIListLayout', {
                    FillDirection = Enum.FillDirection.Vertical;
                    SortOrder = Enum.SortOrder.LayoutOrder;
                    Parent = Container;
                });

                function Tab:Show()
                    for _, Tab in next, Tabbox.Tabs do
                        Tab:Hide();
                    end;

                    Container.Visible = true;
                    Block.Visible = true;
                    TabAccent.Visible = true;

                    Button.BackgroundColor3 = Library.BackgroundColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'BackgroundColor';
                    ButtonLabel.TextColor3 = Color3.fromRGB(255, 255, 255);
                    Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Color3.fromRGB(255, 255, 255);

                    Tab:Resize();
                end;

                function Tab:Hide()
                    Container.Visible = false;
                    Block.Visible = false;
                    TabAccent.Visible = false;

                    Button.BackgroundColor3 = Library.MainColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'MainColor';
                    ButtonLabel.TextColor3 = Color3.fromRGB(130, 130, 130);
                    Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Color3.fromRGB(130, 130, 130);
                end;

                function Tab:Resize()
                    local TabCount = 0;

                    for _, Tab in next, Tabbox.Tabs do
                        TabCount = TabCount + 1;
                    end;

                    for _, Button in next, TabboxButtons:GetChildren() do
                        if not Button:IsA('UIListLayout') then
                            Button.Size = UDim2.new(1 / TabCount, 0, 1, 0);
                        end;
                    end;

                    if (not Container.Visible) then
                        return;
                    end;

                    local Size = 0;

                    for _, Element in next, Tab.Container:GetChildren() do
                        if (not Element:IsA('UIListLayout')) and Element.Visible then
                            Size = Size + Element.Size.Y.Offset;
                        end;
                    end;

                    BoxOuter.Size = UDim2.new(1, 0, 0, 20 + Size + 2 + 2);
                end;

                Button.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                        Tab:Show();
                        Tab:Resize();
                    end;
                end);

                Tab.Container = Container;
                Tabbox.Tabs[Name] = Tab;

                setmetatable(Tab, BaseGroupbox);

                Tab:AddBlank(3);
                Tab:Resize();

                -- Show first tab (number is 2 cus of the UIListLayout that also sits in that instance)
                if #TabboxButtons:GetChildren() == 2 then
                    Tab:Show();
                end;

                return Tab;
            end;

            Tab.Tabboxes[Info.Name or ''] = Tabbox;

            return Tabbox;
        end;

        function Tab:AddLeftTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 1; });
        end;

        function Tab:AddRightTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 2; });
        end;

        TabButton.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                Tab:ShowTab();
            end;
        end);

        -- This was the first tab added, so we show it by default.
        if #TabContainer:GetChildren() == 1 then
            Tab:ShowTab();
        end;

        Window.Tabs[Name] = Tab;
        return Tab;
    end;

    local ModalElement = Library:Create('TextButton', {
        BackgroundTransparency = 1;
        Size = UDim2.new(0, 0, 0, 0);
        Visible = true;
        Text = '';
        Modal = false;
        Parent = ScreenGui;
    });

    local TransparencyCache = {};
    local Toggled = false;
    local Fading = false;

    -- Camera blur for the menu: one persistent BlurEffect that tweens between
    -- 0 (closed) and a target size (open). Created lazily on first toggle so
    -- unused menus don't touch Lighting. Stored on Library so :Unload cleans it.
    local function ensureMenuBlur()
        if Library.MenuBlur and Library.MenuBlur.Parent then return Library.MenuBlur end;
        pcall(function()
            local inst = Instance.new('BlurEffect');
            inst.Size = 0;
            inst.Parent = game:GetService('Lighting');
            Library.MenuBlur = inst;
        end);
        return Library.MenuBlur;
    end;

    function Library:Toggle()
        if Fading then
            return;
        end;

        local FadeTime = Config.MenuFadeTime;
        Fading = true;
        Toggled = (not Toggled);
        Library.Toggled = Toggled;
        ModalElement.Modal = Toggled;

        -- Blur: fade in with the menu, drop instantly on close.
        local Blur = ensureMenuBlur();
        if Blur and Blur.Parent then
            if Toggled then
                TweenService:Create(Blur, TweenInfo.new(FadeTime, Enum.EasingStyle.Quad), {
                    Size = 12;
                }):Play();
            else
                Blur.Size = 0;
            end;
        end;

        -- Refresh PlaceholderBoxes: empty ones show while menu is open (so the
        -- user can grab and drag them into place) and hide again when closed.
        for _, Box in Library.PlaceholderBoxes do
            if Box._refreshVisibility then
                pcall(Box._refreshVisibility);
            end;
        end;

        if Toggled then
            -- A bit scuffed, but if we're going from not toggled -> toggled we want to show the frame immediately so that the fade is visible.
            Outer.Visible = true;

            -- Menu crosshair: 4 Frames forming a plus around the mouse. Uses a
            -- dedicated ScreenGui parented to CoreGui so it ignores the topbar
            -- inset and sits above the main menu. Replaces a Drawing-based
            -- implementation — Drawing isn't UI and isn't available on every
            -- executor.
            task.spawn(function()
                local State = InputService.MouseIconEnabled;
                local S, Gap = 4, 1;

                local cursorGui = Instance.new('ScreenGui');
                ProtectGui(cursorGui);
                cursorGui.Name = 'SanyuiCursor';
                cursorGui.IgnoreGuiInset = true;
                cursorGui.ResetOnSpawn = false;
                cursorGui.DisplayOrder = 100000;
                cursorGui.Parent = CoreGui;

                local function mkArm()
                    local f = Instance.new('Frame');
                    f.BorderSizePixel = 0;
                    f.BackgroundColor3 = Color3.new(1, 1, 1);
                    f.AnchorPoint = Vector2.new(0.5, 0.5);
                    f.Parent = cursorGui;
                    return f;
                end;
                local armL, armR, armT, armB = mkArm(), mkArm(), mkArm(), mkArm();

                -- Accent-colored trail: 8 pooled dots that age out into transparency.
                -- Pool avoids per-frame allocation; write-index rotates round-robin.
                local TRAIL_N = 8;
                local trail = table.create(TRAIL_N);
                for i = 1, TRAIL_N do
                    local d = Instance.new('Frame');
                    d.BorderSizePixel = 0;
                    d.AnchorPoint = Vector2.new(0.5, 0.5);
                    d.BackgroundColor3 = Library.AccentColor;
                    d.BackgroundTransparency = 1;
                    d.Size = UDim2.fromOffset(3, 3);
                    d.Parent = cursorGui;
                    local c = Instance.new('UICorner');
                    c.CornerRadius = UDim.new(1, 0);
                    c.Parent = d;
                    trail[i] = { frame = d, birth = -1 };
                end;
                local trailIdx = 1;
                local TRAIL_LIFE = 0.35;

                local lastX, lastY = -1, -1;
                while Toggled and ScreenGui.Parent do
                    InputService.MouseIconEnabled = false;
                    local mPos = InputService:GetMouseLocation();
                    local X, Y = mPos.X, mPos.Y;

                    armL.Size     = UDim2.fromOffset(S - Gap, 1);
                    armL.Position = UDim2.fromOffset(X - Gap - (S - Gap) / 2, Y);
                    armR.Size     = UDim2.fromOffset(S - Gap, 1);
                    armR.Position = UDim2.fromOffset(X + Gap + (S - Gap) / 2, Y);
                    armT.Size     = UDim2.fromOffset(1, S - Gap);
                    armT.Position = UDim2.fromOffset(X, Y - Gap - (S - Gap) / 2);
                    armB.Size     = UDim2.fromOffset(1, S - Gap);
                    armB.Position = UDim2.fromOffset(X, Y + Gap + (S - Gap) / 2);

                    -- Spawn a trail dot only when the cursor actually moved.
                    if X ~= lastX or Y ~= lastY then
                        local slot = trail[trailIdx];
                        slot.frame.Position = UDim2.fromOffset(X, Y);
                        slot.frame.BackgroundColor3 = Library.AccentColor;
                        slot.birth = tick();
                        trailIdx = trailIdx % TRAIL_N + 1;
                        lastX, lastY = X, Y;
                    end;

                    local now = tick();
                    for i = 1, TRAIL_N do
                        local slot = trail[i];
                        if slot.birth > 0 then
                            local age = (now - slot.birth) / TRAIL_LIFE;
                            if age >= 1 then
                                slot.frame.BackgroundTransparency = 1;
                                slot.birth = -1;
                            else
                                slot.frame.BackgroundTransparency = age;
                            end;
                        end;
                    end;

                    RenderStepped:Wait();
                end;

                for i = 1, TRAIL_N do
                    pcall(trail[i].frame.Destroy, trail[i].frame);
                end;

                InputService.MouseIconEnabled = State;
                pcall(cursorGui.Destroy, cursorGui);
            end);
        end;

        if Toggled then
            -- Open: fade in on the CanvasGroup that holds the menu content.
            TweenService:Create(
                FadeGroup,
                TweenInfo.new(FadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                { GroupTransparency = 0 }
            ):Play();
            task.wait(FadeTime);
        else
            -- Close: instant. User explicitly wanted no close fade.
            FadeGroup.GroupTransparency = 1;
            Outer.Visible = false;
        end;

        Fading = false;
    end

    Library:GiveSignal(InputService.InputBegan:Connect(function(Input, Processed)
        if type(Library.ToggleKeybind) == 'table' and Library.ToggleKeybind.Type == 'KeyPicker' then
            if Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == Library.ToggleKeybind.Value then
                task.spawn(Library.Toggle)
            end
        elseif Input.KeyCode == Enum.KeyCode.RightControl or (Input.KeyCode == Enum.KeyCode.RightShift and (not Processed)) then
            task.spawn(Library.Toggle)
        end
    end))

    if Config.AutoShow then task.spawn(Library.Toggle) end

    Window.Holder = Outer;

    return Window;
end;

local function OnPlayerChange()
    local PlayerList = GetPlayersString();

    for _, Value in next, Options do
        if Value.Type == 'Dropdown' and Value.SpecialType == 'Player' then
            Value:SetValues(PlayerList);
        end;
    end;
end;

Players.PlayerAdded:Connect(OnPlayerChange);
Players.PlayerRemoving:Connect(OnPlayerChange);

getgenv().Library = Library
return Library
