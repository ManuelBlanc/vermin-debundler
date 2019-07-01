-- Lua to JSON serializer. Does not throw errors. Copyright 2019 Manuel Blanc.

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
