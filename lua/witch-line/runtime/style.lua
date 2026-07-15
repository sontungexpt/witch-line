local nvim_get_hl = vim.api.nvim_get_hl
local type, pairs = type, pairs

local ManagedComps = require("witch-line.core.registry").ManagedComps

local M = {}

----------------------------------------------------------------------
-- Separator style enum
----------------------------------------------------------------------

---@enum SepStyle
local SepStyle = {
    Inherited = 0,
    SepFg = 1,
    SepBg = 2,
    Reverse = 3,
}
M.SepStyle = SepStyle

----------------------------------------------------------------------
-- Inherited value resolution (with caching)
----------------------------------------------------------------------

---@type table<string, table<CompId, {[1]: any,[2]:integer}>>
local inherited_cache = {}

--- Resolve a field through component inheritance.
--- Static results are cached; dynamic values bypass cache.
--- Without `merge`, the nearest parent value wins.
---@param comp ProxyComponent
---@param field string
---@param resolve_parent fun(id: CompId): ProxyComponent|nil
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

----------------------------------------------------------------------
-- Highlight definition helpers
----------------------------------------------------------------------

--- Resolve a highlight value (string/number/table) into a HighlightDef table.
--- Does NOT call nvim_set_hl. Pure resolution only.
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

--- Merge child highlight with a parent highlight.
--- Child properties take precedence (keep mode).
--- @param child? HighlightStyle
--- @param parent? HighlightStyle
--- @return HighlightDef|nil
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

----------------------------------------------------------------------
-- Main style resolution
----------------------------------------------------------------------

--- Resolve the main style for a component with inheritance/delegate.
--- @param comp ProxyComponent
--- @param resolve_parent fun(id: CompId): ProxyComponent|nil
--- @param dynamic_style? HighlightStyle
--- @param session Session
--- @return HighlightStyle|nil
--- @return boolean dynamic
--- @return integer inherit_count
M.resolve_main_style = function(comp, resolve_parent, dynamic_style, session, ...)
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

    --- Use local value only — check delegate style override
    if inherit_count == 0 then
        local delegate = comp.delegate
        if type(delegate) == "table" then
            local delegate_style = delegate.style
            if delegate_style then
                style = resolve_hl(delegate_style)
                return style, dynamic, inherit_count
            end
        end
    end

    return style, dynamic, inherit_count
end

----------------------------------------------------------------------
-- Side style resolution
----------------------------------------------------------------------

--- Resolve the style for a side separator.
--- @param comp ProxyComponent
--- @param side "left"|"right"
--- @param session Session
--- @return HighlightStyle|SepStyle|nil style
--- @return boolean dynamic
M.resolve_side_style = function(comp, side, session)
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

----------------------------------------------------------------------
-- Separator style conversion
----------------------------------------------------------------------

--- Convert a separator style enum to a highlight style based on main style.
---@param sep_style SepStyle
---@param main_style? HighlightStyle
---@return HighlightStyle|nil
M.convert_sep_style = function(sep_style, main_style)
    if main_style == nil then
        return nil
    end

    local resolved = resolve_hl(main_style)
    local fg = resolved.fg or resolved.foreground
    local bg = resolved.bg or resolved.background

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

----------------------------------------------------------------------
-- Resolve side separator value (string)
----------------------------------------------------------------------

--- Resolve an inherited side value (e.g. separator string).
--- Static: returns nil if invalid. Dynamic: returns "" if invalid.
--- @param comp ProxyComponent
--- @param side "left"|"right"
--- @param resolve_parent fun(id: CompId): ProxyComponent|nil
--- @param session Session
--- @return string|nil value
--- @return boolean dynamic
M.resolve_side_value = function(comp, side, resolve_parent, session)
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

return M
