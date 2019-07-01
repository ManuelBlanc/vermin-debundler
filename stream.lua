-- File-like streams. Copyright 2019 Manuel Blanc.

local util = require("util")
local class = util.class
local malloc, realloc, free = util.malloc, util.realloc, util.free
local ffi = require("ffi")
local cast, copy, new = ffi.cast, ffi.copy, ffi.new
local zlib = ffi.load(ffi.os == "Windows" and "zlib1" or "z")
local ZERO_ULL = new("uint64_t", 0)

-- ==============================================================================================
-- Zlib
-- ==============================================================================================

ffi.cdef[[
    int uncompress(
        uint8_t *dest, unsigned long *destLen,
        const uint8_t *source, unsigned long sourceLen
    );
]]

local ZLIB_RET = {
    [ 0] = "Z_OK",
    [ 1] = "Z_STREAM_END",
    [ 2] = "Z_NEED_DICT",
    [-1] = "Z_ERRNO",
    [-2] = "Z_STREAM_ERROR",
    [-3] = "Z_DATA_ERROR",
    [-4] = "Z_MEM_ERROR",
    [-5] = "Z_BUF_ERROR",
    [-6] = "Z_VERSION_ERROR",
}

-- ==============================================================================================
-- Abstract stream
-- ==============================================================================================

local Stream = class()
function Stream:_seek(n) error("called _seek in the Stream abstract class") end
function Stream:_read(n) error("called _read in the Stream abstract class") end
function Stream:read(n) return self:_read(malloc(n), n) end
function Stream:read_uint8()  return self:_read(new("uint8_t [1]"), 1)[0] end
function Stream:read_uint16() return self:_read(new("uint16_t[1]"), 2)[0] end
function Stream:read_uint32() return self:_read(new("uint32_t[1]"), 4)[0] end
function Stream:read_uint64() return self:_read(new("uint64_t[1]"), 8)[0] end

-- ==============================================================================================
-- FileStream
-- ==============================================================================================

local FileStream = class(Stream)
function FileStream:init(path)
    self.path = path
    self.file = assert(io.open(path, "rb"))
end
function FileStream:_seek(whence, offset)
    __trace__("FileStream:_seek(%s, %s)", whence, offset)
    return self.file:seek(whence, offset)
end
function FileStream:_read(buf, n)
    __trace__("FileStream:_read(%s, %s)", buf, n)
    local str = self.file:read(n)
    assert(str and #str == n, self.path)
    copy(buf, cast("const uint8_t*", str), n)
    return buf
end

-- ==============================================================================================
-- ZlibStream
-- ==============================================================================================

local ZlibStream = class(Stream)
function ZlibStream:init(strm, tmp_buf_len)
    self.strm = strm
    self.tmp_buf, self.tmp_buf_len = malloc(tmp_buf_len), tmp_buf_len
    self.chunk_pos, self.chunk_len = ZERO_ULL, ffi.new("unsigned long[1]", 0)
end
function ZlibStream:_uncompress_blob()
    __trace__("ZlibStream:_uncompress_blob()")
    local s = self.strm
    local src_len = s:read_uint32()
    local src_buf = s:read(src_len)
    while src_len > 0xFFFF do -- Similar to a VLE algorithm.
        __trace__("Long blob")
        local extra_len = s:read_uint32()
        local extra_buf = s:read(extra_len)
        src_buf = realloc(src_buf, src_len + extra_len)
        copy(src_buf + extra_len, src_buf, src_len)
        copy(src_buf, extra_buf, extra_len)
        free(extra_buf)
    end
    self.chunk_pos, self.chunk_len[0] = ZERO_ULL, self.tmp_buf_len
    --ffi.fill(self.tmp_buf, self.chunk_len[0], 0x47)
    local ret = zlib.uncompress(self.tmp_buf, self.chunk_len, src_buf, src_len)
    free(src_buf)
    __trace__("  zlib.uncompress() => %s", ZLIB_RET[ret])
    __trace__("  Current chunk is %s bytes long", self.chunk_len[0])
    assert(0 == ret, ZLIB_RET[ret])
end
function ZlibStream:_seek(whence, offset)
    assert("Operation '_seek' not supported on a ZlibStream")
end
function ZlibStream:_read(buf, n)
    __trace__("ZlibStream:_read(%s)", n)
    local dst = cast("uint8_t*", buf)
    local nn = n
    while n > 0 do
        __trace__("  Bytes left to read: %s", n)
        if self.chunk_len[0] == self.chunk_pos then
            __trace__("  Consumed the whole blob, uncompressing the next one")
            self:_uncompress_blob()
        end
        __trace__("  Buffer state: %s/%s", self.chunk_pos, self.chunk_len[0])
        local bytes_left = self.chunk_len[0] - self.chunk_pos
        local bytes_read = n > bytes_left and bytes_left or n
        __trace__("  Performing a read: %s", bytes_read)
        __trace__("    copy(%s, %s, %s)", dst, self.tmp_buf + self.chunk_pos, bytes_read)
        copy(dst, self.tmp_buf + self.chunk_pos, bytes_read)
        dst, n = dst + bytes_read, n - bytes_read
        self.chunk_pos = self.chunk_pos + bytes_read
    end
    return buf
end

-- ==============================================================================================
-- ByteStream
-- ==============================================================================================

local ByteStream = class(Stream)
function ByteStream:init(buf, len)
    self.buf, self.len = cast("const uint8_t*", buf), len
    self.ptr = self.buf
end
function ByteStream:_seek(whence, offset)
    if type(whence) == "number" then whence, offset = "cur", whence
    elseif not offset then offset = 0 end
    if whence == "set" then self.pos = offset
    elseif whence == "cur" then self.pos = self.pos + offset
    elseif whence == "end" then self.pos = self.len + offset - 1 end
    return self.pos
end
function ByteStream:_read(buf, n)
    copy(buf, self.buf, n)
    self.pos = self.pos + n
    return buf
end

-- ==============================================================================================
-- Exports
-- ==============================================================================================

return {
    Stream = Stream,
    FileStream = FileStream,
    ZlibStream = ZlibStream,
}
