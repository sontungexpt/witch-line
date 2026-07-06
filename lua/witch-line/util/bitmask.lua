local bit = require("bit")
local band, bor, lshift = bit.band, bit.bor, bit.lshift

local M = {}

M.is_marked = function(mask, bit_index)
    return band(mask, lshift(1, bit_index)) ~= 0
end

M.mark_bit = function(mask, bit_index)
    return bor(mask, lshift(1, bit_index))
end

return M
