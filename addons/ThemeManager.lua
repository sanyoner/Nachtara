-- ═══════════════════════════════════════════════════════════════════════
-- ThemeManager — palette presets + custom theme save/load for Sanyui.
--
-- Default theme matches Sanyui's built-in palette (deep purple accent on
-- near-black background). Users can pick from built-ins, or save/load
-- custom themes to disk.
--
-- Public API:
--   ThemeManager:SetLibrary(lib)        — required before any :Apply* call
--   ThemeManager:SetFolder(folder)      — where custom themes live on disk
--   ThemeManager:ApplyTheme(name)       — apply a built-in or custom theme
--   ThemeManager:ApplyToTab(tab)        — creates a left-side "Themes" groupbox on the tab
--   ThemeManager:ApplyToGroupbox(gb)    — creates the theme UI inside an existing groupbox
--   ThemeManager:LoadDefault()          — loads the saved default (or falls back to 'Default')
-- ═══════════════════════════════════════════════════════════════════════

local httpService = game:GetService('HttpService')

local ThemeManager = {}
ThemeManager.Folder = 'LinoriaLibSettings'
ThemeManager.Library = nil
ThemeManager.DefaultTheme = 'Default'

-- Palette presets. Order matters — first-listed is the dropdown default.
-- Each entry: { sortIndex, { FontColor, MainColor, AccentColor, BackgroundColor, OutlineColor } }
ThemeManager.BuiltInThemes = {
    -- Sanyui's shipping palette: deep purple accent on near-black grays.
    ['Default']     = { 1, httpService:JSONDecode('{"FontColor":"b9b9b9","MainColor":"181823","AccentColor":"7346be","BackgroundColor":"16161f","OutlineColor":"2d2d2d"}') },
    ['Amethyst']    = { 2, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1a1625","AccentColor":"9b59b6","BackgroundColor":"141022","OutlineColor":"2b2339"}') },
    ['Fatality']    = { 3, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1e1842","AccentColor":"c50754","BackgroundColor":"191335","OutlineColor":"3c355d"}') },
    ['Jester']      = { 4, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor":"db4467","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
    ['Mint']        = { 5, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"242424","AccentColor":"3db488","BackgroundColor":"1c1c1c","OutlineColor":"373737"}') },
    ['Tokyo Night'] = { 6, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"191925","AccentColor":"6759b3","BackgroundColor":"16161f","OutlineColor":"323232"}') },
    ['Sunset']      = { 7, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"3e3e3e","AccentColor":"e2581e","BackgroundColor":"323232","OutlineColor":"191919"}') },
    ['Quartz']      = { 8, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"232330","AccentColor":"426e87","BackgroundColor":"1d1b26","OutlineColor":"27232f"}') },
    ['Classic Blue']= { 9, httpService:JSONDecode('{"FontColor":"ffffff","MainColor":"1c1c1c","AccentColor":"0055ff","BackgroundColor":"141414","OutlineColor":"323232"}') },
}

local THEME_FIELDS = { 'FontColor', 'MainColor', 'AccentColor', 'BackgroundColor', 'OutlineColor' }

function ThemeManager:SetLibrary(lib)
    self.Library = lib
end

function ThemeManager:BuildFolderTree()
    local parts = self.Folder:split('/')
    local paths = {}
    for i = 1, #parts do
        paths[#paths + 1] = table.concat(parts, '/', 1, i)
    end
    table.insert(paths, self.Folder .. '/themes')
    table.insert(paths, self.Folder .. '/settings')
    for _, p in ipairs(paths) do
        if not isfolder(p) then makefolder(p) end
    end
end

function ThemeManager:SetFolder(folder)
    self.Folder = folder
    self:BuildFolderTree()
end

function ThemeManager:ApplyTheme(theme)
    local customData = self:GetCustomTheme(theme)
    local data = customData or self.BuiltInThemes[theme]
    if not data then return end

    -- Built-ins are { sortIndex, palette }, custom themes are the palette directly.
    local palette = customData or data[2]
    for field, hex in pairs(palette) do
        self.Library[field] = Color3.fromHex(hex)
        if Options[field] then
            Options[field]:SetValueRGB(Color3.fromHex(hex))
        end
    end
    self:ThemeUpdate()
end

function ThemeManager:ThemeUpdate()
    -- Pull current colors from the Options ColorPickers so live edits propagate
    -- even when the user didn't open the Themes tab (registry refresh only).
    for _, field in ipairs(THEME_FIELDS) do
        if Options and Options[field] then
            self.Library[field] = Options[field].Value
        end
    end
    self.Library.AccentColorDark = self.Library:GetDarkerColor(self.Library.AccentColor)
    self.Library:UpdateColorsUsingRegistry()
end

function ThemeManager:LoadDefault()
    local path = self.Folder .. '/themes/default.txt'
    local theme = self.DefaultTheme
    local isCustom = false

    if isfile(path) then
        local saved = readfile(path)
        if self.BuiltInThemes[saved] then
            theme = saved
        elseif self:GetCustomTheme(saved) then
            theme = saved
            isCustom = true
        end
    end

    if not isCustom and Options.ThemeManager_ThemeList then
        Options.ThemeManager_ThemeList:SetValue(theme)
    else
        self:ApplyTheme(theme)
    end
end

function ThemeManager:SaveDefault(theme)
    writefile(self.Folder .. '/themes/default.txt', theme)
end

function ThemeManager:GetCustomTheme(file)
    if not file or file == '' then return nil end
    local path = self.Folder .. '/themes/' .. file
    if not isfile(path) then return nil end
    local ok, decoded = pcall(httpService.JSONDecode, httpService, readfile(path))
    return ok and decoded or nil
end

function ThemeManager:SaveCustomTheme(file)
    if not file or file:gsub(' ', '') == '' then
        return self.Library:Notify('Invalid theme file name', 3)
    end
    local theme = {}
    for _, field in ipairs(THEME_FIELDS) do
        theme[field] = Options[field].Value:ToHex()
    end
    writefile(self.Folder .. '/themes/' .. file .. '.json', httpService:JSONEncode(theme))
end

function ThemeManager:ReloadCustomThemes()
    local out = {}
    local list = listfiles(self.Folder .. '/themes')
    for _, file in ipairs(list) do
        if file:sub(-5) == '.json' then
            local pos = file:find('.json', 1, true)
            while pos > 0 do
                local ch = file:sub(pos, pos)
                if ch == '/' or ch == '\\' then break end
                pos = pos - 1
            end
            if pos > 0 then
                table.insert(out, file:sub(pos + 1))
            end
        end
    end
    return out
end

function ThemeManager:CreateThemeManager(groupbox)
    groupbox:AddLabel('Background color'):AddColorPicker('BackgroundColor', { Default = self.Library.BackgroundColor })
    groupbox:AddLabel('Main color')      :AddColorPicker('MainColor',       { Default = self.Library.MainColor })
    groupbox:AddLabel('Accent color')    :AddColorPicker('AccentColor',     { Default = self.Library.AccentColor })
    groupbox:AddLabel('Outline color')   :AddColorPicker('OutlineColor',    { Default = self.Library.OutlineColor })
    groupbox:AddLabel('Font color')      :AddColorPicker('FontColor',       { Default = self.Library.FontColor })

    local themeNames = {}
    for name in pairs(self.BuiltInThemes) do themeNames[#themeNames + 1] = name end
    table.sort(themeNames, function(a, b) return self.BuiltInThemes[a][1] < self.BuiltInThemes[b][1] end)

    groupbox:AddDivider()
    groupbox:AddDropdown('ThemeManager_ThemeList', { Text = 'Preset', Values = themeNames, Default = 1 })
    groupbox:AddButton('Set as default', function()
        self:SaveDefault(Options.ThemeManager_ThemeList.Value)
        self.Library:Notify(string.format('Set default theme to %q', Options.ThemeManager_ThemeList.Value))
    end)

    Options.ThemeManager_ThemeList:OnChanged(function()
        self:ApplyTheme(Options.ThemeManager_ThemeList.Value)
    end)

    groupbox:AddDivider()
    groupbox:AddInput('ThemeManager_CustomThemeName', { Text = 'Custom theme name' })
    groupbox:AddDropdown('ThemeManager_CustomThemeList', { Text = 'Custom themes', Values = self:ReloadCustomThemes(), AllowNull = true, Default = 1 })
    groupbox:AddDivider()

    groupbox:AddButton('Save theme', function()
        self:SaveCustomTheme(Options.ThemeManager_CustomThemeName.Value)
        Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
        Options.ThemeManager_CustomThemeList:SetValue(nil)
    end):AddButton('Load theme', function()
        if Options.ThemeManager_CustomThemeList.Value then
            self:ApplyTheme(Options.ThemeManager_CustomThemeList.Value)
        end
    end)

    groupbox:AddButton('Refresh list', function()
        Options.ThemeManager_CustomThemeList:SetValues(self:ReloadCustomThemes())
        Options.ThemeManager_CustomThemeList:SetValue(nil)
    end)

    groupbox:AddButton('Set custom as default', function()
        local val = Options.ThemeManager_CustomThemeList.Value
        if val and val ~= '' then
            self:SaveDefault(val)
            self.Library:Notify(string.format('Set default theme to %q', val))
        end
    end)

    self:LoadDefault()

    local function update() self:ThemeUpdate() end
    Options.BackgroundColor:OnChanged(update)
    Options.MainColor      :OnChanged(update)
    Options.AccentColor    :OnChanged(update)
    Options.OutlineColor   :OnChanged(update)
    Options.FontColor      :OnChanged(update)
end

function ThemeManager:ApplyToTab(tab)
    assert(self.Library, 'Must set ThemeManager.Library first!')
    local gb = tab:AddLeftGroupbox('Themes')
    self:CreateThemeManager(gb)
end

function ThemeManager:ApplyToGroupbox(groupbox)
    assert(self.Library, 'Must set ThemeManager.Library first!')
    self:CreateThemeManager(groupbox)
end

ThemeManager:BuildFolderTree()

return ThemeManager
