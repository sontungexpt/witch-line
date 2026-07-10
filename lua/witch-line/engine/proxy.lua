local type, unpack, setmetatable = type, unpack, setmetatable

local Resolver = require("witch-line.engine.resolver")
local lookup_plain_value = Resolver.lookup_plain_value

local CompAPI = require("witch-line.core.component_api")


local M = {}

local SESSION = {}
local RAW_COMP = {}

local bind

local mt = {
    __newindex = function(proxy, key, value)
        proxy[RAW_COMP][key] = value
    end,

    __index = function(proxy, key)
        local raw_comp = proxy[RAW_COMP]

        local value, origin = lookup_plain_value(raw_comp, key)

        if value == nil or type(value) ~= "function" then
            return value
        end

        return function(...)
            local session = proxy[SESSION]
            local cache = session:cache(origin)

            if origin == raw_comp then
                return cache:memo(value, ...)
            end

            local target = bind(origin, session)

            local argc = select("#", ...)
            local args = { ... }

            CompAPI.replace_self_aliases(
                args,
                argc,
                target,
                raw_comp,
                proxy
            )

            return cache:memo(value, unpack(args))
        end
    end,
}

--- @class ProxyComponent : ManagedComponent

--- Creates a session-bound proxy for a component.
---
--- The proxy transparently resolves referenced fields, memoizes callback
--- results, and ensures callbacks receive the correct component instance.
---
--- @param comp ManagedComponent
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

return M
