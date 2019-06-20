--[[
    MurmurHash2, 64-bit versions, by Austin Appleby and placed in the public domain.
    The same caveats as 32-bit MurmurHash2 apply here - beware of alignment 
    and endian-ness issues if used across multiple platforms.

    Ported to Lua by ManuelBlanc (https://github.com/manuelblanc/).
    Requires a 64-bit bitwise operations library. Eg, https://github.com/ManuelBlanc/lua-bit64
--]]

local ffi = require("ffi")
local bit64 = require("bit64")
local bxor, lshift, rshift = bit64.bxor, bit64.lshift, bit64.rshift
local UINT64_T_PTR = ffi.typeof("uint64_t*")
local UINT8_T_PTR = ffi.typeof("uint8_t*")

-- 'M' and 'R' are mixing constants generated offline.
-- They're not really 'magic', they just happen to work well.
local M, R = bit64[[0xc6a4a7935bd1e995]], 47

local function MurmurHash64A(key, len, seed)
    -- Default argument values.
    len, seed = len or #key, seed or 0

    -- Initialize the hash to a 'random' value
    local h = bxor(seed, len * M)

    -- Mix 8 bytes at a time into the hash
    local data = ffi.cast(UINT64_T_PTR, key)
    local len8 = math.floor(len / 8)
    for i = 0, len8 - 1 do
        local k = data[i]
        k = k * M
        k = bxor(k, rshift(k, R))
        k = k * M
        h = bxor(h, k)
        h = h * M
    end

    -- Handle the last few bytes of the input array.
    local data2 = ffi.cast(UINT8_T_PTR, data)
    for i = len % 8 - 1, 0, -1 do
        h = bxor(h, lshift(data2[i], i*8))
        if i == 0 then h = h * M  end
    end

    -- Do a few final mixes of the hash to ensure the last few bytes are well-incorporated.
    h = bxor(h, rshift(h, R))
    h = h * M
    h = bxor(h, rshift(h, R))
    return h
end

-- Sanity checks.
assert("0000000000000000" == bit64.tohex(MurmurHash64A(nil, 0)))
assert("2f4a8724618f4c63" == bit64.tohex(MurmurHash64A("test")))
-- for i=1, select("#", ...) do print(bit64.tohex(MurmurHash64A(select(i, ...)))) end

return MurmurHash64A
