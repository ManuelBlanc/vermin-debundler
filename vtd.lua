#!/usr/bin/env luajit
-- Debundler entrypoint. Copyright 2019 Manuel Blanc.

assert(jit, "LuaJIT is required")
local util = require("util").path
local tohex64 = require("bit64").tohex
local MurmurHash64A = require("murmurhash64")
local BundleReader = require("bundle_reader")
local HashLookup = require("hash_lookup")

-- ==============================================================================================
-- Actions
-- ==============================================================================================

local Actions = {}

function Actions.help()
    io.stderr:write[[
Usage: vtd [options..] verb [args..]

Options:
    -g game             Select the game bundle version.
    -b path             Base path for commands that generate files.
    -l file             Load a hash lookup file. Can be repeated.
    -n name             Load a hash lookup file. Can be repeated.
    -v                  Enable debug output.
Commands:
    dict                Print the hash lookup dictionary.
    help                Show this help.
    index               List the contents of a bundle.
    extract [file]      Extract a file.
]]
    os.exit(1)
end
function Actions.dict(ctx)
    ctx.lookup:dump(io.stdout)
end
function Actions.index(ctx, arg)
    for _, a in ipairs(arg) do
        local br = BundleReader:new(a, ctx.lookup)
        local out
        if ctx.base_path then
            local target_name = path(a).basename .. ".json"
            local target_path = ctx.base_path .. "/"
            --if fragment then target_path = target_path .. target_name:sub(1, 2) .. "/" end
            os.execute("mkdir -p " .. target_path)
            out = assert(io.open(target_path .. target_name, "w"))
        else
            out = io.stdout
        end
        br:write_index(out)
        if ctx.base_path then out:close() end
    end
end
function Actions.hash(ctx, arg)
    local function hash(s)
        return tohex64(MurmurHash64A(s, #s, 0))
    end
    for _, a in ipairs(arg) do
        ctx.out:write(string.gsub(a, "[^.]+", hash), "\n")
    end
end
function Actions.extract(ctx, arg)
    for _, a in ipairs(arg) do
        local br = BundleReader:new(a, ctx.lookup)
        br:extract_scripts(ctx.base_path, ctx.hash_list)
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

-- ==============================================================================================
-- Actions
-- ==============================================================================================

local function check(v)
    if v == nil then Actions.help() else return v end
end

local function main(...)
    local lookup = HashLookup:new()
    lookup:add_from_list {
        "animation_curves", "apb", "bik", "bones", "config", "crypto", "data", "entity", "flow",
        "font", "ini", "ivf", "level", "lua", "material", "mod", "mouse_cursor", "navdata",
        "network_config", "package", "particles", "physics_properties", "render_config", "scene",
        "shader", "shader_library", "shader_library_group", "shading_environment",
        "shading_environment_mapping", "sound_environment", "state_machine", "strings",
        "surface_properties", "texture", "timpani_bank", "timpani_master", "tome", "unit",
        "vector_field", "wav", "wwise_bank", "wwise_dep", "wwise_metadata", "wwise_stream"
    }
    local ctx = { out = io.stdout, lookup = lookup }
    local arg, n = {...}, 1
    while n <= #arg do
        local a = arg[n]
        if string.sub(a, 1, 1) == "-" and a ~= "-" then
            table.remove(arg, n)
            if a == "--" then break end
            for m=2, #a do
                local opt = string.sub(a, m, m)
                if opt == "v" then __trace__["*"] = true
                else
                    if arg[n] == nil or m ~= #a then Action.help() end
                    if opt == "g" then
                        ctx.game = tonumber(table.remove(arg, n))
                    elseif opt == "b" then
                        ctx.base_path = table.remove(arg, n)
                    elseif opt == "l" then
                        ctx.lookup:add_from_file(table.remove(arg, n))
                    elseif opt == "n" then
                        ctx.lookup:add(table.remove(arg, n))
                    else
                        usage()
                    end
                end
            end
        else
            n = n + 1
        end
    end

    --for _, k in pairs(ctx.hash_list) do ctx.hash_list[tohex64(murmurhash64(k))] = k end

    local act = Actions[table.remove(arg, 1)] or Actions.help
    act(ctx, arg)
end

local function pe(err)
    io.stderr:write(err, "\n", debug.traceback(2), "\n")
end
local ok = xpcall(main, pe, ...)
io.stdout:flush()
io.stderr:flush()
os.exit(ok and 0 or 255) -- 255 to stop xargs
