-- ═══════════════════════════════════════════════════════════════════════
-- SaveManager — config persistence with on-disk encryption.
--
-- Configs are written as a single opaque base64 string. The underlying format
-- is plain JSON (unchanged from the stock Linoria SaveManager), but it goes
-- through XOR + base64 on write and the reverse on read. Reading the raw file
-- from disk shows only a random-looking alphanumeric blob — toggle names,
-- slider values, dropdown selections, keybinds are not visible.
--
-- Cipher: XOR with a rotating fixed key, then base64 encode. XOR is symmetric
-- so the same helper decrypts. This is obfuscation (determined attackers with
-- the key can reverse it), not cryptographic secrecy — that's impossible in
-- pure Lua without a real crypto lib. Matches the user's request: "crypted"
-- meaning "doesn't reveal contents on casual inspection".
--
-- Public API (same as stock SaveManager):
--   SaveManager:SetLibrary(lib)
--   SaveManager:SetFolder(name)
--   SaveManager:SetIgnoreIndexes(list) / :IgnoreThemeSettings()
--   SaveManager:Save(name) / :Load(name)
--   SaveManager:BuildConfigSection(tab)
--   SaveManager:LoadAutoloadConfig()
-- ═══════════════════════════════════════════════════════════════════════

local httpService = game:GetService('HttpService')

local SaveManager = {}
SaveManager.Folder = 'LinoriaLibSettings'
SaveManager.Ignore = {}

-- ───────── Cipher ─────────
--
-- Key is a long fixed string. Changing it breaks existing configs — intentional
-- so a leaked sample config can't be trivially decoded without the library.
local CIPHER_KEY = 'nachtara_cfg_4f8c2a9e1d7b3f65_sanyui_v1'

local b64chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'

local function base64Encode(data)
    return ((data:gsub('.', function(x)
        local r, b = '', x:byte()
        for i = 8, 1, -1 do r = r .. (b % 2 ^ i - b % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2 ^ (6 - i) or 0) end
        return b64chars:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local function base64Decode(data)
    data = string.gsub(data, '[^' .. b64chars .. '=]', '')
    return (data:gsub('.', function(x)
        if x == '=' then return '' end
        local r, f = '', (b64chars:find(x) - 1)
        for i = 6, 1, -1 do r = r .. (f % 2 ^ i - f % 2 ^ (i - 1) > 0 and '1' or '0') end
        return r
    end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
        if #x ~= 8 then return '' end
        local c = 0
        for i = 1, 8 do c = c + (x:sub(i, i) == '1' and 2 ^ (8 - i) or 0) end
        return string.char(c)
    end))
end

local function xorBytes(data, key)
    local out = table.create(#data)
    local klen = #key
    for i = 1, #data do
        local kc = key:byte(((i - 1) % klen) + 1)
        out[i] = string.char(bit32.bxor(data:byte(i), kc))
    end
    return table.concat(out)
end

local function encryptPayload(plaintext)
    return base64Encode(xorBytes(plaintext, CIPHER_KEY))
end

local function decryptPayload(ciphertext)
    -- Trim whitespace a user might have introduced.
    ciphertext = (ciphertext:gsub('%s+', ''))
    local raw = base64Decode(ciphertext)
    return xorBytes(raw, CIPHER_KEY)
end

-- ───────── Parsers per element type ─────────

SaveManager.Parser = {
    Toggle = {
        Save = function(idx, object) return { type = 'Toggle', idx = idx, value = object.Value } end,
        Load = function(idx, data)
            if Toggles[idx] then Toggles[idx]:SetValue(data.value) end
        end,
    },
    Slider = {
        Save = function(idx, object) return { type = 'Slider', idx = idx, value = tostring(object.Value) } end,
        Load = function(idx, data)
            if Options[idx] then Options[idx]:SetValue(data.value) end
        end,
    },
    Dropdown = {
        Save = function(idx, object) return { type = 'Dropdown', idx = idx, value = object.Value, mutli = object.Multi } end,
        Load = function(idx, data)
            if Options[idx] then Options[idx]:SetValue(data.value) end
        end,
    },
    ColorPicker = {
        Save = function(idx, object) return { type = 'ColorPicker', idx = idx, value = object.Value:ToHex(), transparency = object.Transparency } end,
        Load = function(idx, data)
            if Options[idx] then Options[idx]:SetValueRGB(Color3.fromHex(data.value), data.transparency) end
        end,
    },
    KeyPicker = {
        Save = function(idx, object) return { type = 'KeyPicker', idx = idx, mode = object.Mode, key = object.Value } end,
        Load = function(idx, data)
            if Options[idx] then Options[idx]:SetValue({ data.key, data.mode }) end
        end,
    },
    Input = {
        Save = function(idx, object) return { type = 'Input', idx = idx, text = object.Value } end,
        Load = function(idx, data)
            if Options[idx] and type(data.text) == 'string' then Options[idx]:SetValue(data.text) end
        end,
    },
}

-- ───────── Folder / ignore list ─────────

function SaveManager:SetIgnoreIndexes(list)
    for _, key in next, list do self.Ignore[key] = true end
end

function SaveManager:IgnoreThemeSettings()
    self:SetIgnoreIndexes({
        'BackgroundColor', 'MainColor', 'AccentColor', 'OutlineColor', 'FontColor',
        'ThemeManager_ThemeList', 'ThemeManager_CustomThemeList', 'ThemeManager_CustomThemeName',
    })
end

function SaveManager:BuildFolderTree()
    local paths = { self.Folder, self.Folder .. '/themes', self.Folder .. '/settings' }
    for _, p in ipairs(paths) do
        if not isfolder(p) then makefolder(p) end
    end
end

function SaveManager:SetFolder(folder)
    self.Folder = folder
    self:BuildFolderTree()
end

function SaveManager:SetLibrary(lib)
    self.Library = lib
end

-- ───────── Save / Load ─────────

function SaveManager:Save(name)
    if not name then return false, 'no config file is selected' end
    local fullPath = self.Folder .. '/settings/' .. name .. '.nch'

    local data = { objects = {} }
    for idx, toggle in next, Toggles do
        if self.Ignore[idx] then continue end
        table.insert(data.objects, self.Parser[toggle.Type].Save(idx, toggle))
    end
    for idx, option in next, Options do
        if not self.Parser[option.Type] then continue end
        if self.Ignore[idx] then continue end
        table.insert(data.objects, self.Parser[option.Type].Save(idx, option))
    end

    local okEncode, json = pcall(httpService.JSONEncode, httpService, data)
    if not okEncode then return false, 'failed to encode data' end

    local okCipher, payload = pcall(encryptPayload, json)
    if not okCipher then return false, 'failed to encrypt data' end

    writefile(fullPath, payload)
    return true
end

function SaveManager:Load(name)
    if not name then return false, 'no config file is selected' end

    -- Modern encrypted path is `.nch`. Fall back to legacy plain-JSON `.json`
    -- so configs saved by the previous SaveManager still load.
    local encPath = self.Folder .. '/settings/' .. name .. '.nch'
    local legacyPath = self.Folder .. '/settings/' .. name .. '.json'

    local raw
    if isfile(encPath) then
        raw = readfile(encPath)
        local okD, plain = pcall(decryptPayload, raw)
        if not okD or type(plain) ~= 'string' then return false, 'failed to decrypt config' end
        raw = plain
    elseif isfile(legacyPath) then
        raw = readfile(legacyPath)
    else
        return false, 'invalid file'
    end

    local ok, decoded = pcall(httpService.JSONDecode, httpService, raw)
    if not ok or type(decoded) ~= 'table' or type(decoded.objects) ~= 'table' then
        return false, 'decode error'
    end

    for _, option in next, decoded.objects do
        if self.Parser[option.type] then
            task.spawn(function() self.Parser[option.type].Load(option.idx, option) end)
        end
    end
    return true
end

function SaveManager:RefreshConfigList()
    local list = listfiles(self.Folder .. '/settings')
    local out, seen = {}, {}
    for _, file in ipairs(list) do
        local ext = file:sub(-4)
        if ext == '.nch' or file:sub(-5) == '.json' then
            -- Extract basename between last path separator and the extension.
            local extLen = (ext == '.nch') and 4 or 5
            local start = #file - extLen
            local pos = start
            while pos > 0 do
                local ch = file:sub(pos, pos)
                if ch == '/' or ch == '\\' then break end
                pos = pos - 1
            end
            if pos >= 0 then
                local name = file:sub(pos + 1, start)
                if not seen[name] then
                    seen[name] = true
                    table.insert(out, name)
                end
            end
        end
    end
    return out
end

function SaveManager:LoadAutoloadConfig()
    local path = self.Folder .. '/settings/autoload.txt'
    if not isfile(path) then return end

    local name = readfile(path)
    local ok, err = self:Load(name)
    if not ok then
        return self.Library:Notify('Failed to load autoload config: ' .. tostring(err))
    end
    self.Library:Notify(string.format('Auto loaded config %q', name))
end

function SaveManager:BuildConfigSection(tab)
    assert(self.Library, 'Must set SaveManager.Library')

    local section = tab:AddRightGroupbox('Configuration')

    section:AddInput('SaveManager_ConfigName',    { Text = 'Config name' })
    section:AddDropdown('SaveManager_ConfigList', { Text = 'Config list', Values = self:RefreshConfigList(), AllowNull = true })

    section:AddDivider()

    section:AddButton('Create config', function()
        local name = Options.SaveManager_ConfigName.Value
        if name:gsub(' ', '') == '' then
            return self.Library:Notify('Invalid config name (empty)', 2)
        end
        local ok, err = self:Save(name)
        if not ok then return self.Library:Notify('Failed to save config: ' .. tostring(err)) end
        self.Library:Notify(string.format('Created config %q', name))
        Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
        Options.SaveManager_ConfigList:SetValue(nil)
    end):AddButton('Load config', function()
        local name = Options.SaveManager_ConfigList.Value
        local ok, err = self:Load(name)
        if not ok then return self.Library:Notify('Failed to load config: ' .. tostring(err)) end
        self.Library:Notify(string.format('Loaded config %q', name))
    end)

    section:AddButton('Overwrite config', function()
        local name = Options.SaveManager_ConfigList.Value
        local ok, err = self:Save(name)
        if not ok then return self.Library:Notify('Failed to overwrite config: ' .. tostring(err)) end
        self.Library:Notify(string.format('Overwrote config %q', name))
    end)

    section:AddButton('Refresh list', function()
        Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
        Options.SaveManager_ConfigList:SetValue(nil)
    end)

    section:AddButton('Set as autoload', function()
        local name = Options.SaveManager_ConfigList.Value
        writefile(self.Folder .. '/settings/autoload.txt', name)
        SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
        self.Library:Notify(string.format('Set %q to auto load', name))
    end)

    SaveManager.AutoloadLabel = section:AddLabel('Current autoload config: none', true)

    if isfile(self.Folder .. '/settings/autoload.txt') then
        local name = readfile(self.Folder .. '/settings/autoload.txt')
        SaveManager.AutoloadLabel:SetText('Current autoload config: ' .. name)
    end

    SaveManager:SetIgnoreIndexes({ 'SaveManager_ConfigList', 'SaveManager_ConfigName' })
end

SaveManager:BuildFolderTree()

return SaveManager
