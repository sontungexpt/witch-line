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
    if a == b then
        return true
    end

    local len = #a
    if len ~= #b then
        return false
    end

    -- Count element occurrences in array `a`
    local count = {}
    for i = 1, len do
        local v = a[i]
        count[v] = (count[v] or 0) + 1
    end
    for i = 1, len do
        local v = b[i]
        local c = count[v]
        if not c then
            -- Element in `b` not found in `a`
            return false
        end
        if c == 1 then
            -- Remove entry when count reaches zero to keep table small
            count[v] = nil
        else
            count[v] = c - 1
        end
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
    for _, v in ipairs(a) do
        map[v] = true
    end

    for _, v in ipairs(b) do
        if not map[v] then
            return false
        end
    end
    return true
end

return M
