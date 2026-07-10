local type, select, str_rep = type, select, string.rep

local M = {}

--- @enum SepStyle
local SepStyle = {
    Inherited = 0,
    SepFg = 1,
    SepBg = 2,
    Reverse = 3,
}
M.SepStyle = SepStyle


local resolve_value = function(comp, key, session)
    local value = comp[key]
    if type(value) == "function" then
        return value(comp, session)
    end
    return value
end


--- Run `pre_update(comp, session)` if present.
--- @param comp ManagedComponent
--- @param session Session
M.pre_update = function(comp, session)
    resolve_value(comp, "pre_update", session)
end

--- Run `post_update(comp, session)` if present.
--- @param comp ManagedComponent
--- @param session Session
M.post_update = function(comp, session)
    resolve_value(comp, "post_update", session)
end


--- Return the internal hl_name storage field for a given side.
--- @param "left"|"right" side
--- @return "___left_hl_name"|"___right_hl_name"
M.hl_name_field = function(side)
    return side == "left" and "___left_hl_name" or "___right_hl_name"
end

--- Resolve the separator style for a side of a component.
--- Defaults to SepStyle.SepBg when the side style field is nil.
--- @param comp ManagedComponent
--- @param "left"|"right" side
--- @return SepStyle|CompStyle
M.side_style = function(comp, side)
    return comp[side == "left" and "left_style" or "right_style"] or SepStyle.SepBg
end

--- Run `update`, apply padding, return rendered string and optional style.
--- Non-string results become `""`.  Padding: number → both sides, table → left/right.
--- @param comp ManagedComponent  Evaluated component; reads `update`, `padding`.
--- @param session Session  Session context for memoized function calls.
--- @return string  Rendered text (empty string for non-string/nil results).
--- @return CompStyle|nil  Style override from `update`, or nil.
M.evaluate = function(comp, session)
    local result, style = resolve_value(comp, "update", session)

    if type(result) ~= "string" or result == "" then
        return "", style
    end

    local padding = comp.padding
    if padding == nil then
        padding = 1
    end

    local pt = type(padding)
    if pt == "number" then
        if padding > 0 then
            local pad = str_rep(" ", padding)
            return pad .. result .. pad, style
        end
        return result, style
    else
        if pt == "table" then
            local left = padding.left
            local right = padding.right

            if type(left) == "number" and left > 0 then
                result = str_rep(" ", left) .. result
            end
            if type(right) == "number" and right > 0 then
                result = result .. str_rep(" ", right)
            end
        end
        return result, style
    end
end


--- Resolve the minimum screen width constraint for a component.
--- Returns nil when the field is absent or resolves to a non-number.
--- @param comp ManagedComponent
--- @param session Session
--- @return integer|nil
M.min_screen_width = function(comp, session)
    local m = resolve_value(comp, "min_screen_width", session)
    return type(m) == "number" and m or nil
end

--- Resolve theme_aware for a component; falls back to `___builtin`.
--- @param comp ManagedComponent
--- @param session Session
--- @return boolean
M.theme_aware = function(comp, session)
    local auto = resolve_value(comp, "theme_aware", session)
    if auto ~= nil then
        return auto
    end
    --- Builtin component should be theme_aware
    return comp.___builtin or false
end

--- Determine whether a component should be hidden in the current context.
--- Returns true only when `hidden` resolves to exactly `true`.
--- @param comp ManagedComponent
--- @param session Session
--- @return boolean
M.hidden = function(comp, session)
    return resolve_value(comp, "hidden", session) == true
end

--- Normalize a style table by attaching `theme_aware` if not already set.
---@param style CompStyle|nil
---@param enable_theme_aware boolean
---@return CompStyle|nil
M.normalize_style = function(style, enable_theme_aware)
    if type(style) == "table" and style.theme_aware == nil then
        style.theme_aware = enable_theme_aware
    end
    return style
end



--- Replaces component aliases with the target component.
---
--- Every argument equal to one of the provided aliases is replaced with
--- `target`, preserving all other arguments.
---
--- @param args any[] Arguments to update in-place.
--- @param argc integer Number of valid arguments in `args`.
--- @param target ManagedComponent Component to substitute for matching aliases.
--- @param ... Component Aliases representing the current component.
M.replace_self_aliases = function(args, argc, target, ...)
    local alias_count = select("#", ...)

    for i = 1, argc do
        local arg = args[i]

        for j = 1, alias_count do
            if arg == select(j, ...) then
                args[i] = target
                break
            end
        end
    end
end

return M
