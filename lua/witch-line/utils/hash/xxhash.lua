local ffi = require('ffi')
local bit = require('bit')

local rotl, xor, shr = bit.rol, bit.bxor, bit.rshift
local uint32_t = ffi.typeof("uint32_t")

-- Prime constants
local P1 = uint32_t(0x9E3779B1)
local P2 = uint32_t(0x85EBCA77)
local P3 = (0xC2B2AE3D)
local P4 = (0x27D4EB2F)
local P5 = (0x165667B1)

-- multiplication with modulo2 semantics
-- see https://github.com/luapower/murmurhash3
local function mmul(a, b)
	local type = 'uint32_t'
	return tonumber(ffi.cast(type, ffi.cast(type, a) * ffi.cast(type, b)))
end

local function xxhash32(data, len, seed)
	seed, len = seed or 0, len or #data
	local i,n = 0, 0 -- byte and word index
	local bytes = ffi.cast( 'const uint8_t*', data)
	local words = ffi.cast('const uint32_t*', data)

	local h32
	if len >= 16 then
		local limit = len - 16
		local v = ffi.new("uint32_t[4]")
		v[0], v[1] = seed + P1 + P2, seed + P2
		v[2], v[3] = seed, seed - P1
		while i <= limit do
			for j=0, 3 do
				v[j] = v[j] + words[n] * P2
				v[j] = rotl(v[j], 13); v[j] = v[j] * P1
				i = i + 4; n = n + 1
			end
		end
		h32 = rotl(v[0], 1) + rotl(v[1], 7) + rotl(v[2], 12) + rotl(v[3], 18)
	else
		h32 = seed + P5
	end
	h32 = h32 + len

	local limit = len - 4
	while i <= limit do
		h32 = (h32 + mmul(words[n], P3))
		h32 = mmul(rotl(h32, 17), P4)
		i = i + 4; n = n + 1
	end

	while i < len do
		h32 = h32 + mmul(bytes[i], P5)
		h32 = mmul(rotl(h32, 11), P1)
		i = i + 1
	end

	h32 = xor(h32, shr(h32, 15))
	h32 = mmul(h32, P2)
	h32 = xor(h32, shr(h32, 13))
	h32 = mmul(h32, P3)
	return tonumber(ffi.cast("uint32_t", xor(h32, shr(h32, 16))))
end

return xxhash32
