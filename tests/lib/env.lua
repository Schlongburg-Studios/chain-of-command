-- Builds a fresh, isolated sandbox that mimics FiveM + oxmysql + ox_lib, installs a
-- framework mock, and loads the cmd_chain server scripts into it.
local json = require 'lib.json'

local Env = {}

local function deepcopy(v)
    if type(v) ~= 'table' then return v end
    local o = {}
    for k, x in pairs(v) do o[k] = deepcopy(x) end
    return o
end
Env.deepcopy = deepcopy

---Errors if a parameter array has a nil hole (CLAUDE.md rule: it shifts oxmysql params).
local function assertNoHoles(p)
    local max = 0
    for k in pairs(p) do
        if type(k) == 'number' and k > max then max = k end
    end
    if max ~= #p then error(('nil hole in oxmysql parameters (max index %d, length %d)'):format(max, #p), 3) end
end

---@param opts { root: string, framework: 'qbx'|'qb', editable: boolean, files?: table, db?: table, defer?: boolean, world?: fun(fw) }
function Env.new(opts)
    local S = {
        handlers = {}, clientEvents = {}, callbacks = {}, commands = {},
        clock = 0, frozen = false,
        files = deepcopy(opts.files or {}), aces = {},
        db = { members = {}, audit = {}, ranks = {} },
    }
    for k, row in pairs(opts.db and opts.db.members or {}) do S.db.members[k] = deepcopy(row) end
    for k, row in pairs(opts.db and opts.db.ranks or {}) do S.db.ranks[k] = deepcopy(row) end

    local env = setmetatable({}, { __index = _G })
    env._G = env
    env.json = json
    env.source = 0

    -- events
    function env.AddEventHandler(name, fn)
        S.handlers[name] = S.handlers[name] or {}
        table.insert(S.handlers[name], fn)
    end
    env.RegisterNetEvent = env.AddEventHandler
    function env.TriggerEvent(name, ...)
        for _, fn in ipairs(S.handlers[name] or {}) do fn(...) end
    end
    function env.TriggerClientEvent(name, src, ...)
        table.insert(S.clientEvents, { name = name, src = src, args = { ... } })
    end

    -- natives
    function env.CreateThread(fn) fn() end
    env.Citizen = { CreateThread = env.CreateThread, Trace = print }
    function env.GetGameTimer()
        if not S.frozen then S.clock = S.clock + 2500 end
        return S.clock
    end
    function env.IsDuplicityVersion() return true end
    function env.GetCurrentResourceName() return 'cmd_chain' end
    function env.LoadResourceFile(res, file) return S.files[res .. '/' .. file] end
    function env.SaveResourceFile(res, file, data)
        S.files[res .. '/' .. file] = data
        return true
    end
    function env.IsPlayerAceAllowed(src, ace) return S.aces[tostring(src) .. ':' .. ace] == true end

    -- ox_lib (server parts cmd_chain uses)
    env.lib = {
        callback = { register = function(name, fn) S.callbacks[name] = fn end },
        addCommand = function(name, _, fn) S.commands[name] = fn end,
    }

    -- framework mock (sets GetResourceState, GetPlayers, exports entries, framework SQL)
    local fw = require('lib.' .. opts.framework).new(env, S, deepcopy, opts)
    env.exports = setmetatable(fw.exports, { __call = function() end })

    -- oxmysql
    local function run(sql, p)
        p = p or {}
        assertNoHoles(p)
        if sql:find('CREATE TABLE') or sql:find('ALTER TABLE') then return {} end
        local rows = fw.sql(sql, p)
        if rows then return rows end
        local db = S.db

        if sql:find('SELECT citizenid, dept, callsign') then
            local r = {}
            for _, m in pairs(db.members) do r[#r + 1] = deepcopy(m) end
            return r
        end
        if sql:find('INSERT IGNORE INTO cmd_chain_members') then
            local k = p[1] .. ':' .. p[2]
            db.members[k] = db.members[k] or { citizenid = p[1], dept = p[2], divisions = p[3], hired_at = 0 }
            return 1
        end
        if sql:find('DELETE FROM cmd_chain_members') then db.members[p[1] .. ':' .. p[2]] = nil return {} end
        if sql:find('SET callsign = NULL') then db.members[p[1] .. ':' .. p[2]].callsign = nil return 1 end
        if sql:find('SET callsign') then db.members[p[2] .. ':' .. p[3]].callsign = p[1] return 1 end
        if sql:find('SET divisions') then db.members[p[2] .. ':' .. p[3]].divisions = p[1] return 1 end

        if sql:find('INSERT INTO cmd_chain_audit') then
            local row, i = {}, 0
            for col in sql:match('%((.-)%)'):gmatch('[%w_]+') do
                i = i + 1
                row[col] = p[i]
            end
            assert(i == #p, 'audit column/parameter count mismatch')
            db.audit[#db.audit + 1] = {
                dept = row.dept, actor = row.actor_citizenid, target = row.target_citizenid,
                action = row.action, old = row.old_value, new = row.new_value,
            }
            return #db.audit
        end
        if sql:find('FROM cmd_chain_audit') then return deepcopy(db.audit) end

        if sql:find('SELECT grade, name, payment, caps FROM cmd_chain_ranks') then
            local r = {}
            for _, x in pairs(db.ranks) do
                if x.dept == p[1] then r[#r + 1] = deepcopy(x) end
            end
            return r
        end
        if sql:find('INSERT INTO cmd_chain_ranks') then
            db.ranks[p[1] .. ':' .. p[2]] = { dept = p[1], grade = p[2], name = p[3], payment = p[4], caps = p[5] }
            return {}
        end
        if sql:find('DELETE FROM cmd_chain_ranks') then db.ranks[p[1] .. ':' .. p[2]] = nil return {} end

        error('unmocked SQL: ' .. sql)
    end
    local function callable(fn) return setmetatable({ await = fn }, { __call = function(_, sql, p) return fn(sql, p) end }) end
    env.MySQL = { query = callable(run), insert = callable(run), update = callable(run) }
    function env.MySQL.ready(cb) S.ready = cb end

    -- world
    if opts.world then opts.world(fw) else Env.defaultWorld(fw) end

    -- load the resource (server side)
    local resource = opts.root .. '/cmd_chain/'
    for _, file in ipairs({ 'config.lua', 'bridge/qbx.lua', 'bridge/qb.lua', 'server/audit.lua', 'server/main.lua', 'server/api.lua' }) do
        local chunk = assert(loadfile(resource .. file, 't', env))
        chunk()
        if file == 'config.lua' then env.Config.Structure.editable = opts.editable end
    end

    local E = { env = env, S = S, fw = fw, opts = opts }
    function E.start() S.ready() end
    if not opts.defer then E.start() end
    return E
end

---CHIEF 6, CAPT 5, CADET 0 online; CIV and CIV2 online civilians; OFF1 an offline Officer.
function Env.defaultWorld(fw)
    fw.addPlayer('CHIEF', 1, 'police', 6, 'Chief')
    fw.addPlayer('CAPT', 2, 'police', 5, 'Capt')
    fw.addPlayer('CADET', 3, 'police', 0, 'Cadet')
    fw.addPlayer('CIV', 4, 'unemployed', 0, 'Civ')
    fw.addPlayer('OFF1', nil, 'police', 1, 'Offline')
    fw.addPlayer('CIV2', 5, 'unemployed', 0, 'Civ2')
end

return Env
