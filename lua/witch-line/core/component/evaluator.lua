local type, str_rep = type, string.rep

local M = {}

--- @enum SepStyle
local SepStyle = {
    Inherited = 0,
    SepFg = 1,
    SepBg = 2,
    Reverse = 3,
}
M.SepStyle = SepStyle


--- Resolve a field value: call functions with session memo, pass through others.
--- @param comp ManagedComponent  Owner component, passed to function calls.
--- @param key string  The field key to resolve.
--- @param session Session  Session context; nil means no memoization.
--- @return any  Resolved value (function return or literal).
local function resolve_value(comp, key, session)
    local value = comp[key]
    if type(value) == "function" then
        return session.memo(value, comp, session)
    end
    return value
end

--- Call a lifecycle field if it is a function.
--- @param field string  Component field name (e.g. `"init"`, `"pre_update"`).
--- @param comp ManagedComponent  Passed as `self` to the callback.
local function call_lifecycle(field, comp)
    local value = comp[field]
    if type(value) == "function" then
        value(comp)
    end
end

--- Emit the pre_update lifecycle hook.
--- @param comp ManagedComponent
M.emit_pre_update = function(comp)
    call_lifecycle("pre_update", comp)
end

--- Emit the post_update lifecycle hook.
--- @param comp ManagedComponent
M.emit_post_update = function(comp)
    call_lifecycle("post_update", comp)
end

--- Emit the init lifecycle hook.
--- @param comp ManagedComponent
M.emit_init = function(comp)
    call_lifecycle("init", comp)
end

--- Return the internal hl_name storage field for a given side.
--- @param "left"|"right" side
--- @return "_left_hl_name"|"_right_hl_name"
M.hl_name_field = function(side)
    return side == "left" and "_left_hl_name" or "_right_hl_name"
end

--- Resolve the separator style for a side of a component.
--- Defaults to SepStyle.SepBg.
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

    if type(result) ~= "string" then
        result = ""
    elseif result ~= "" then
        local padding = comp.padding
        if padding == nil then padding = 1 end
        local pt = type(padding)
        if pt == "number" and padding > 0 then
            local pad = str_rep(" ", padding)
            result = pad .. result .. pad
        elseif pt == "table" then
            local left = padding.left
            if left == nil then left = 0 end
            local right = padding.right
            if right == nil then right = 0 end

            if type(left) == "number" and left > 0 then
                result = str_rep(" ", left) .. result
            end
            if type(right) == "number" and right > 0 then
                result = result .. str_rep(" ", right)
            end
        end
    end

    return result, style
end


--- Resolve the minimum screen width constraint for a component.
--- @param comp ManagedComponent
--- @param session Session
--- @return integer|nil
M.min_screen_width = function(comp, session)
    local m = resolve_value(comp, "min_screen_width", session)
    return type(m) == "number" and m or nil
end

--- Resolve auto_theme for a component; falls back to `_plug_provided`.
--- @param comp ManagedComponent
--- @param session Session
--- @return boolean
M.auto_theme = function(comp, session)
    local auto = resolve_value(comp, "auto_theme", session)
    if auto ~= nil then
        return auto
    end
    return comp._plug_provided or false
end

--- Determine whether a component should be hidden in the current context.
--- @param comp ManagedComponent
--- @param session Session
--- @return boolean
M.hidden = function(comp, session)
    return resolve_value(comp, "hidden", session) == true
end



return M
