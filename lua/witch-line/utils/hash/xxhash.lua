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

ffi.cdef [[
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
]]

local uint32 = ffi.typeof("uint32_t")

local P1 = uint32(0x9E3779B1)
local P2 = uint32(0x85EBCA77)
local P3 = uint32(0xC2B2AE3D)
local P4 = uint32(0x27D4EB2F)
local P5 = uint32(0x165667B1)


--- Initializes an xxHash32 state structure.
---
--- This sets up the 4 internal accumulators (v1..v4) according to the xxHash32
--- reference algorithm, using the provided seed. The temporary buffer and
--- length counters are also reset.
---
--- @param seed integer The user-provided 32-bit seed for hash initialization.
--- @return xxh32_state_t st A freshly allocated and fully initialized xxHash32 state.
local function xxh32_init(seed)
  --- @type xxh32_state_t
  ---@diagnostic disable-next-line: assign-type-mismatch
  local st     = ffi.new("xxh32_state_t")
  st.seed      = seed
  st.v1        = seed + P1 + P2
  st.v2        = seed + P2
  st.v3        = seed + 0
  st.v4        = seed - P1
  st.total_len = 0
  st.memsize   = 0
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
--- @param st xxh32_state_t The hash state being updated.
--- @param input string The input string.
local function xxh32_update(st, input)
  local len = #input
  st.total_len = st.total_len + len
  local p = input
  local endp = p + len

  if st.memsize + len < 16 then
    -- Chưa đủ 16 byte → nhét vào memory
    ffi.copy(st.memory + st.memsize, input, len)
    st.memsize = st.memsize + len
    return
  end

  -- Nếu memory trước đó có dữ liệu → làm đầy đủ 16 byte
  if st.memsize > 0 then
    local needed = 16 - st.memsize
    ffi.copy(st.memory + st.memsize, input, needed)

    local mem = ffi.cast("uint32_t*", st.memory)

    st.v1 = rotl(st.v1 + mem[0] * P2, 13) * P1
    st.v2 = rotl(st.v2 + mem[1] * P2, 13) * P1
    st.v3 = rotl(st.v3 + mem[2] * P2, 13) * P1
    st.v4 = rotl(st.v4 + mem[3] * P2, 13) * P1

    p = p + needed
    st.memsize = 0
  end

  -- Main loop
  while p + 16 <= endp do
    local blk = ffi.cast("uint32_t*", p)

    st.v1 = rotl(st.v1 + blk[0] * P2, 13) * P1
    st.v2 = rotl(st.v2 + blk[1] * P2, 13) * P1
    st.v3 = rotl(st.v3 + blk[2] * P2, 13) * P1
    st.v4 = rotl(st.v4 + blk[3] * P2, 13) * P1

    p = p + 16
  end

  -- Copy phần dư (<16 bytes)
  if p < endp then
    local leftover = endp - p
    ffi.copy(st.memory, p, leftover)
    st.memsize = leftover
  end
end

local function xxh32_finalize(st)
  local h32

  if st.total_len >= 16 then
    h32 = rotl(st.v1, 1) +
        rotl(st.v2, 7) +
        rotl(st.v3, 12) +
        rotl(st.v4, 18)
  else
    h32 = st.seed + P5
  end

  h32 = h32 + st.total_len

  -- Process remaining bytes
  local p = ffi.cast("uint8_t*", st.memory)
  local mem = p
  local i = 0

  -- 4 bytes
  while i + 4 <= st.memsize do
    local k1 = ffi.cast("uint32_t*", mem + i)[0]
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
  xxh32_finalize = xxh32_finalize
}

-- local st = xxh32_init(0)
--
-- for i = 1, #list do
--   local s = list[i]
--   xxh32_update(st, s, #s)
-- end
--
-- local result = xxh32_finalize(st)
-- print(result)

-- local ffi = require('ffi')
-- local bit = require('bit')
--
--
-- local rotl, xor, shr = bit.rol, bit.bxor, bit.rshift
-- local uint32_t = ffi.typeof("uint32_t")
--
-- -- Prime constants
-- local P1 = uint32_t(0x9E3779B1)
-- local P2 = uint32_t(0x85EBCA77)
-- local P3 = (0xC2B2AE3D)
-- local P4 = (0x27D4EB2F)
-- local P5 = (0x165667B1)
--
-- -- multiplication with modulo2 semantics
-- -- see https://github.com/luapower/murmurhash3
-- local function mmul(a, b)
--   local type = 'uint32_t'
--   return tonumber(ffi.cast(type, ffi.cast(type, a) * ffi.cast(type, b)))
-- end
--
-- local function xxhash32(data, len, seed)
--   seed, len = seed or 0, len or #data
--   local i, n = 0, 0 -- byte and word index
--   local bytes = ffi.cast('const uint8_t*', data)
--   local words = ffi.cast('const uint32_t*', data)
--
--   local h32
--   if len >= 16 then
--     local limit = len - 16
--     local v = ffi.new("uint32_t[4]")
--     v[0], v[1] = seed + P1 + P2, seed + P2
--     v[2], v[3] = seed, seed - P1
--     while i <= limit do
--       for j = 0, 3 do
--         v[j] = v[j] + words[n] * P2
--         v[j] = rotl(v[j], 13); v[j] = v[j] * P1
--         i = i + 4; n = n + 1
--       end
--     end
--     h32 = rotl(v[0], 1) + rotl(v[1], 7) + rotl(v[2], 12) + rotl(v[3], 18)
--   else
--     h32 = seed + P5
--   end
--   h32 = h32 + len
--
--   local limit = len - 4
--   while i <= limit do
--     h32 = (h32 + mmul(words[n], P3))
--     h32 = mmul(rotl(h32, 17), P4)
--     i = i + 4; n = n + 1
--   end
--
--   while i < len do
--     h32 = h32 + mmul(bytes[i], P5)
--     h32 = mmul(rotl(h32, 11), P1)
--     i = i + 1
--   end
--
--   h32 = xor(h32, shr(h32, 15))
--   h32 = mmul(h32, P2)
--   h32 = xor(h32, shr(h32, 13))
--   h32 = mmul(h32, P3)
--   return tonumber(ffi.cast("uint32_t", xor(h32, shr(h32, 16))))
-- end
--
-- return xxhash32
--
