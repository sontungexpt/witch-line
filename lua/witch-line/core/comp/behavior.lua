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

---@type table<string, table<CompId, {[1]: any, [2]: integer}>>
local inherited_cache = {}

---@param comp ManagedComponent
---@param field string Field name to resolve.
---@param resolve_parent_fn fun(id: CompId): ManagedComponent|nil
---@param merge_fn? fun(current: any, parent: any, depth: integer): any
---@param initial? any Initial value before inheritance.
---@param ... any Arguments passed to dynamic fields.
---@return any value Resolved value.
---@return boolean dynamic Whether result depends on runtime evaluation.
---@return integer count Number of inherited values merged.
local resolve_inherited_value = function(
    comp,
    field,
    resolve_parent_fn,
    merge_fn,
    initial,
    ...
)
    local cid = comp.id
    local dynamic = initial ~= nil

    local field_cache

    -- Static inheritance can be cached permanently.
    if not dynamic then
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
        result = result(comp, ...)
    end


    local visited = {}
    local inherit_count = 0

    local parent_id = comp.___parent_id

    while parent_id and not visited[parent_id] do
        visited[parent_id] = true

        local parent = resolve_parent_fn(parent_id)
        if parent == nil then
            break
        end

        local value = parent[field]

        if type(value) == "function" then
            dynamic = true
            value = value(parent, ...)
        end

        if value ~= nil then
            inherit_count = inherit_count + 1

            -- No merge function, use first parent value as-is.
            if merge_fn == nil then
                result = value
                break
            end

            -- Merge function present, apply it to accumulate results.
            result = merge_fn(result, value, inherit_count)
        end


        parent_id = parent.___parent_id
    end


    -- Only cache values that do not depend on runtime arguments.
    if not dynamic then
        local cache = {
            result,
            inherit_count,
        }

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
M.resolve_inherited_value = resolve_inherited_value

--- Run `pre_update(comp, session)` if present.
---@param comp ManagedComponent
M.pre_update = function(comp, ...)
    local callback = comp.pre_update
    if type(callback) == "function" then
        callback(comp, ...)
    end
end


--- Run `post_update(comp, session)` if present.
---@param comp ManagedComponent
M.post_update = function(comp, ...)
    local callback = comp.post_update
    if type(callback) == "function" then
        callback(comp, ...)
    end
end


--- Run `update(comp, session)` and apply component padding.
---
--- Non-string results become an empty string.
--- Numeric padding applies to both sides.
--- Table padding supports `left` and `right`.
---
---@param comp ManagedComponent Component being evaluated.
---@return string Rendered component output.
---@return CompStyle|nil Optional style override.
M.evaluate = function(comp, ...)
    local update = comp.update

    local result, style
    if type(update) == "function" then
        result, style = update(comp, ...)
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


--- Resolve whether component should adapt to current theme.
---@param comp ManagedComponent
---@return boolean
M.theme_aware = function(comp, ...)
    local value = comp.theme_aware
    if type(value) == "function" then
        value = value(comp, ...)
    end

    if value ~= nil then
        return value
    end

    return comp.___builtin or false
end


--- Resolve whether component should be hidden.
---@param comp ManagedComponent
---@return boolean
M.hidden = function(comp, ...)
    local value = comp.hidden

    if type(value) == "function" then
        value = value(comp, ...)
    end

    return value == true
end

--- Normalize a style table by attaching `theme_aware` if not already set.
--- @param style CompStyle
--- @param enable_theme_aware boolean
--- @return CompStyle
local normalize_style = function(style, enable_theme_aware)
    if type(style) == "table" and style.theme_aware == nil then
        style.theme_aware = enable_theme_aware
    end
    return style
end
M.normalize_style = normalize_style

--- Resolve the style for a component.
--- @param comp ManagedComponent
--- @param resolve_parent_fn fun(id: CompId): ManagedComponent|nil
--- @param merge_fn fun(style: CompStyle, ...: CompStyle): CompStyle
--- @param override_style? CompStyle
--- @param theme_aware boolean
--- @return CompStyle
--- @return boolean
--- @return integer
M.style = function(comp, resolve_parent_fn, merge_fn, override_style, theme_aware, ...)
    if comp.___accept_returned_style ~= false
        and (
            type(override_style) == "string"
            or type(override_style) == "table"
        )
    then
        override_style = override_style
    else
        override_style = nil
    end

    local style, force_recompute, pcount = resolve_inherited_value(
        comp,
        "style",
        resolve_parent_fn,
        merge_fn,
        override_style,
        ...
    )
    normalize_style(style, theme_aware)
    return style, force_recompute, pcount
end

---Resolve an inherited side value.
---
---Side values are expected to be strings (for example separators).
---Invalid static values are ignored, while invalid dynamic values are
---replaced with an empty string to avoid breaking runtime rendering.
---@param comp ManagedComponent Component to resolve.
---@param side string Side field name.
---@param resolve_parent_fn fun(id: CompId): ManagedComponent|nil Resolve parent component.
---@param ... any Arguments passed to dynamic fields.
---@return string|nil value Resolved side string.
---@return boolean dynamic Whether the value is dynamic.
function M.side(comp, side, resolve_parent_fn, ...)
    -- Resolve the side value from the component or its parent chain.
    -- No merge is needed because the nearest inherited value wins.
    local value, dynamic = resolve_inherited_value(
        comp,
        side,
        resolve_parent_fn,
        nil,
        nil,
        ...
    )

    -- Dynamic fields may depend on runtime state and must always return
    -- a safe string value for the renderer.
    if dynamic then
        return type(value) == "string" and value or "", dynamic
    end

    -- Static values are validated strictly.
    -- Invalid values mean the side is not configured
    return type(value) == "string" and value or nil, dynamic
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

---@param comp ManagedComponent
---@param side "left"|"right"
---@param main_style? CompStyle
---@param theme_aware boolean
---@param ... any Runtime arguments passed to dynamic styles.
---@return CompStyle|nil style Resolved highlight style.
---@return boolean dynamic Whether style depends on runtime evaluation.
---@return boolean inherited Whether side uses component highlight directly.
M.resolved_side_style = function(
    comp,
    side,
    main_style,
    theme_aware,
    ...
)
    local side_style = M.side_style(comp, side)

    local dynamic = false
    local t = type(side_style)


    -- Resolve dynamic side style.
    if t == "function" then
        dynamic = true
        side_style = side_style(comp, ...)
        t = type(side_style)
    end


    -- Resolve built-in separator styles.
    if t == "number" then
        if not main_style then
            return nil, dynamic, false
        end

        local fg = main_style.fg or main_style.foreground
        local bg = main_style.bg or main_style.background

        if side_style == SepStyle.SepFg then
            side_style = {
                fg = fg,
                bg = "NONE",
            }
        elseif side_style == SepStyle.SepBg then
            side_style = {
                fg = bg,
                bg = "NONE",
            }
        elseif side_style == SepStyle.Reverse then
            side_style = {
                fg = bg,
                bg = fg,
            }
        elseif side_style == SepStyle.Inherited then
            return nil, dynamic, true
        else
            return nil, dynamic, false
        end
    end


    -- Normalize before leaving behavior layer.
    ---@cast side_style CompStyle
    return normalize_style(side_style, theme_aware), dynamic, false
end

return M
