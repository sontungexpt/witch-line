local vim, type, pairs      = vim, type, pairs

-- Shared type-set tables (defined once to avoid per-entry allocation).
-- Each maps a set of acceptable Lua types for a given override key.
-- Note: "function" is a reserved word in Lua, so it must be quoted as a key.
local FN_TABLE              = { ["function"] = true, table = true }
local BOOL_FN               = { boolean = true, ["function"] = true }
local STR_FN                = { string = true, ["function"] = true }
local NUM_TABLE             = { number = true, table = true }
local BOOL_NUM              = { boolean = true, number = true }
-- local NUM_FN                = { number = true, ["function"] = true }
-- local ANY                   = { number = true, string = true, boolean = true, table = true, ["function"] = true }

-- Field-level type constraints for override values.
-- Each entry maps a component field name to the set of accepted Lua types.
-- The type check prevents users from setting fields to incompatible types.
local OVERRIDEABLE_TYPE_MAP = {
    padding     = NUM_TABLE,
    config      = "table",
    timing      = BOOL_NUM,
    lazy        = "boolean",
    style       = FN_TABLE,
    left_style  = FN_TABLE,
    right_style = FN_TABLE,
    left        = STR_FN,
    right       = STR_FN,
    hidden      = "function",
    flexible    = "number",
    theme_aware = BOOL_FN,
}

--- Recursively merge `from` into `to` for table values.
--- Lists (integer-indexed tables) are replaced entirely.
local function merge_value(to, from)
    if to == nil then return from end
    if from == nil then return to end
    if type(from) ~= "table" then return from end
    if next(to) == nil then return from end
    if next(from) == nil then return to end
    if vim.islist(to) and vim.islist(from) then return from end

    for k, v in pairs(from) do
        to[k] = merge_value(to[k], v)
    end
    return to
end

--- Apply user overrides to a built-in component.
--- @param comp DefaultComponent
--- @param override table
--- @return Component
local function apply_override(comp, override)
    if type(override) ~= "table" then
        return comp
    end

    if override.style then
        comp.___accept_returned_style = false
    end

    if override.style or override.left_style or override.right_style then
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
