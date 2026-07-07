--- Utility functions for table manipulation and serialization
local M = {}

local type, next, pairs = type, next, pairs

M.unique_list = function(list)
    local seen, result, n = {}, {}, 0
    for i = 1, #list do
        local v = list[i]
        if not seen[v] then
            seen[v] = true
            n = n + 1
            result[n] = v
        end
    end
    return result, n
end

M.array_equal = function(a, b)
    if a == b then return true end
    local len = #a
    if len ~= #b then return false end
    local count = {}
    for i = 1, len do
        local v = a[i]
        count[v] = (count[v] or 0) + 1
    end
    for i = 1, len do
        local v = b[i]
        local c = count[v]
        if not c then return false end
        count[v] = c - 1
        if count[v] == 0 then count[v] = nil end
    end
    return next(count) == nil
end

M.shallow_copy = function(tbl)
    local copy = {}
    for k, v in pairs(tbl) do
        copy[k] = v
    end
    return copy
end

M.is_superset = function(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return false
    end
    local map = {}
    for i = 1, #a do
        map[a[i]] = true
    end
    for i = 1, #b do
        if not map[b[i]] then return false end
    end
    return true
end

return M
