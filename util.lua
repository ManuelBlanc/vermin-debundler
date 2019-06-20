local getinfo = debug.getinfo
local stdout, stderr = io.stdout, io.stderr
local byte, format, match, sub = string.match, string.format, string.sub, string.byte

-- ==============================================================================================
-- Class
-- ==============================================================================================

local DESTROYED_MT = { __index = function () error("This object has been destroyed") end }
local function class(super)
    local ClassTable = setmetatable({
        super = super,
        new = function(mt, ...)
            local i = setmetatable({}, mt)
            return i.init and i:init(...) or i
        end,
        delete = function(i)
            if i.destroy then i:destroy() end
            setmetatable(i, DESTROYED_MT)
        end,
    }, super)
    ClassTable.__index = ClassTable
    return ClassTable
end

-- ==============================================================================================
-- Debugging
-- ==============================================================================================

--local function SGR(a, s) return format("\027[%sm%s\27[0m", a, s) end
local function getcaller(lvl)
    local info = getinfo(1 + lvl, "lSf")
    return format(
        "\027[36m%15s\27[0m:\027[31m%3d\27[0m",
        sub(info.short_src, -15, -1), info.currentline
    ), info
end

--[[ GLOBAL ]] __trace__ = setmetatable({}, {
    __call = function(self, lvl, ...)
        if type(lvl) == "string" then return __trace__(1, lvl, ...) end
        local locstr, info = getcaller(1 + lvl)
        if self[assert(info.func)] == nil then
            if self[assert(info.short_src)] == nil then
                if not self["*"] then return end
            elseif not self[info.short_src] then return end
        elseif not self[info.func] then return end
        return stderr:write(format("%s: %s\n", locstr, format(...)))
    end,
})

-- setmetatable(_G, { __index = function(_, key) error("Undeclared global access _G." .. tostring(key)) end, })

-- ==============================================================================================
-- Manual memory management
-- ==============================================================================================

local ffi = require("ffi")
local C, cast, gc  = ffi.C, ffi.cast, ffi.gc

ffi.cdef[[
void *malloc(size_t);
void free(void*);
void *realloc(void*,size_t);
]]

-- local function addressof(v) return tonumber(tostring(v):match("0x%x+"), 16) end
local function leak_detector(n)
    local locstr = getfileline(3)
    return function(ptr) -- Can colorize the pointer with "38;5;N" (16 <= N <= 216).
        __trace__("Possible memory leak @ %s:%s: malloc(%s) =>", locstr, n, ptr)
        return C.free(ptr)
    end
end
__trace__[leak_detector] = true -- By default enable the leak detector.

local function malloc(n)
    local p = gc(cast("uint8_t*", C.malloc(n)), leak_detector(n))
    --ffi.fill(p, n, 0x40) -- Fill uninitialised values with '@'.
    __trace__(2, "malloc(%s) => %s", n, p)
    return p
end
local function realloc(ptr, n)
    gc(ptr, nil)
    local rptr = assert(C.realloc(ptr, n), "Cannot realloc " .. tostring(ptr))
    __trace__(2, "realloc(%s, %s) => %s", ptr, n, rptr)
    return gc(cast("uint8_t*", rptr), leak_detector(n))
end
local function free(ptr)
    __trace__(2, "free(%s)", ptr)
    return C.free(gc(ptr, nil))
end

local function memdump(ptr, len, out)
    ptr = cast("const uint8_t*", ptr)
    local base = ptr
    while len > 0 do
        out:write(format("%08X ", tonumber(base - ptr)))
        for i=1, 4 do
            out:write(" ")
            local n = len > 8 and 8 or tonumber(len) -- Compatible with ULL.
            for i=0, n-1 do
                out:write(format(" %02X", ptr[i]))
            end
            ptr, len = ptr + 8, len - n
            if len == 0 then break end
        end
        out:write("\n")
    end
end

-- ==============================================================================================
-- Path
-- ==============================================================================================

local function path(pathstr)
    local i = match(pathstr, "^.*()/") or 1
    local basename = sub(pathstr, i+1)
    local j = match(basename, "^.*()%.") or 1
    return {
        dirname   = sub(pathstr,  1, i-1),
        basename  = sub(pathstr,  i+1),
        filename  = sub(basename, 1, i-1),
        extension = sub(basename, j+1),
    }
end

return {
    __trace__ = __trace__,
    class = class,
    malloc = malloc,
    realloc = realloc,
    free = free,
    memdump = memdump,
    path = path,
    -- Misc.
    getcaller = getcaller,
    leak_detector = leak_detector,
}
