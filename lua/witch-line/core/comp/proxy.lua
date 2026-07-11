local type, unpack, setmetatable = type, unpack, setmetatable

local resolve_plain_field = require("witch-line.core.resolver").resolve_plain_field

--- @class ProxyComponent : ManagedComponent

local M = {}

local SESSION, RAW_COMP = {}, {}

local bind

--- Returns the raw component behind a proxy.
---
--- @param proxy ProxyComponent
--- @return ManagedComponent
M.get_raw_comp = function(proxy)
    return proxy[RAW_COMP]
end

--- Returns the session associated with a proxy.
---
--- @param proxy ProxyComponent
--- @return Session
M.get_session = function(proxy)
    return proxy[SESSION]
end

local mt = {
    __newindex = function(proxy, key, value)
        proxy[RAW_COMP][key] = value
    end,

    __index = function(proxy, key)
        local raw_comp = proxy[RAW_COMP]
        local value, origin = resolve_plain_field(raw_comp, key)

        if type(value) ~= "function" then
            return value
        end

        return function(...)
            local session = proxy[SESSION]
            local cache = session:cache(origin)

            if origin == raw_comp then
                return cache:memo(value, ...)
            end

            local argc = select("#", ...)
            if argc == 0 then
                return cache:memo(value)
            end

            local ref_proxy
            local args = { ... }
            for i = 1, argc do
                local arg = args[i]
                if arg == raw_comp or arg == proxy then
                    --lazy bind
                    ref_proxy = ref_proxy or bind(origin, session)
                    args[i] = ref_proxy
                end
            end

            return cache:memo(value, unpack(args))
        end
    end,
}


--- Creates a session-bound proxy for a component.
---
--- The proxy transparently resolves referenced fields, memoizes callback
--- results, and ensures callbacks receive the correct component instance.
---
--- @param comp Component
--- @param session Session
--- @return ProxyComponent
bind = function(comp, session)
    return setmetatable({
        id = comp.id,
        [RAW_COMP] = comp,
        [SESSION] = session,
    }, mt)
end
M.bind = bind

return M
