local ffi = require("ffi")
local bit = bit or require("bit")

local M = {}

local FNV_PRIME_32  = 0x01000193
local FNV_OFFSET_32 = 0x811C9DC5

ffi.cdef[[
typedef unsigned char uint8_t;
]]

--- Calculates the FNV-1a hash of a string using 32-bit FNV parameters.
--- Optimized with FFI pointer access.
M.fnv1a32 = function(str)
    local len = #str
    local ptr = ffi.cast("const uint8_t*", str)
    local hash = FNV_OFFSET_32

    for i = 0, len - 1 do
        hash = bit.bxor(hash, ptr[i])
        hash = bit.band(hash * FNV_PRIME_32, 0xFFFFFFFF)
    end
    return hash
end

--- Calculates the FNV-1a hash of concatenated strings.
--- Accepts an array of strings and optional i..j range.
M.fnv1a32_concat = function(strs, i, j)
    local hash = FNV_OFFSET_32
    local first = i or 1
    local last  = j or #strs

    for l = first, last do
        local str = strs[l]
        local len = #str
        local ptr = ffi.cast("const uint8_t*", str)
        for k = 0, len - 1 do
            hash = bit.bxor(hash, ptr[k])
            hash = bit.band(hash * FNV_PRIME_32, 0xFFFFFFFF)
        end
    end
    return hash
end

return M