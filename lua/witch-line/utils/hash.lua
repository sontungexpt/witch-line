local ffi = require("ffi")
local bit = bit or require("bit")

local FNV_PRIME_32  = 0x01000193
local FNV_OFFSET_32 = 0x811C9DC5
local FNV_MASK_32   = 0xffffffff

local M = {}

--- Calculates the FNV-1a 32-bit hash of a string.
--- Uses FFI uint32_t for automatic 32-bit overflow (no bit.band needed).
--- @param str string The input string to hash.
--- @return integer hash The resulting FNV-1a 32-bit hash.
M.fnv1a32 = function(str)
    local len = #str
    local ptr = ffi.cast("const uint8_t*", str)
    local hash = FNV_OFFSET_32
    local bxor, band = bit.bxor, bit.band
    for i = 0, len - 1 do
      hash = band((bxor(hash, ptr[i]) * FNV_PRIME_32), FNV_MASK_32)
    end
    return hash
end

--- Calculates the FNV-1a 32-bit hash of concatenated strings.
--- Accepts an array of strings and optional i..j range.
--- @param strs string[] The array of strings to hash.
--- @param i integer|nil The starting index (1-based). Defaults to 1.
--- @param j integer|nil The ending index (1-based). Defaults to #strs.
--- @return integer hash The resulting FNV-1a 32-bit hash.
M.fnv1a32_fold = function(strs, i, j)
    local last = j or #strs
    if last > 100 then
        return M.fnv1a32(table.concat(strs, "", i or 1, last))
    end

    local hash = FNV_OFFSET_32
    local bxor, band = bit.bxor, bit.band
    for l = i or 1, last do
        local str = strs[l]
        local len = #str
        local ptr = ffi.cast("const uint8_t*", str)
        for k = 0, len - 1 do
          hash = band((bxor(hash, ptr[k]) * FNV_PRIME_32), FNV_MASK_32)
        end
    end
    return hash
end


return M
