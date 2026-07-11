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


local resolve_value = function(comp, key, ...)
    local value = comp[key]
    if type(value) == "function" then
        return value(comp, ...)
    end
    return value
end


--- Run `pre_update(comp, session)` if present.
--- @param comp Component
--- @param session Session
M.pre_update = function(comp, session)
    resolve_value(comp, "pre_update", session)
end

--- Run `post_update(comp, session)` if present.
--- @param comp Component
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
--- @param comp Component
--- @param "left"|"right" side
--- @return SepStyle|CompStyle
M.side_style = function(comp, side)
    return comp[side == "left" and "left_style" or "right_style"] or SepStyle.SepBg
end

--- Run `update`, apply padding, return rendered string and optional style.
--- Non-string results become `""`.  Padding: number → both sides, table → left/right.
--- @param comp Component  Evaluated component; reads `update`, `padding`.
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

--- Resolve theme_aware for a component; falls back to `___builtin`.
--- @param comp Component|DefaultComponent
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
--- @param comp Component
--- @param session Session
--- @return boolean
M.hidden = function(comp, session)
    return resolve_value(comp, "hidden", session) == true
end

--- Normalize a style table by attaching `theme_aware` if not already set.
--- @param style? CompStyle
--- @param enable_theme_aware boolean
--- @return CompStyle|nil
M.normalize_style = function(style, enable_theme_aware)
    if type(style) == "table" and style.theme_aware == nil then
        style.theme_aware = enable_theme_aware
    end
    return style
end


---@type table<string, table<CompId, {[1]: any,[2]: integer}>>
local inherited_cache = {}

---@param comp ManagedComponent
---@param key string
---@param get_parent fun(id: CompId): ManagedComponent|nil
---@param merge fun(current: any, parent: any, n: integer): any
---@param initial_value? any
---@return any
---@return boolean
---@return integer
function M.resolve_inherited(
    comp,
    key,
    get_parent,
    merge,
    initial_value,
    ...
)
    local cid = comp.id
    local require_recomputes = initial_value ~= nil

    local key_cache
    if require_recomputes == false then
        key_cache = inherited_cache[key]
        local cached = key_cache and key_cache[cid]
        if cached then
            return cached[1], false, cached[2]
        end
    end

    local merged = initial_value or comp[key]
    if type(merged) == "function" then
        require_recomputes = true
        merged = merged(comp, ...)
    end

    local seen = {}
    local n = 0

    local parent_id = comp.___parent_id

    while parent_id and not seen[parent_id] do
        local parent = get_parent(parent_id)
        if parent == nil then
            break
        end
        seen[parent_id] = true

        local value = parent[key]
        if type(value) == "function" then
            require_recomputes = true
            value = value(parent, ...)
        end

        if value ~= nil then
            n = n + 1
            merged = merge(merged, value, n)
        end
        parent_id = parent.___parent_id
    end

    if not require_recomputes then
        local cache = { merged, n }
        if key_cache then
            key_cache[cid] = cache
        else
            inherited_cache[key] = {
                [cid] = cache,
            }
        end
    end


    return merged, require_recomputes, n
end

return M
