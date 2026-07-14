local nvim_get_hl = vim.api.nvim_get_hl
local type, pairs, str_rep = type, pairs, string.rep

local M = {}

---@enum SepStyle
local SepStyle = {
    Inherited = 0,
    SepFg = 1,
    SepBg = 2,
    Reverse = 3,
}
M.SepStyle = SepStyle

---@type table<string, table<CompId, {[1]: any,[2]:integer}>>
local inherited_cache = {}

---Resolve a field through component inheritance.
---Static results are cached; dynamic values bypass cache.
---Without `merge`, the nearest parent value wins.
---@param comp ManagedComponent
---@param field string
---@param resolve_parent fun(id: CompId): ManagedComponent|nil
---@param merge? fun(current: any, parent: any, depth: integer): any
---@param initial? any
---@param session Session
---@param ...any
---@return any value
---@return boolean dynamic
---@return integer depth
local resolve_inherited_value = function(
    comp,
    field,
    resolve_parent,
    merge,
    initial,
    session,
    ...
)
    local cid = comp.id
    local dynamic = initial ~= nil

    local field_cache

    if dynamic == false then
        field_cache = inherited_cache[field]

        local cached = field_cache and field_cache[cid]

        if cached then
            return cached[1], false, cached[2]
        end
    end

    local result = initial
    if result == nil then
        result = comp[field]
    end

    if type(result) == "function" then
        dynamic = true
        result = result(comp, session, ...)
    end

    local visited = {
        [cid] = true,
    }
    local inherit_count = 0

    local parent_id = comp.___parent_id

    while parent_id and not visited[parent_id] do
        visited[parent_id] = true

        local parent = resolve_parent(parent_id)
        if parent == nil then
            break
        end

        local value = parent[field]

        if type(value) == "function" then
            dynamic = true
            value = value(parent, session, ...)
        end

        if value ~= nil then
            inherit_count = inherit_count + 1

            if merge == nil then
                result = value
                break
            end

            result = merge(result, value, inherit_count)
        end

        parent_id = parent.___parent_id
    end

    if dynamic == false then
        local cache = { result, inherit_count }

        if field_cache then
            field_cache[cid] = cache
        else
            inherited_cache[field] = {
                [cid] = cache,
            }
        end
    end

    return result, dynamic, inherit_count
end

--- Execute pre update callback.
--- @param comp ManagedComponent
--- @param session Session
M.pre_update = function(comp, session)
    local callback = comp.pre_update
    if type(callback) == "function" then
        callback(comp, session)
    end
end


--- Execute post update callback.
--- @param comp ManagedComponent
--- @param session Session
M.post_update = function(comp, session)
    local callback = comp.post_update
    if type(callback) == "function" then
        callback(comp, session)
    end
end

--- Evaluate component value and optional style override.
--- @param comp ManagedComponent
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

    if padding == nil then
        padding = 1
    end

    local padding_type = type(padding)

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

--- Resolve theme-aware component value.
--- @param comp ManagedComponent
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

--- Resolve component visibility.
--- @param comp ManagedComponent
--- @param session Session
--- @return boolean
M.hidden = function(comp, session)
    local is_hidden = comp.hidden
    if type(is_hidden) == "function" then
        return is_hidden(comp, session) == true
    end
    return is_hidden == true
end


--- Resolve an inherited side value (e.g. separator string).
--- Static: returns nil if invalid. Dynamic: returns "" if invalid.
--- @param comp ManagedComponent
--- @param side "left"|"right"
--- @param resolve_parent fun(id: CompId): ManagedComponent|nil
--- @param session Session
--- @return string|nil value
--- @return boolean dynamic
function M.side(comp, side, resolve_parent, session)
    local value, dynamic = resolve_inherited_value(
        comp,
        side,
        resolve_parent,
        nil,
        nil,
        session
    )

    if dynamic then
        return type(value) == "string" and value or "", dynamic
    end

    return type(value) == "string" and value or nil, dynamic
end


---@param value? HighlightDef|string|number
---@return HighlightDef
local resolve_hl = function(value)
    local t = type(value)
    local theme_aware = nil
    if t == "table" then
        theme_aware = value.theme_aware
        local link = value.link
        if link == nil then
            return value
        end

        --- link to other highlight
        value = link
        t = type(value)
    end

    local hl
    if t == "string" then
        hl = nvim_get_hl(0, {
            name = value,
            create = false,
            link = false
        })

        --- @cast hl HighlightDef
        hl.theme_aware = theme_aware
        return hl
    elseif t == "number" then
        -- id must be a positive integer
        if value < 1 then
            return {}
        end
        hl = nvim_get_hl(0, {
            id = value,
            create  = false,
            link = false
        })
        --- @cast hl HighlightDef
        hl.theme_aware = theme_aware
        return hl
    end
    error("Invalid highlight value: " .. tostring(value) .. " type: " .. t)
end

--- Merge child highlight with a parent highlight or highlight group name.
--- Child properties take precedence (`keep` mode).
--- Parent can be a table (with optional `link` field) or a highlight group name string.
---
--- We do not move it to highlight module because we want only component know how they get the style
---
--- @param child? HighlightStyle The child highlight definition (fields take precedence).
--- @param parent? HighlightStyle The parent highlight definition or group name.
--- @return HighlightDef|nil merged The merged highlight table (or the child table if no merge occurred).
local merge_hl = function(child, parent)
    local child_style = resolve_hl(child)
    local parent_style = resolve_hl(parent)

    if child_style == nil then
        return parent_style
    elseif parent_style == nil then
        return child_style
    end

    local merged = {}

    -- Parent first
    for k, v in pairs(parent_style) do
        merged[k] = v
    end

    -- Child override
    for k, v in pairs(child_style) do
        merged[k] = v
    end

    return merged
end

--- Resolve the style for a component.
--- @param comp ManagedComponent
--- @param resolve_parent fun(id: CompId): ManagedComponent|nil
--- @param dynamic_style? HighlightStyle
--- @param session Session
--- @return HighlightStyle|nil
--- @return boolean
--- @return integer
M.style = function(comp, resolve_parent, dynamic_style, session, ...)
    local dynamic_style_type = type(dynamic_style)
    if comp.___accept_returned_style == false
        or (
            dynamic_style_type ~= "string"
            and dynamic_style_type ~= "table"
        )
    then
        dynamic_style = nil
    end

    local style, dynamic, inherit_count = resolve_inherited_value(
        comp,
        "style",
        resolve_parent,
        merge_hl,
        dynamic_style,
        session,
        ...
    )

    if style == nil then
        return nil, dynamic, inherit_count
    end

    --- Use local value only
    if inherit_count == 0 then
        local delegate = comp.delegate
        if type(delegate) == "table" then
            local delegate_id = delegate.style
            if delegate_id then
                --- Link to the delegate's style
                local resolve_hl_name = require("witch-line.runtime.resolver").hl_name
                style = resolve_hl_name(delegate_id)
                return style, dynamic, inherit_count
            end
        end
    end

    return style, dynamic, inherit_count
end

--- Convert a separator style to a highlight style.
---@param sep_style SepStyle
---@param main_style? HighlightStyle
---@return HighlightStyle|nil
M.convert_sep_style = function(sep_style, main_style)
    if main_style == nil then
        return nil
    end

    local fg = main_style.fg or main_style.foreground
    local bg = main_style.bg or main_style.background

    local converted
    if sep_style == SepStyle.SepFg then
        converted = {
            fg = fg,
            bg = "NONE",
        }
    elseif sep_style == SepStyle.SepBg then
        converted = {
            fg = bg,
            bg = "NONE",
        }
    elseif sep_style == SepStyle.Reverse then
        converted = {
            fg = bg,
            bg = fg,
        }
    elseif sep_style == SepStyle.Inherited then
        return main_style
    end

    return converted
end

---@param comp ManagedComponent
---@param side "left"|"right"
---@param theme_aware boolean
---@param session Session Runtime arguments passed to dynamic styles.
---@return HighlightStyle|SepStyle|nil style Resolved highlight style.
---@return boolean dynamic Whether style depends on runtime evaluation.
M.side_style = function(
    comp,
    side,
    theme_aware,
    session
)
    local field = side == "left" and "left_style" or "right_style"
    local side_style = comp[field] or SepStyle.SepBg

    local dynamic = false
    local t = type(side_style)

    -- Resolve dynamic side style.
    if t == "function" then
        dynamic = true
        side_style = side_style(comp, session)
        t = type(side_style)
    end

    if t == "table" then
        return side_style, dynamic
    elseif t == "number" then
        return side_style, dynamic
    elseif t == "string" then
        return side_style, dynamic
    end

    return nil, dynamic
end



--- Return the internal hl_name storage field for a given side.
--- @param side "left"|"right"
--- @return string
M.hl_name_field = function(side)
    return side == "left" and "___left_hl_name" or "___right_hl_name"
end

return M
