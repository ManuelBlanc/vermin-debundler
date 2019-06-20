--[[
    Vermintide Debundler. Requires LuaJIT.

    Copyright 2019 ManuelBlanc
    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]

local util = require("util")
local class = util.class
local path = util.path
local stream = require("stream")
local FileStream, ZlibStream = stream.FileStream, stream.ZlibStream
local tohex32, tohex64 = require("bit").tohex, require("bit64").tohex
local murmurhash64 = require("murmurhash64")
local tojson = require("json").tojson
local cast = require("ffi").cast

-- ==============================================================================================
-- Bundle Reader
-- ==============================================================================================

-- Acceptable bundle formats dictionary.
local BUNDLE_FORMAT_DATA = {
    { signature = 0xF0000004, header = 0x10, name = "vt1" },
    { signature = 0xF0000005, header = 0x14, name = "vt2" },
    { signature = 0xF0000006, header = 0x18, name = "vt2x" },
}
for _, def in ipairs(BUNDLE_FORMAT_DATA) do
    BUNDLE_FORMAT_DATA[def.signature] = def
end

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

function BundleReader:extract_scripts(base_path, hash_list)
    base_path = base_path or "scripts/"
    for _, item in ipairs(self.items) do
        __trace__("%s.%s", item.name or item.name_hash, item.type or item.type_hash)
        for _, header in ipairs(item.headers) do
            if header.lang == 0 and item.type == "lua" and (not hash_list or hash_list[item.name_hash]) then
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

function BundleReader:write_index(base_path, fragment)
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
    local target_name = path(self.path).basename .. ".json"
    __trace__("%s => %s of %s", target_name, #obj, #self.items)
    local target_path = base_path or "index/"
    if fragment then target_path = target_path .. target_name:sub(1, 2) .. "/" end
    os.execute("mkdir -p " .. target_path)
    local f = assert(io.open(target_path .. target_name, "w"))
    f:write(tojson(obj))
    f:close()
end

-- ==============================================================================================
-- Hash Lookup
-- ==============================================================================================

local HashLookup = class()
function HashLookup:add(plain)
    self[tohex64(murmurhash64(plain))] = plain
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
function HashLookup:tostring()
    local lines = {}
    for k, v in pairs(self) do
        lines[#lines+1] = string.format("%s\t%s", k, v)
    end
    table.sort(lines)
    return table.concat(lines, "\n")
end

local hl = HashLookup:new()
hl:add_from_file "files.txt"
hl:add_from_file "stash/dict.txt"
hl:add_from_list { "animation_curves", "apb", "bik", "bones", "config", "crypto", "data", "entity", "flow", "font", "ini", "ivf", "level", "lua", "material", "mod", "mouse_cursor", "navdata", "network_config", "package", "particles", "physics_properties", "render_config", "scene", "shader", "shader_library", "shader_library_group", "shading_environment", "shading_environment_mapping", "sound_environment", "state_machine", "strings", "surface_properties", "texture", "timpani_bank", "timpani_master", "tome", "unit", "vector_field", "wav", "wwise_bank", "wwise_dep", "wwise_metadata", "wwise_stream" }
---print(hl:tostring())

local hash_list = {
    "scripts/settings/breeds/breed_tweaks.lua",
    "scripts/settings/breeds/breed_tweaks",
}
for _, k in pairs(hash_list) do hash_list[tohex64(murmurhash64(k))] = k end

--__trace__[debundle_all] = true
--__trace__[BundleReader.write_index] = true
--__trace__["*"] = false
--__trace__["./debundler.lua"] = true
--__trace__["./stream.lua"] = false
--__trace__[ZlibStream._uncompress_blob] = true
--__trace__[ZlibStream._read] = true

local function pe(err) io.stderr:write(err, "\n", debug.traceback(2), "\n") end
local ok = true
for _, path in ipairs({...}) do
    print(path)
    ok = xpcall(function()
        local br = BundleReader:new(path, hl)
        br:write_index("index/", true)
        --br:extract_scripts()
    end, pe)
    --if not ok then break end
end
io.stdout:flush()
io.stderr:flush()
os.exit(ok and 0 or 255) -- 255 to stop xargs
