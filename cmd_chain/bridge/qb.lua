-- QBCore adapter. Verified against qb-core main (server/player.lua, server/functions.lua,
-- server/events.lua, client/events.lua, shared/main.lua) and https://qbcore.org/docs.
-- Note: QBCore holds one job per character, and job grade keys are strings ('0', '1', ...).

if Bridge then return end
local state = GetResourceState('qb-core')
if state ~= 'started' and state ~= 'starting' then return end

local QBCore = exports['qb-core']:GetCoreObject()
Bridge = { name = 'qb' }

---Optional per-grade flags that config.lua ranks may set (Config.Departments). qb-core has no bankAuth.
Bridge.gradeFlags = { 'isboss' }

if not IsDuplicityVersion() then
    ---@param cb fun()
    function Bridge.onJobUpdate(cb)
        RegisterNetEvent('QBCore:Client:OnJobUpdate', function() cb() end)
        RegisterNetEvent('QBCore:Client:SetDuty', function() cb() end)
    end

    ---@param cb fun()
    function Bridge.onPlayerLoaded(cb)
        RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function() cb() end)
    end

    return
end

---@param src integer
function Bridge.getPlayer(src)
    return QBCore.Functions.GetPlayer(src)
end

---@param citizenid string
---@param includeOffline boolean?
function Bridge.getPlayerByCitizenId(citizenid, includeOffline)
    local player = QBCore.Functions.GetPlayerByCitizenId(citizenid)
    if not player and includeOffline then
        player = QBCore.Functions.GetOfflinePlayerByCitizenId(citizenid)
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

---@return string name, integer grade, boolean onDuty
function Bridge.getJob(player)
    local job = player.PlayerData.job
    return job.name, tonumber(job.grade.level) or 0, job.onduty == true
end

---@return table<string, integer>
function Bridge.getJobs(player)
    local name, grade = Bridge.getJob(player)
    if name == 'unemployed' then return {} end
    return { [name] = grade }
end

---@return integer?
function Bridge.getJobGrade(player, jobName)
    local name, grade = Bridge.getJob(player)
    if name == jobName then return grade end
end

function Bridge.isOnDuty(player, jobName)
    local job = player.PlayerData.job
    return job.name == jobName and job.onduty == true
end

function Bridge.getName(player)
    local info = player.PlayerData.charinfo or {}
    return ('%s %s'):format(info.firstname or '?', info.lastname or '?')
end

---Works online and offline. Saves so offline changes persist and the
---roster query (players table) sees online changes immediately.
---@return boolean ok, string? err
function Bridge.setJob(citizenid, jobName, grade)
    local player = Bridge.getPlayerByCitizenId(citizenid, true)
    if not player then return false, 'player_not_found' end
    if not player.Functions.SetJob(jobName, grade) then return false, 'set_job_failed' end
    player.Functions.Save()
    return true
end

---@return boolean ok, string? err
function Bridge.removeJob(citizenid, jobName)
    local player = Bridge.getPlayerByCitizenId(citizenid, true)
    if not player then return false, 'player_not_found' end
    if player.PlayerData.job.name ~= jobName then return true end
    if not player.Functions.SetJob('unemployed', 0) then return false, 'remove_job_failed' end
    player.Functions.Save()
    return true
end

local function getSharedJob(jobName)
    -- GetShared reads live data; older qb-core builds lack it, so fall back to the core object.
    local ok, job = pcall(function() return exports['qb-core']:GetShared('Jobs', jobName) end)
    if ok and job then return job end
    return QBCore.Shared.Jobs[jobName]
end

---@return table<integer, true>? grades nil when the job does not exist
function Bridge.getJobGrades(jobName)
    local job = getSharedJob(jobName)
    if not job then return nil end
    local grades = {}
    for grade in pairs(job.grades or {}) do
        grades[tonumber(grade)] = true
    end
    return grades
end

---@return table? data the framework's grade entry ({ name, payment, isboss, ... })
function Bridge.getJobGradeData(jobName, grade)
    local job = getSharedJob(jobName)
    return job and job.grades and job.grades[tostring(grade)] or nil
end

local function updateJob(jobName, job)
    local ok, res, err = pcall(function() return exports['qb-core']:UpdateJob(jobName, job) end)
    if not ok then
        if not QBCore.Functions.UpdateJob then return false, 'update_qb_core' end
        res, err = QBCore.Functions.UpdateJob(jobName, job)
    end
    if res == false then return false, err or 'framework_rejected' end
    return true
end

---Creates or updates a grade. QBCore keeps this in memory only, so cmd_chain re-applies
---its saved structure on every start. Other fields on the grade (isboss, ...) are kept.
---@return boolean ok, string? err
function Bridge.upsertJobGrade(jobName, grade, data)
    local job = getSharedJob(jobName)
    if not job then return false, 'job_not_found' end
    local key = tostring(grade)
    local merged = job.grades[key] or {}
    merged.name = data.name
    merged.payment = data.payment
    for _, flag in ipairs(Bridge.gradeFlags) do
        if data[flag] ~= nil then merged[flag] = data[flag] or nil end -- false removes the key
    end
    job.grades[key] = merged
    return updateJob(jobName, job)
end

---@return boolean ok, string? err
function Bridge.removeJobGrade(jobName, grade)
    local job = getSharedJob(jobName)
    if not job then return false, 'job_not_found' end
    job.grades[tostring(grade)] = nil
    return updateJob(jobName, job)
end

---QBCore jobs live in qb-core/shared/jobs.lua alongside other settings; cmd_chain does
---not rewrite it. Grades are re-applied from the cmd_chain database on every start.
function Bridge.persistJobs()
    return true, 'memory_only'
end

---Everyone holding the job, online or offline. Reads qb-core's own players table
---(read-only); online players are overlaid with live data.
---@return { citizenid: string, grade: integer, name: string }[]
function Bridge.getJobMembers(jobName)
    local rows = MySQL.query.await([[
        SELECT citizenid, charinfo, job FROM players
        WHERE JSON_UNQUOTE(JSON_EXTRACT(job, '$.name')) = ?
    ]], { jobName }) or {}

    local byCid = {}
    for i = 1, #rows do
        local row = rows[i]
        local job = row.job and json.decode(row.job) or {}
        local info = row.charinfo and json.decode(row.charinfo) or {}
        byCid[row.citizenid] = {
            citizenid = row.citizenid,
            grade = tonumber(job.grade and job.grade.level) or 0,
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
    -- SetJob/SetJobDuty fire OnPlayerUpdated; qb-core re-fires OnJobUpdate from it.
    -- QBCore:Server:SetDuty only fires from the /duty toggle, so we listen to both.
    AddEventHandler('QBCore:Server:OnJobUpdate', function(src) cb(src) end)
    AddEventHandler('QBCore:Server:SetDuty', function(src) cb(src) end)
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
