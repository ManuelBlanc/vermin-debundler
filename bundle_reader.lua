-- Bitsquid Bundle Reader. Copyright 2019 Manuel Blanc.

local util = require("util")
local class = util.class
local path = util.path
local stream = require("stream")
local FileStream, ZlibStream = stream.FileStream, stream.ZlibStream
local tohex32, tohex64 = require("bit").tohex, require("bit64").tohex
local murmurhash64 = require("murmurhash64")
local tojson = require("json").tojson
local cast = require("ffi").cast

-- Acceptable bundle formats dictionary.
local BUNDLE_FORMAT_DATA = {
    { signature = 0xF0000004, header = 0x10, name = "vt1" },
    { signature = 0xF0000005, header = 0x14, name = "vt2" },
    { signature = 0xF0000006, header = 0x18, name = "vt2x" },
}
for _, def in ipairs(BUNDLE_FORMAT_DATA) do
    BUNDLE_FORMAT_DATA[def.signature] = def
end

-- ==============================================================================================
-- Bundle Reader
-- ==============================================================================================

local BundleReader = class()

function BundleReader:init(path, lookup)
    self.path, self.lookup = path, lookup
    self.file = FileStream:new(path)
    self.items = {}
    self.signature = self.file:read_uint32()
    self.unzip_size = self.file:read_uint32() -- + 2^16 52183
    self.padding = self.file:read_uint32()
    self.format = BUNDLE_FORMAT_DATA[self.signature]
    assert(self.format, "Unknown signature: " .. tohex32(self.signature))
    assert(self.padding == 0, "Padding is not 0")
    self:read_items()
end

function BundleReader:destroy()
    for _, item in ipairs(self.items) do
        for _, header in ipairs(item.headers) do
            util.free(header.data)
        end
    end
end

function BundleReader:read_items()
    local s = ZlibStream:new(self.file, 2*65536)

    local item_count = s:read_uint32()
    __trace__("Item count: %s", item_count)

    util.free(s:read(256)) -- Skip the rest of the header.

    __trace__("========== INDEX 1 ==========")
    for i=1, item_count do
        __trace__("Reading item %i", i)
        local item = {
            type_hash = tohex64(s:read_uint64()),
            name_hash = tohex64(s:read_uint64()),
        }
        item.type = self.lookup:get(item.type_hash)
        item.name = self.lookup:get(item.name_hash)

        __trace__("type_hash = %s (%s)", item.type_hash, item.type or "n/a")
        __trace__("name_hash = %s (%s)", item.name_hash, item.name or "n/a")

        if self.format.name == "vt2" then
            --__trace__("Skipping 1x uint32")
            s:read_uint32()
        elseif self.format.name == "vt2x" then
            --__trace__("Skipping 2x uint32")
            s:read_uint32()
            s:read_uint32()
        end
        self.items[#self.items+1] = item
    end

    collectgarbage()

    __trace__("========== INDEX 2 ==========")
    for i=1, item_count do
        __trace__("Reading item %i", i)
        local item = self.items[i]

        local type_hash = tohex64(s:read_uint64())
        local name_hash = tohex64(s:read_uint64())
        __trace__("type_hash = %s [expect: %s]", type_hash, item.type_hash)
        __trace__("name_hash = %s [expect: %s]", name_hash, item.name_hash)
        assert(item.type_hash == type_hash, "Type hash mismatch at item " .. i)
        assert(item.name_hash == name_hash, "Name hash mismatch at item " .. i)

        local header_count = s:read_uint32()
        item.unknown = s:read_uint32()
        __trace__("header_count = %s, unknown = %s", header_count, item.unknown)

        item.headers = {}
        for j=1, header_count do
            __trace__("Reading header %i", j)
            item.headers[j] = {
                lang    = s:read_uint32(),
                size    = s:read_uint32(),
                unknown = s:read_uint32(),
            }
        end

        for j=1, header_count do
            local header = item.headers[j]
            assert(not header.data)
            header.data = s:read(header.size)
        end
    end
end

function BundleReader:extract_script(out, hash)
    for _, item in ipairs(self.items) do
        for _, header in ipairs(item.headers) do
            if header.lang == 0 and item.type == "lua" and item.name_hash == hash then
                local script_len = cast("const uint32*", header.data)
                local data = ffi.string(header.data + 12, script_len)
                out:write(data)
            end
        end
    end
end

function BundleReader:extract_all_scripts(base_path, hash_dict)
    base_path = base_path or "scripts/"
    for _, item in ipairs(self.items) do
        for _, header in ipairs(item.headers) do
            if header.lang == 0 and item.type == "lua" and (not hash_dict or hash_dict[item.name_hash]) then
                local p = path(item.name)
                local script_path, script_base = p.dirname, p.basename
                script_path = base_path .. script_path .. script_base .. ".lua"
                os.execute("mkdir -p " .. script_path)
                local script_len = cast("const uint32*", header.data)
                local script_data = ffi.string(header.data + 12, script_len)
                local out = assert(io.open(script_path .. script_base, "wb"))
                out:write(script_data)
                out:close()
            end
        end
    end
end

function BundleReader:write_index(out)
    local obj = {}
    for i, item in ipairs(self.items) do
        obj[i] = {
            type_hash = item.type_hash, type = item.type,
            name_hash = item.name_hash, name = item.name,
            unknown = item.unknown,
            headers = {},
        }
        for j, header in ipairs(item.headers) do
            obj[i].headers[j] = { lang = header.lang, size = header.size, unknown = header.unknown }
        end
    end
    out:write(tojson(obj), "\n")
end

return BundleReader
