-- Qbox adapter. Verified against qbx_core main (server/player.lua, server/functions.lua,
-- server/groups.lua, client/functions.lua) and https://docs.qbox.re/resources/qbx_core.
-- Qbox `provide`s qb-core, so this adapter is checked first.

if Bridge then return end
local state = GetResourceState('qbx_core')
if state ~= 'started' and state ~= 'starting' then return end

local qbx = exports.qbx_core
Bridge = { name = 'qbx' }

---Optional per-grade flags that config.lua ranks may set (see Config.Departments).
Bridge.gradeFlags = { 'isboss', 'bankAuth' }

if not IsDuplicityVersion() then
    ---@param cb fun()
    function Bridge.onJobUpdate(cb)
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function() cb() end)
        RegisterNetEvent('qbx_core:client:onGroupUpdate', function() cb() end)
        RegisterNetEvent('QBCore:Client:SetDuty', function() cb() end)
    end

    ---@param cb fun()
    function Bridge.onPlayerLoaded(cb)
        AddEventHandler('QBCore:Client:OnPlayerLoaded', function() cb() end)
    end

    return
end

---@param src integer
function Bridge.getPlayer(src)
    return qbx:GetPlayer(src)
end

---@param citizenid string
---@param includeOffline boolean?
function Bridge.getPlayerByCitizenId(citizenid, includeOffline)
    local player = qbx:GetPlayerByCitizenId(citizenid)
    if not player and includeOffline then
        player = qbx:GetOfflinePlayer(citizenid)
    end
    return player
end

function Bridge.getCitizenId(player)
    return player.PlayerData.citizenid
end

---@return integer? source nil when the player object is offline
function Bridge.getSource(player)
    if player.Offline then return nil end
    return player.PlayerData.source
end

---Primary job only.
---@return string name, integer grade, boolean onDuty
function Bridge.getJob(player)
    local job = player.PlayerData.job
    return job.name, job.grade.level, job.onduty == true
end

---Every job the player holds (Qbox multi-job), as { [jobName] = grade }.
---@return table<string, integer>
function Bridge.getJobs(player)
    local jobs = {}
    for name, grade in pairs(player.PlayerData.jobs or {}) do
        jobs[name] = tonumber(grade)
    end
    local primary = player.PlayerData.job
    if primary and primary.name ~= 'unemployed' and jobs[primary.name] == nil then
        jobs[primary.name] = primary.grade.level
    end
    return jobs
end

---@return integer?
function Bridge.getJobGrade(player, jobName)
    return Bridge.getJobs(player)[jobName]
end

---Duty only exists for the primary job in Qbox.
function Bridge.isOnDuty(player, jobName)
    local job = player.PlayerData.job
    return job.name == jobName and job.onduty == true
end

function Bridge.getName(player)
    local info = player.PlayerData.charinfo or {}
    return ('%s %s'):format(info.firstname or '?', info.lastname or '?')
end

---Adds the job (or overwrites the grade). Works online and offline.
---Uses AddPlayerToJob instead of SetJob, because SetJob removes the player's current
---primary job, which would silently fire a multi-job officer from another job.
---@return boolean ok, string? err
function Bridge.setJob(citizenid, jobName, grade)
    local ok, err = qbx:AddPlayerToJob(citizenid, jobName, grade)
    if not ok then return false, err and err.code or 'set_job_failed' end

    local player = Bridge.getPlayerByCitizenId(citizenid, true)
    if player and player.PlayerData.job.name == 'unemployed' then
        qbx:SetPlayerPrimaryJob(citizenid, jobName)
    end
    return true
end

---@return boolean ok, string? err
function Bridge.removeJob(citizenid, jobName)
    local ok, err = qbx:RemovePlayerFromJob(citizenid, jobName)
    if not ok then return false, err and err.code or 'remove_job_failed' end
    return true
end

---@return table<integer, true>? grades nil when the job does not exist
function Bridge.getJobGrades(jobName)
    local job = qbx:GetJob(jobName)
    if not job then return nil end
    local grades = {}
    for grade in pairs(job.grades or {}) do
        grades[tonumber(grade)] = true
    end
    return grades
end

---@return table? data the framework's grade entry ({ name, payment, isboss, bankAuth, ... })
function Bridge.getJobGradeData(jobName, grade)
    local job = qbx:GetJob(jobName)
    return job and job.grades and job.grades[grade] or nil
end

---Creates or updates a grade in memory. Other fields on the grade (isboss, bankAuth, ...)
---are kept. Call Bridge.persistJobs() afterwards to save to disk.
---@return boolean ok, string? err
function Bridge.upsertJobGrade(jobName, grade, data)
    local job = qbx:GetJob(jobName)
    if not job then return false, 'job_not_found' end
    local merged = job.grades[grade] or {}
    merged.name = data.name
    merged.payment = data.payment
    for _, flag in ipairs(Bridge.gradeFlags) do
        if data[flag] ~= nil then merged[flag] = data[flag] or nil end -- false removes the key
    end
    qbx:UpsertJobGrade(jobName, grade, merged, false)
    local check = Bridge.getJobGradeData(jobName, grade)
    if not check or check.name ~= data.name then return false, 'framework_rejected' end
    return true
end

---@return boolean ok, string? err
function Bridge.removeJobGrade(jobName, grade)
    if not qbx:GetJob(jobName) then return false, 'job_not_found' end
    qbx:RemoveJobGrade(jobName, grade, false)
    if Bridge.getJobGradeData(jobName, grade) then return false, 'framework_rejected' end
    return true
end

-- Writing jobs.lua ourselves: qbx_core's own commitToFile drops each job's `type`
-- (e.g. 'leo') and errors on grades without `payment`. This writer keeps every field.

local LUA_KEYWORDS = {}
for word in ('and break do else elseif end false for function goto if in local nil not or repeat return then true until while'):gmatch('%a+') do
    LUA_KEYWORDS[word] = true
end

local function sortedKeys(t)
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b)
        local ta, tb = type(a), type(b)
        if ta ~= tb then return ta == 'number' end
        return a < b
    end)
    return keys
end

local function keyRepr(k)
    if type(k) == 'number' then return ('[%s]'):format(math.tointeger(k) or k) end
    if k:match('^[%a_][%w_]*$') and not LUA_KEYWORDS[k] then return k end
    return ('[%q]'):format(k)
end

local serialize

local function isFlat(t)
    local n = 0
    for _, v in pairs(t) do
        n = n + 1
        if type(v) == 'table' or n > 6 then return false end
    end
    return true
end

serialize = function(value, indent)
    local kind = type(value)
    if kind == 'string' then return ('%q'):format(value) end
    if kind == 'number' then return tostring(math.tointeger(value) or value) end
    if kind ~= 'table' then return tostring(value) end
    if next(value) == nil then return '{}' end

    local keys = sortedKeys(value)
    if isFlat(value) then
        local parts = {}
        for i, k in ipairs(keys) do parts[i] = keyRepr(k) .. ' = ' .. serialize(value[k]) end
        return '{ ' .. table.concat(parts, ', ') .. ' }'
    end

    local pad = ('    '):rep(indent + 1)
    local lines = { '{' }
    for _, k in ipairs(keys) do
        lines[#lines + 1] = ('%s%s = %s,'):format(pad, keyRepr(k), serialize(value[k], indent + 1))
    end
    lines[#lines + 1] = ('    '):rep(indent) .. '}'
    return table.concat(lines, '\n')
end

local JOBS_FILE = 'shared/jobs.lua'
local ORIGINAL_BACKUP = 'shared/jobs.lua.cmd_chain-original.bak'
local LAST_BACKUP = 'shared/jobs.lua.bak'

---Saves every job (in memory) to qbx_core/shared/jobs.lua so grades survive restarts.
---The first write keeps a copy of the original file; every write keeps the previous one.
---@return boolean ok, string? err
function Bridge.persistJobs()
    local content = table.concat({
        '-- Saved by cmd_chain (Chain of Command). Original: ' .. ORIGINAL_BACKUP,
        '---Job names must be lower case (top level table key)',
        '---@type table<string, Job>',
        'return ' .. serialize(qbx:GetJobs(), 0),
        '',
    }, '\n')

    local current = LoadResourceFile('qbx_core', JOBS_FILE)
    if current == content then return true end
    -- Never overwrite the file unless the backups were really written.
    if current then
        if not LoadResourceFile('qbx_core', ORIGINAL_BACKUP) then
            if not SaveResourceFile('qbx_core', ORIGINAL_BACKUP, current, -1) then return false, 'write_failed' end
        end
        if not SaveResourceFile('qbx_core', LAST_BACKUP, current, -1) then return false, 'write_failed' end
    end
    if not SaveResourceFile('qbx_core', JOBS_FILE, content, -1) then return false, 'write_failed' end
    -- Read it back: a write that "succeeded" but did not land is the same problem.
    if LoadResourceFile('qbx_core', JOBS_FILE) ~= content then return false, 'write_failed' end
    return true
end

---Is this grade in the jobs.lua file on disk (what qbx_core loads at its next start)? The file is
---a plain `return { ... }` table, so it is loaded with an empty environment. Unreadable = no.
---@return boolean
function Bridge.gradeOnDisk(jobName, grade)
    local text = LoadResourceFile('qbx_core', JOBS_FILE)
    if type(text) ~= 'string' then return false end
    local chunk = load(text, 'jobs.lua', 't', {})
    if not chunk then return false end
    local ok, jobs = pcall(chunk)
    if not ok or type(jobs) ~= 'table' then return false end
    local job = jobs[jobName]
    return type(job) == 'table' and type(job.grades) == 'table' and job.grades[grade] ~= nil
end

---Can cmd_chain write qbx_core/shared/jobs.lua? FiveM blocks writing into another resource
---unless server.cfg allows it (`add_filesystem_permission cmd_chain write qbx_core`). Writes
---the file's own content back, so nothing changes when it works.
---@return boolean
function Bridge.canPersist()
    local current = LoadResourceFile('qbx_core', JOBS_FILE)
    -- SaveResourceFile returns 1 on success and false on failure, so test truthiness, not `== true`.
    return current ~= nil and SaveResourceFile('qbx_core', JOBS_FILE, current, -1) and true or false
end

---Everyone holding the job, online or offline. Reads qbx_core's own player_groups
---table (read-only); online players are overlaid with live data.
---@return { citizenid: string, grade: integer, name: string }[]
function Bridge.getJobMembers(jobName)
    local rows = MySQL.query.await([[
        SELECT pg.citizenid, pg.grade, p.charinfo
        FROM player_groups pg
        LEFT JOIN players p ON p.citizenid = pg.citizenid
        WHERE pg.`group` = ? AND pg.`type` = 'job'
    ]], { jobName }) or {}

    local byCid = {}
    for i = 1, #rows do
        local row = rows[i]
        local info = row.charinfo and json.decode(row.charinfo) or {}
        byCid[row.citizenid] = {
            citizenid = row.citizenid,
            grade = tonumber(row.grade),
            name = ('%s %s'):format(info.firstname or '?', info.lastname or '?'),
        }
    end

    for _, id in ipairs(GetPlayers()) do
        local player = Bridge.getPlayer(tonumber(id))
        if player then
            local cid = player.PlayerData.citizenid
            local grade = Bridge.getJobGrade(player, jobName)
            if grade then
                byCid[cid] = { citizenid = cid, grade = grade, name = Bridge.getName(player) }
            else
                byCid[cid] = nil
            end
        end
    end

    local list = {}
    for _, member in pairs(byCid) do list[#list + 1] = member end
    return list
end

---@param cb fun(src: integer)
function Bridge.onJobUpdate(cb)
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src) cb(src) end)
    AddEventHandler('QBCore:Server:SetDuty', function(src) cb(src) end)
    AddEventHandler('qbx_core:server:onGroupUpdate', function(src) cb(src) end)
end

---@param cb fun(src: integer)
function Bridge.onPlayerLoaded(cb)
    AddEventHandler('QBCore:Server:PlayerLoaded', function(player)
        cb(player.PlayerData.source)
    end)
end

---@param cb fun(src: integer)
function Bridge.onPlayerUnload(cb)
    AddEventHandler('QBCore:Server:OnPlayerUnload', function(src) cb(src) end)
end
