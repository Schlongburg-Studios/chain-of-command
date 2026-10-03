-- Minimal JSON for the test sandbox (FiveM provides `json` at runtime).
local json = {}

local function encodeString(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local map = { ['"'] = '\\"', ['\\'] = '\\\\', ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t' }
        return map[c] or ('\\u%04x'):format(c:byte())
    end) .. '"'
end

local function isArray(t)
    local n = #t
    if n == 0 then return false end
    for k in pairs(t) do
        if type(k) ~= 'number' or k < 1 or k > n or math.type(k) ~= 'integer' then return false end
    end
    return true
end

function json.encode(v)
    local kind = type(v)
    if v == nil then return 'null' end
    if kind == 'boolean' then return tostring(v) end
    if kind == 'number' then return math.type(v) == 'integer' and ('%d'):format(v) or ('%.14g'):format(v) end
    if kind == 'string' then return encodeString(v) end
    if kind ~= 'table' then error('cannot encode ' .. kind) end
    if isArray(v) then
        local out = {}
        for i = 1, #v do out[i] = json.encode(v[i]) end
        return '[' .. table.concat(out, ',') .. ']'
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    local out = {}
    for _, k in ipairs(keys) do
        local value = v[k]
        if value == nil then value = v[tonumber(k)] end
        out[#out + 1] = encodeString(k) .. ':' .. json.encode(value)
    end
    return '{' .. table.concat(out, ',') .. '}'
end

function json.decode(s)
    local pos = 1
    local function ws() pos = s:find('[^%s]', pos) or #s + 1 end
    local value

    local function str()
        local out = {}
        pos = pos + 1
        while true do
            local c = s:sub(pos, pos)
            if c == '' then error('unterminated string') end
            if c == '"' then pos = pos + 1 break end
            if c == '\\' then
                local e = s:sub(pos + 1, pos + 1)
                local map = { n = '\n', r = '\r', t = '\t', b = '\b', f = '\f', ['/'] = '/', ['"'] = '"', ['\\'] = '\\' }
                if e == 'u' then
                    out[#out + 1] = utf8.char(tonumber(s:sub(pos + 2, pos + 5), 16))
                    pos = pos + 6
                else
                    out[#out + 1] = map[e]
                    pos = pos + 2
                end
            else
                out[#out + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(out)
    end

    value = function()
        ws()
        local c = s:sub(pos, pos)
        if c == '{' then
            local t = {}
            pos = pos + 1
            ws()
            if s:sub(pos, pos) == '}' then pos = pos + 1 return t end
            while true do
                ws()
                local k = str()
                ws()
                pos = pos + 1 -- :
                t[k] = value()
                ws()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == '}' then return t end
            end
        elseif c == '[' then
            local t = {}
            pos = pos + 1
            ws()
            if s:sub(pos, pos) == ']' then pos = pos + 1 return t end
            while true do
                t[#t + 1] = value()
                ws()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == ']' then return t end
            end
        elseif c == '"' then
            return str()
        elseif s:sub(pos, pos + 3) == 'true' then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == 'false' then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == 'null' then pos = pos + 4 return nil
        else
            local num = s:match('^-?%d+%.?%d*[eE]?[-+]?%d*', pos)
            if not num or num == '' then error('bad json at ' .. pos) end
            pos = pos + #num
            return math.tointeger(tonumber(num)) or tonumber(num)
        end
    end

    return value()
end

return json
