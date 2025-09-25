local ffi = require("ffi")

local M = {}

local FNV_PRIME_32  = 0x01000193ULL
local FNV_OFFSET_32 = 0x811C9DC5ULL

ffi.cdef[[
typedef uint32_t fnv32_t;
typedef unsigned char uint8_t;
]]

--- Calculates the FNV-1a 32-bit hash of a string.
--- Uses FFI uint32_t for automatic 32-bit overflow (no bit.band needed).
M.fnv1a32 = function(str)
    local len = #str
    local ptr = ffi.cast("const uint8_t*", str)
    local hash = ffi.new("fnv32_t", FNV_OFFSET_32)

    for i = 0, len - 1 do
        hash = bit.bxor(hash, ptr[i]) * FNV_PRIME_32
    end
    return tonumber(hash)
end

--- Calculates the FNV-1a 32-bit hash of concatenated strings.
--- Accepts an array of strings and optional i..j range.
M.fnv1a32_concat = function(strs, i, j)
    local first = i or 1
    local last  = j or #strs
    local hash = ffi.new("fnv32_t", FNV_OFFSET_32)

    for l = first, last do
        local str = strs[l]
        local len = #str
        local ptr = ffi.cast("const uint8_t*", str)
        for k = 0, len - 1 do
            hash = bit.bxor(hash, ptr[k]) * FNV_PRIME_32
        end
    end
    return tonumber(hash)
end

return M