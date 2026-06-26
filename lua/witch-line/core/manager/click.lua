local M = {}

M.register = function(comp, on_click)
    local cached = comp._click_handler
    if cached then
        return cached
    end

    local t = type(on_click)
    if t == "table" then
        local name = on_click.name
        if name and type(name) ~= "string" or name == "" then
            require("witch-line.utils.notifier").error("on_click.name must be a non-empty string")
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
        require("witch-line.utils.notifier").error("on_click must be a function or the name of a global function")
        return ""
    end

    comp._click_handler = cached
    return cached
end

M.unregister = function(comp)
    local name = comp._click_handler
    if name then
        _G[name] = nil
        comp._click_handler = nil
    end
end

return M
