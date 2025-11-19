local bit = require("bit")
local band, rshift, lshift, bor = bit.band, bit.rshift, bit.lshift, bit.bor

local M = {}
--- Split a 24-bit RGB color value into its individual components.
--- @param c integer The 24-bit RGB color value.
--- @return integer r The red component.
--- @return integer g The green component.
--- @return integer b The blue component.
local split_rgb24 = function(c)
	-- c: 0xRRGGBB
	-- local r = rshift(c, 16) -- lấy 8 bit cao nhất
	-- local g = band(rshift(c, 8), 0xFF)
	-- local b = band(c, 0xFF)
	return rshift(c, 16), band(rshift(c, 8), 0xFF), band(c, 0xFF)
end
M.split_rgb24 = split_rgb24

--- Join 3 RGB components into a 24-bit RGB color value.
--- @param r integer The red component.
--- @param g integer The green component.
--- @param b integer The blue component.
--- @return integer c The 24-bit RGB color value.
local join_rgb24 = function(r, g, b)
	return bor(lshift(r, 16), lshift(g, 8), b)
end
M.join_rgb24 = join_rgb24

--- Calculate the luminance of a 24-bit RGB color value.
--- @param c integer The 24-bit RGB color value.
--- @return number l The luminance value between 0 and 1.
M.luminance_24 = function(c)
	local r, g, b = split_rgb24(c)
	return r * 0.299 + g * 0.587 + b * 0.114
end

--- Calculate the luminance of a 24-bit RGB color value.
--- @param c integer The 24-bit RGB color value.
--- @return number l The luminance value between 0 and 1.
M.luminance_fast = function(c)
	local r, g, b = split_rgb24(c)
	return (r * 299 + g * 587 + b * 114) / 1000 -- integer division
end

--- Adjust the brightness of a 24-bit RGB color value.
--- @param c integer The 24-bit RGB color value.
--- @param factor number The brightness factor (0.0 to 1.0).
M.adjust_rgb24 = function(c, factor)
	local r, g, b = split_rgb24(c)
	r = r * factor
	g = g * factor
	b = b * factor
	return join_rgb24(r > 255 and 255 or r, g > 255 and 255 or g, b > 255 and 255 or b)
end

-- local function adjust_palette(palette, status_bg)
--     local lum = luminance_fast(status_bg)

--     -- dark background → brighten colors
--     local factor = lum < 110 and 1.25 or 0.8

--     local result = {}
--     for name, value in pairs(palette) do
--         local c = type(value) == "number" and value or tonumber(value:sub(2), 16)
--         result[name] = adjust_rgb24(c, factor)
--     end
--     return result
-- end
return M
