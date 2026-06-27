local vim, type, rawset, pairs = vim, type, rawset, pairs

-- Shared type-set tables (defined once to avoid per-entry allocation).
-- Each maps a set of acceptable Lua types for a given override key.
-- Note: "function" is a reserved word in Lua, so it must be quoted as a key.
local FN_TABLE                 = { ["function"] = true, table = true }
local BOOL_FN                  = { boolean = true, ["function"] = true }
local NUM_FN                   = { number = true, ["function"] = true }
local STR_FN                   = { string = true, ["function"] = true }
local NUM_TABLE                = { number = true, table = true }
local BOOL_NUM                 = { boolean = true, number = true }
local ANY                      = { number = true, string = true, boolean = true, table = true, ["function"] = true }

-- Field-level type constraints for override values.
-- Each entry maps a component field name to the set of accepted Lua types.
-- The type check prevents users from setting fields to incompatible types.
local OVERRIDEABLE_TYPE_MAP    = {
    padding          = NUM_TABLE,
    static           = ANY,
    timing           = BOOL_NUM,
    lazy             = "boolean",
    style            = FN_TABLE,
    min_screen_width = NUM_FN,
    hide             = BOOL_FN,
    left_style       = FN_TABLE,
    right_style      = FN_TABLE,
    left             = STR_FN,
    right            = STR_FN,
    flexible         = "number",
    auto_theme       = BOOL_FN,
}

--- Recursively merge `from` into `to` for table values.
--- Non-table values from `from` replace `to` directly.
--- When `skip_type_check` is false (or omitted), type mismatches keep the original.
--- Lists (integer-indexed tables) are replaced entirely rather than merged.
--- @param to any  Original value (may be nil).
--- @param from any  Override value to merge in.
--- @param skip_type_check? boolean  When true, skip the type-compatibility guard.
--- @return any  Merged result.
local function merge_override_value(to, from, skip_type_check)
    if to == nil then
        return from
    elseif from == nil then
        return to
    elseif not skip_type_check and type(to) ~= type(from) then
        return to
    elseif type(from) ~= "table" then
        return from
    elseif next(to) == nil then
        return from
    elseif next(from) == nil then
        return to
    elseif vim.islist(to) and vim.islist(from) then
        return from
    end

    for k, v in pairs(from) do
        to[k] = merge_override_value(to[k], v, skip_type_check)
    end
    return to
end

--- Apply user overrides to a built-in component.
--- Side effects:
---   - Sets `_use_returned_style = false` when `style` is overridden.
---   - Disables `auto_theme` when `style`, `left_style`, or `right_style` is overridden.
--- @param comp DefaultComponent
--- @param override table  User-provided override table.
--- @return Component  The same `comp` table, modified in-place.
local function apply_override(comp, override)
    if type(override) ~= "table" then
        return comp
    end

    if override.style then
        comp._use_returned_style = false
    end
    if override.style or override.left_style or override.right_style then
        comp.auto_theme = false
    end

    for k, v in pairs(override) do
        local accepts = OVERRIDEABLE_TYPE_MAP[k]
        if accepts then
            local type_v = type(v)
            local ok = accepts == type_v or accepts[type_v]
            if ok then
                if type_v == "table" then
                    rawset(comp, k, merge_override_value(comp[k], v, true))
                else
                    rawset(comp, k, v)
                end
            end
        end
    end

    return comp
end

return apply_override
