local bit = bit or require("bit")
local byte = string.byte

local M = {}

local FNV_PRIME_32 = 0x01000193
local FNV_OFFSET_32 = 0x811C9DC5

--- Calculates the FNV-1a hash of a string using 32-bit FNV parameters.
--- @param str string The input string to hash.
--- @return number The resulting hash value as a 32-bit integer.
M.fnv1a32 = function(str)
	local hash = FNV_OFFSET_32
	for i = 1, #str do
		local byte = byte(str, i)
		hash = bit.bxor(hash, byte)
		hash = bit.band(hash * FNV_PRIME_32, 0xFFFFFFFF) -- Ensure it stays within 32 bits
	end
	return hash
end

return M
