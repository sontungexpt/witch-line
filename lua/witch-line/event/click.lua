local M = {}

--- Register a click handler for a component.
--- Resolves `on_click` to a global function name and caches it on the component.
---@param comp ManagedComponent
---@return string handler_name  The global function name for the click handler.
M.register = function(comp)
    local cached = comp.___click_handler
    if cached then
        return cached
    end

    local on_click = comp.on_click
    local t = type(on_click)
    if t == "table" then
        local name = on_click.name
        if name and type(name) ~= "string" or name == "" then
            require("witch-line.util.notifier").error("on_click.name must be a non-empty string")
            return ""
        end
        cached = type(name) == "string" and name or nil
        on_click = on_click.callback
        t = type(on_click)
    end

    if t == "string" and _G[on_click] then
        cached = on_click
    elseif t == "function" then
        if not cached then
            cached = ("WLClickHandler" .. tostring(comp.id)):gsub("[^%w_]", "")
        end
        if not _G[cached] then
            _G[cached] = function(...) on_click(comp, ...) end
        end
    else
        require("witch-line.util.notifier").error("on_click must be a function or the name of a global function")
        return ""
    end

    rawset(comp, "___click_handler", cached)
    return cached
end

--- Unregister a click handler for a component.
--- Removes the global function and clears the cached handler name.
---@param comp ManagedComponent
M.unregister = function(comp)
    local name = comp.___click_handler
    if name then
        _G[name] = nil
        rawset(comp, "___click_handler", nil)
    end
end

return M
