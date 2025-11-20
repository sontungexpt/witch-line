local ffi = require("ffi")
local bit = require("bit")
local rotl, rshift, bxor = bit.rol, bit.rshift, bit.bxor

---@class xxh32_state_t : ffi.cdata*
---@field seed      integer
---@field v1        integer
---@field v2        integer
---@field v3        integer
---@field v4        integer
---@field total_len integer
---@field memsize   integer
---@field memory    integer[]  # uint8_t[16]

ffi.cdef([[
typedef struct {
    uint32_t seed;
    uint32_t v1;
    uint32_t v2;
    uint32_t v3;
    uint32_t v4;

    uint32_t total_len;
    uint32_t memsize;
    uint8_t memory[16];  // temp buffer
} xxh32_state_t;
]])

local uint32 = ffi.typeof("uint32_t")

local P1 = uint32(0x9E3779B1)
local P2 = uint32(0x85EBCA77)
local P3 = uint32(0xC2B2AE3D)
local P4 = uint32(0x27D4EB2F)
local P5 = uint32(0x165667B1)

local u8ptr = ffi.typeof("const uint8_t*")
local uint32_ptr = ffi.typeof("uint32_t*")

--- Initializes an xxHash32 state structure.
---
--- This sets up the 4 internal accumulators (v1..v4) according to the xxHash32
--- reference algorithm, using the provided seed. The temporary buffer and
--- length counters are also reset.
---
--- @param seed integer The user-provided 32-bit seed for hash initialization.
--- @return xxh32_state_t st A freshly allocated and fully initialized xxHash32 state.
local xxh32_init = function(seed)
	--- @type xxh32_state_t
	---@diagnostic disable-next-line: assign-type-mismatch
	local st = ffi.new("xxh32_state_t")
	st.seed = seed
	st.v1 = seed + P1 + P2
	st.v2 = seed + P2
	st.v3 = seed + 0
	st.v4 = seed - P1
	st.total_len = 0
	st.memsize = 0
	return st
end

--- Feeds input bytes into the xxHash32 state.
---
--- This function processes data in 16-byte blocks (the core xxHash32 mixing
--- step). Any leftover bytes smaller than 16 are buffered in `state.memory`
--- until enough data is accumulated.
---
--- Behavior:
---   - If total buffered bytes < 16 → store into `memory` and return.
---   - If previous data existed → fill the 16-byte block and mix v1..v4.
---   - Main loop processes 16-byte chunks directly from the input pointer.
---   - Remaining bytes (< 16) are kept in the temp buffer for the final stage.
---
--- @param st xxh32_state_t The hash state being updated (return from `xxh32_init`).
--- @param input string The input string.
local xxh32_update = function(st, input)
	local len = #input
	st.total_len = st.total_len + len
	local p = ffi.cast(u8ptr, input)
	local endp = p + len

	-- cache some local vars for speed
	local memsize, mem = st.memsize, st.memory
	-- Work with local accumulators to reduce table access

	if memsize + len < 16 then
		-- Chưa đủ 16 byte → nhét vào memory
		ffi.copy(mem + memsize, p, len)
		st.memsize = memsize + len
		return
	end

	local v1, v2, v3, v4 = st.v1, st.v2, st.v3, st.v4

	-- Nếu memory trước đó có dữ liệu → làm đầy đủ 16 byte
	if memsize > 0 then
		local needed = 16 - memsize
		ffi.copy(mem + memsize, p, needed) -- copy from input pointer

		local m32 = ffi.cast(uint32_ptr, st.memory)

		v1 = rotl(v1 + m32[0] * P2, 13) * P1
		v2 = rotl(v2 + m32[1] * P2, 13) * P1
		v3 = rotl(v3 + m32[2] * P2, 13) * P1
		v4 = rotl(v4 + m32[3] * P2, 13) * P1

		-- v1 = uint32(rotl(v1 + m32[0] * P2, 13) * P1)
		-- v2 = uint32(rotl(v2 + m32[1] * P2, 13) * P1)
		-- v3 = uint32(rotl(v3 + m32[2] * P2, 13) * P1)
		-- v4 = uint32(rotl(v4 + m32[3] * P2, 13) * P1)

		p = p + needed
		st.memsize = 0
	end

	-- Main loop
	while p + 16 <= endp do
		local blk = ffi.cast(uint32_ptr, p)

		---@diagnostic disable: cast-local-type
		v1 = rotl(v1 + blk[0] * P2, 13) * P1
		v2 = rotl(v2 + blk[1] * P2, 13) * P1
		v3 = rotl(v3 + blk[2] * P2, 13) * P1
		v4 = rotl(v4 + blk[3] * P2, 13) * P1
		-- v1 = uint32(rotl(v1 + blk[0] * P2, 13) * P1)
		-- v2 = uint32(rotl(v2 + blk[1] * P2, 13) * P1)
		-- v3 = uint32(rotl(v3 + blk[2] * P2, 13) * P1)
		-- v4 = uint32(rotl(v4 + blk[3] * P2, 13) * P1)
		---@diagnostic enable: cast-local-type

		p = p + 16
	end

	-- Copy phần dư (<16 bytes)
	if p < endp then
		local leftover = endp - p
		ffi.copy(mem, p, leftover)
		st.memsize = leftover
	end

	-- write back local accumulators and memsize
	---@diagnostic disable-next-line: assign-type-mismatch
	st.v1, st.v2, st.v3, st.v4 = v1, v2, v3, v4
end

--- Finalize the XXH32 hash computation.
--- This processes the remaining buffered bytes, applies the avalanche steps,
--- and returns the final 32-bit hash value.
---
--- @param st xxh32_state_t State object return from `xxh32_init`
--- @return integer h32 The finalized 32-bit hash value.
local xxh32_finalize = function(st)
	local h32

	if st.total_len >= 16 then
		h32 = rotl(st.v1, 1) + rotl(st.v2, 7) + rotl(st.v3, 12) + rotl(st.v4, 18)
	else
		h32 = st.seed + P5
	end

	h32 = h32 + st.total_len

	-- Process remaining bytes
	local mem = ffi.cast("uint8_t*", st.memory)
	local i = 0

	-- 4 bytes
	while i + 4 <= st.memsize do
		local k1 = ffi.cast(uint32_ptr, mem + i)[0]
		h32 = rotl(h32 + k1 * P3, 17) * P4
		i = i + 4
	end

	-- Single bytes
	while i < st.memsize do
		h32 = rotl(h32 + mem[i] * P5, 11) * P1
		i = i + 1
	end

	-- Avalanche
	h32 = bxor(h32, rshift(h32, 15)) * P2
	h32 = bxor(h32, rshift(h32, 13)) * P3
	h32 = bxor(h32, rshift(h32, 16))

	return h32
end

return {
	xxh32_init = xxh32_init,
	xxh32_update = xxh32_update,
	xxh32_finalize = xxh32_finalize,
}
