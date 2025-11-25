local bit = require("bit")
local bor, band, lshift = bit.bor, bit.band, bit.lshift

local BitMask = {}

--- Marks specific indices to be skipped during the merging process.
--- @param bitmasks integer The current bitmask representing indices to skip.
--- @param bit_idx integer The index to mark for skipping. (Start from 0)
--- @return integer new_mask The updated bitmask with the specified index marked for skipping.
BitMask.mark_bit = function(bitmasks, bit_idx)
	return bor(bitmasks, lshift(1, bit_idx))
end

--- Checks if a specific index is marked to be skipped in the bitmask.
--- @param bitmasks integer The bitmask representing indices to skip.
--- @param bit_idx integer The index to mark for skipping. (Start from 0)
--- @return boolean is_skipped True if the index is marked to be skipped, false otherwise.
BitMask.is_marked = function(bitmasks, bit_idx)
	return band(bitmasks, lshift(1, bit_idx)) ~= 0
end

return BitMask
