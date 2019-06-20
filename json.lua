--[[
    Lua to JSON serializer. Does not throw errors.

    Copyright 2019 ManuelBlanc
    Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
    The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
--]]

local tostring, type, ipairs, pairs, next = tostring, type, ipairs, pairs, next
local concat = table.concat
local byte, format, gsub = string.byte, string.format, string.gsub

local function ctlsub(c)
        if c == "\n" then return "\\n"
    elseif c == "\r" then return "\\r"
    elseif c == "\t" then return "\\t"
    else return format("\\%03d", byte(c)) end
end
local function cleanstr(s)
    return gsub(format("%q", tostring(s)), "%c", ctlsub)
end

local function pushvalue(b, val, ident)
    if val == nil then b[#b+1] = "null" return end
    local typ = type(val)
    if typ == "table" then
        if #val > 0 then
            b[#b+1] = "[ "
            for i=1, #val do
                if i > 1 then b[#b+1] = ident .. ", " end
                pushvalue(b, val[i], ident .. "  ")
                b[#b+1] = "\n"
            end
            b[#b+1] = ident .. "]"
        elseif next(val) then
            b[#b+1] = "{ "
            local add_comma = false
            for k, v in pairs(val) do
                if add_comma then b[#b+1] = ident .. ", "
                else add_comma = true
                end
                b[#b+1] = cleanstr(k)
                b[#b+1] = ":"
                if type(v) ~= "table" then b[#b+1] = " "
                else b[#b+1] = "\n" .. ident .. "  "
                end
                pushvalue(b, v, ident .. "  ")
                b[#b+1] = "\n"
            end
            b[#b+1] = ident .. "}"
        else
            b[#b+1] = "[]" -- The empty table
        end
    elseif typ == "boolean" or typ == "number" then
        b[#b+1] = tostring(val)
    else
        b[#b+1] = cleanstr(val)
    end
end

-- ==============================================================================================
-- Exports
-- ==============================================================================================

local function tojson(v)
    local b = {nil,nil,nil,nil,nil,nil,nil,nil,nil,nil}
    pushvalue(b, v, "")
    return concat(b)
end

return {
    tojson = tojson,
}
