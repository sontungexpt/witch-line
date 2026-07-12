local
type,
next,
pcall,
pairs,
string_gsub =
    type,
    next,
    pcall,
    pairs,
    string.gsub

local api = vim.api
local
hlID,
nvim_set_hl,
nvim_get_hl,
nvim_get_color_by_name =
    vim.fn.hlID,
    api.nvim_set_hl,
    api.nvim_get_hl,
    api.nvim_get_color_by_name

local theme_aware_enabled = false

local M = {}

--- @class ThemeAwareHighlight : vim.api.keyset.highlight
--- Whether the style adapts automatically to the current theme.
--- @field theme_aware? boolean

--- @alias HighlightStyle ThemeAwareHighlight | string

---@type table<string, integer>
local ColorRgb24Bit = {}

---@type table<string, HighlightStyle>
local Styles = {}

--- Highlight all styles in the Styles table.
local function restore_highlight_styles()
    for hl_name, style in pairs(Styles) do
        M.highlight(hl_name, style)
    end
end

--- Sets the auto theme value.
---@param value boolean
M.set_theme_aware_enabled = function(value)
    theme_aware_enabled = value
end

--- Inspects the current highlight cache.
--- @param target "rgb24bit"|"styles"|nil target to inspect
M.inspect = function(target)
    local notifier = require("witch-line.util.notifier")
    if target == "rgb24bit" then
        notifier.info(vim.inspect(ColorRgb24Bit))
    elseif target == "styles" then
        notifier.info(vim.inspect(Styles))
    else
        notifier.info(vim.inspect {
            ColorRgb24Bit = ColorRgb24Bit,
            Styles = Styles,
        })
    end
end


--- Toggles the auto-theme feature.
M.toggle_theme_aware = function()
    theme_aware_enabled = not theme_aware_enabled
    restore_highlight_styles()
    require("witch-line.util.notifier").info(
        "Auto theme is " .. (theme_aware_enabled and "enabled" or "disabled")
    )
end

api.nvim_create_autocmd("ColorScheme", {
    callback = restore_highlight_styles,
})


--- Generates a valid highlight group name from an ID.
--- @param id CompId The ID to generate the highlight name for.
--- @return string hl_name The generated highlight name.
M.make_hl_name_from_id = function(id)
    return "WL" .. string_gsub(id, "[^%w_]", "")
end

--- Adds a highlight name to a string.hi
--- @param str string The string to which the highlight name will be added.
--- @param hl_name string|nil The highlight name to add.
M.assign_highlight_name = function(str, hl_name)
    return hl_name and str ~= "" and "%#" .. hl_name .. "#" .. str .. "%*" or str
end

--- Replace a string contains highlight segment with new highlight name.
--- @param str string The string that may contains highlight segment.
--- @param new_hl_name string|nil The new string with the new replaced highlight name.
--- @param n? integer Whether to replace the first occurrence only.
M.replace_highlight_name = function(str, new_hl_name, n)
    return string_gsub(str, "%%#.-#", "%#" .. new_hl_name .. "#", n)
end

--- Safe nvim_get_hl with pcall.
---@param opts table
---@return vim.api.keyset.get_hl_info|nil
M.safe_nvim_get_hl = function(opts)
    local ok, style = pcall(nvim_get_hl, 0, opts)
    return ok and style or nil
end

local adjust
--- Adjust a 24-bit RGB foreground color for readability on any background.
--- Uses perceptual luminance for accurate brightness targeting:
--- blue (perceptually dark) gets more boost, green (perceptually bright) gets less.
--- @param c integer Foreground color (0xRRGGBB)
--- @param bg integer Background color (0xRRGGBB)
--- @return integer adjusted 24-bit RGB color
adjust = function(c, bg)
    local bit = require("bit")
    local rshift, band, lshift, bor = bit.rshift, bit.band, bit.lshift, bit.bor
    local K_AVG = 0.70 / 255    -- avg-based (light path)
    local K_LUM = 0.70 / 255000 -- luminance-based (dark path)

    adjust = function(c, bg)
        local dark = rshift(bg, 16) * 299 + band(rshift(bg, 8), 0xFF) * 587 + band(bg, 0xFF) * 114 < 130000
        local r = rshift(c, 16)
        local g = band(rshift(c, 8), 0xFF)
        local b = band(c, 0xFF)

        if dark then
            -- Luminance-based gain: blue-heavy → more boost, green-heavy → less
            local avg = (r + g + b) / 3
            if avg < 30 then
                local fill = 70 + (30 - avg) * 0.5
                r = r + fill; g = g + fill; b = b + fill
            end
            local L = r * 299 + g * 587 + b * 114
            local gn = 1 + (200000 - L) * K_LUM
            r = r * gn; if r > 255 then r = 255 end
            g = g * gn; if g > 255 then g = 255 end
            b = b * gn; if b > 255 then b = 255 end
        else
            -- Avg-based dimming on light bg (fast path — no luminance compute)
            local avg = (r + g + b) / 3
            if avg > 50 then
                local gn = 1 + (50 - avg) * K_AVG
                r = r * gn; g = g * gn; b = b * gn
            end
        end

        -- Desaturate using average gray
        local gray = (r + g + b) / 3
        local sat = dark and 0.88 or 0.72
        r = gray + (r - gray) * sat
        g = gray + (g - gray) * sat
        b = gray + (b - gray) * sat

        -- Ensure minimum readability on dark backgrounds
        if dark and gray < 75 then
            local diff = (75 - gray) * 0.6
            r = r + diff; g = g + diff; b = b + diff
        end

        r = math.floor(r + 0.5)
        if r > 255 then r = 255 elseif r < 0 then r = 0 end
        g = math.floor(g + 0.5)
        if g > 255 then g = 255 elseif g < 0 then g = 0 end
        b = math.floor(b + 0.5)
        if b > 255 then b = 255 elseif b < 0 then b = 0 end
        return bor(lshift(r, 16), lshift(g, 8), b)
    end

    return adjust(c, bg)
end

--- Cache the id of StatusLine hl group to avoid repeated API calls.
local STATUSLINE_HL = nil

--- Resolve a color into a 24-bit RGB value, a highlight group property, or "NONE".
---
--- Supports:
--- 1. Numeric RGB (e.g., 0xFFAA00) → returned directly (optionally adjusted).
--- 2. Named colors (e.g., "red") → resolved via Neovim API and cached.
--- 3. Highlight groups (e.g., "Normal") → fetch `fg` or `bg` field.
--- 4. "NONE" → returned as-is.
---
--- @param c string|integer|nil  Color name, RGB value, or highlight group.
--- @param field "fg"|"bg"   Field to fetch from highlight group.
--- @param auto_adjust? boolean  Adjust color based on statusline background if true.
--- @return integer|string|nil  Resolved 24-bit RGB, "NONE", or nil if not found.
local resolve_color = function(c, field, auto_adjust)
    local t = type(c)
    local num = c
    if t == "string" then
        if c == "NONE" then
            return "NONE"
        elseif c == "" then
            return nil
        end
        -- Read cache
        num = ColorRgb24Bit[c]
        if not num then
            num = nvim_get_color_by_name(c)
            if num ~= -1 then
                -- cache color
                ColorRgb24Bit[c] = num
            else
                local hlid = hlID(c)
                if hlid == 0 then
                    return nil
                end
                -- Not cache here because c can be changed by user
                num = nvim_get_hl(0, { id = hlid, create = false })[field]
            end
        end
    elseif t ~= "number" then
        return nil
    end
    --- @cast num integer num is number here
    if theme_aware_enabled and auto_adjust then
        STATUSLINE_HL = STATUSLINE_HL or {
            id = api.nvim_get_hl_id_by_name("StatusLine"),
        }
        local stbg = nvim_get_hl(0, STATUSLINE_HL).bg
        return stbg and adjust(num, stbg) or num
    end
    return num
end

--- Define or update a Neovim highlight group.
--- String style creates a link; table style resolves colors and sets directly.
--- Caches in `Styles` for persistence across colorscheme reloads.
---
--- @param group_name string The highlight group name.
--- @param hl_style HighlightStyle A link target string or highlight style table.
--- @return boolean applied True if the highlight was set successfully.
M.highlight = function(group_name, hl_style)
    if group_name == "" then
        return false
    end
    local hl_style_type = type(hl_style)
    if hl_style_type == "string" and hl_style ~= "" then
        nvim_set_hl(0, group_name, { link = hl_style, default = true })
        return true
    elseif hl_style_type ~= "table" or not next(hl_style) then
        return false
    end

    Styles[group_name] = hl_style

    local style = {} --- Shallow copy
    for k, v in pairs(hl_style) do
        style[k] = v
    end

    local theme_aware = style.theme_aware

    style.fg = resolve_color(style.fg or style.foreground, "fg", theme_aware)
    style.bg = resolve_color(style.bg or style.background, "bg", theme_aware) or "NONE"

    --- Removed this before highlight because this is the custom value and not valid in nvim_set_hl
    style.theme_aware = nil

    nvim_set_hl(0, group_name, style)
    return true
end

return M
