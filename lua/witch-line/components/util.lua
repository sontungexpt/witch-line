local islist, type, pairs, next = vim.islist, type, pairs, next

local FN_TABLE              = { ["function"] = true, table = true }
local STR_FN_TABLE          = { string = true, ["function"] = true }
local BOOL_FN               = { boolean = true, ["function"] = true }
local STR_FN                = { string = true, ["function"] = true }
local NUM_TABLE             = { number = true, table = true }
local BOOL_NUM              = { boolean = true, number = true }
-- local NUM_FN                = { number = true, ["function"] = true }
-- local ANY                   = { number = true, string = true, boolean = true, table = true, ["function"] = true }

--- @type table<string, string|table<string, true>>
local OVERRIDEABLE_TYPE_MAP = {
    padding     = NUM_TABLE,
    config      = "table",
    timing      = BOOL_NUM,
    lazy        = "boolean",
    flexible    = "number",
    theme_aware = BOOL_FN,

    style       = FN_TABLE,
    left        = STR_FN,
    right       = STR_FN,
    left_style  = FN_TABLE,
    right_style = FN_TABLE,

    hidden      = "function",
    update      = STR_FN,
    on_click    = STR_FN_TABLE,
}

--- Recursively merge `from` into `to` for table values.
--- Lists (integer-indexed tables) are replaced entirely.
--- @param to? table
--- @param from? table
--- @return table|nil
local function merge_value(to, from)
    if to == nil then
        return from
    elseif from == nil then
        return to
    elseif type(from) ~= "table" then
        return from
    elseif next(to) == nil then
        return from
    elseif next(from) == nil then
        return to
    elseif islist(to) and islist(from) then
        return from
    end

    for k, v in pairs(from) do
        to[k] = merge_value(to[k], v)
    end
    return to
end

--- Apply user overrides to a built-in component.
--- @param comp DefaultComponent
--- @param override Component
--- @return DefaultComponent
local apply_override = function(comp, override)
    if type(override) ~= "table" then
        return comp
    end

    -- Respect user override for style
    local style = override.style
    if style then
        comp.___accept_returned_style = false
    end

    -- Respect user override for style
    if style or override.left_style or override.right_style then
        comp.theme_aware = false
    end

    for k, v in pairs(override) do
        local accepts = OVERRIDEABLE_TYPE_MAP[k]
        if accepts then
            local type_v = type(v)
            if accepts == type_v or accepts[type_v] then
                if type_v == "table" then
                    comp[k] = merge_value(comp[k], v)
                else
                    comp[k] = v
                end
            end
        end
    end

    return comp
end

return apply_override
