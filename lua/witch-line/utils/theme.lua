local M = {}

-- -- Split 24-bit
-- local function split(c)
-- 	return rshift(c, 16), band(rshift(c, 8), 0xFF), band(c, 0xFF)
-- end

-- Join 24-bit
-- local function join(r, g, b)
-- 	return bor(lshift(r, 16), lshift(g, 8), b)
-- end

-- -- Fast integer luminance
-- local function lum(c)
-- 	local r = rshift(c, 16)
-- 	local g = band(rshift(c, 8), 0xFF)
-- 	local b = band(c, 0xFF)
-- 	return (r * 299 + g * 587 + b * 114) / 1000
-- end

-- --- Adjust color
-- --- @param c integer 24-bit color
-- --- @param bg integer 24-bit background
-- local adjust = function(c, bg)
-- 	-- unpack background
-- 	local bg_r = rshift(bg, 16)
-- 	local bg_g = band(rshift(bg, 8), 0xFF)
-- 	local bg_b = band(bg, 0xFF)

-- 	--- unpack color
-- 	local r = rshift(c, 16)
-- 	local g = band(rshift(c, 8), 0xFF)
-- 	local b = band(c, 0xFF)

-- 	--- calculate luminance
-- 	local bg_lum = (bg_r * 299 + bg_g * 587 + bg_b * 114) / 1000
-- 	local is_dark = bg_lum < 140

-- 	-- -- scale ×1024 for bitshift divide
-- 	local light = is_dark and 184 or -153 -- 0.18 × 1024, -0.15 × 1024
-- 	local blend = is_dark and 122 or 103 -- 0.12 × 1024, 0.10 × 1024
-- 	local inv_blend = 1024 - blend

-- 	-- LIGHTEN / DARKEN (fixed-point)
-- 	if light > 0 then
-- 		local inv = 1024 - light
-- 		r = rshift(r * inv + 255 * light, 10)
-- 		g = rshift(g * inv + 255 * light, 10)
-- 		b = rshift(b * inv + 255 * light, 10)
-- 	else
-- 		local inv = 1024 + light
-- 		r = rshift(r * inv, 10)
-- 		g = rshift(g * inv, 10)
-- 		b = rshift(b * inv, 10)
-- 	end

-- 	-- -- BLEND với background (fixed-point)
-- 	r = rshift(r * blend + bg_r * inv_blend, 10)
-- 	g = rshift(g * blend + bg_g * inv_blend, 10)
-- 	b = rshift(b * blend + bg_b * inv_blend, 10)
--
-- 	--- rgb to 24-bit
-- 	return bor(lshift(r, 16), lshift(g, 8), b)
-- end

return M
