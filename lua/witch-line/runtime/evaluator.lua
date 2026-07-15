local type, str_rep = type, string.rep

local M = {}

--- Execute pre-update callback.
--- @param comp ProxyComponent
--- @param session Session
M.pre_update = function(comp, session)
    local callback = comp.pre_update
    if type(callback) == "function" then
        callback(comp, session)
    end
end

--- Execute post-update callback.
--- @param comp ProxyComponent
--- @param session Session
M.post_update = function(comp, session)
    local callback = comp.post_update
    if type(callback) == "function" then
        callback(comp, session)
    end
end

--- Resolve component visibility.
--- @param comp ProxyComponent
--- @param session Session
--- @return boolean
M.hidden = function(comp, session)
    local is_hidden = comp.hidden
    if type(is_hidden) == "function" then
        return is_hidden(comp, session) == true
    end
    return is_hidden == true
end

--- Evaluate component value (calls `update`, applies padding).
--- Does NOT resolve styles, separators, or highlights.
--- @param comp ProxyComponent
--- @param session Session
--- @return string value
--- @return HighlightStyle|nil dynamic_style
M.evaluate = function(comp, session)
    local update = comp.update

    local result, style
    if type(update) == "function" then
        result, style = update(comp, session)
    else
        result = update
    end

    if type(result) ~= "string" or result == "" then
        return "", style
    end

    local padding = comp.padding
    local padding_type
    if padding == nil then
        padding = 1
        padding_type = "number"
    else
        padding_type = type(padding)
        if padding_type == "function" then
            padding = padding(comp, session)
            padding_type = type(padding)
        end
    end

    if padding_type == "number" then
        if padding > 0 then
            local pad = str_rep(" ", padding)
            return pad .. result .. pad, style
        end

        return result, style
    elseif padding_type == "table" then
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

--- Resolve theme-aware flag.
--- @param comp ProxyComponent
--- @param session Session
--- @return boolean
M.theme_aware = function(comp, session)
    local value = comp.theme_aware
    if type(value) == "function" then
        value = value(comp, session)
    end

    if value ~= nil then
        return value
    end

    return comp.___builtin or false
end

return M
