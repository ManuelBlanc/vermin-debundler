-- Bitsquid bundle reader. Copyright 2019 Manuel Blanc.

local class = require("util").class
local tohex64 = require("bit64").tohex
local MurmurHash64A = require("murmurhash64")

-- ==============================================================================================
-- Hash Lookup
-- ==============================================================================================

local HashLookup = class()
function HashLookup:add(plain)
    self[tohex64(MurmurHash64A(plain))] = plain
end
function HashLookup:add_from_file(filename)
    for plain in io.lines(filename) do self:add(plain) end
end
function HashLookup:add_from_list(list)
    for _, plain in ipairs(list) do self:add(plain) end
end
function HashLookup:get(hash)
    return self[hash]
end
function HashLookup:dump(out)
    local lines = {}
    for k, v in pairs(self) do
        lines[#lines+1] = string.format("%s\t%s", k, v)
    end
    table.sort(lines)
    out:write(table.concat(lines, "\n"), "\n")
end

return HashLookup