-- QBCore (qb-core) mock: core object, exports, events and the players table as cmd_chain's
-- bridge uses them. Behaviour mirrors qb-core main (server/player.lua, server/events.lua,
-- server/exports.lua): SetJob fires OnPlayerUpdated, which qb-core re-fires as OnJobUpdate.
local M = {}

function M.new(env, S, deepcopy, opts)
    local fw = { name = 'qb' }

    local police = {
        ['0'] = { name = 'Recruit', payment = 50 },
        ['1'] = { name = 'Officer', payment = 75 },
        ['2'] = { name = 'Sergeant', payment = 100 },
        ['3'] = { name = 'Lieutenant', payment = 125 },
        ['4'] = { name = 'Chief', isboss = true, payment = 150 },
    }
    if not opts.editable then
        police['5'] = { name = 'Captain', payment = 175 }
        police['6'] = { name = 'Chief', isboss = true, payment = 200 }
    end
    local SHARED = { Jobs = {
        unemployed = { label = 'Civilian', defaultDuty = true, grades = { ['0'] = { name = 'Freelancer', payment = 10 } } },
        police = { label = 'Law Enforcement', type = 'leo', defaultDuty = true, grades = police },
    } }
    fw.SHARED = SHARED

    local P, online = {}, {}
    fw.P, fw.online = P, online

    function env.GetResourceState(name) return name == 'qb-core' and 'started' or 'missing' end
    function env.GetPlayers()
        local list = {}
        for src in pairs(online) do list[#list + 1] = tostring(src) end
        return list
    end

    local function isOnline(cid)
        local src = P[cid] and P[cid].source
        return src ~= nil and online[src] == cid
    end

    local function updated(cid)
        if isOnline(cid) then env.TriggerEvent('QBCore:Server:OnPlayerUpdated', P[cid].source, 'job', deepcopy(P[cid].job)) end
    end

    -- qb-core/server/player.lua Player:SetJob: an unknown grade becomes "No Grades" level 0.
    local function setJob(cid, job, grade)
        local info = SHARED.Jobs[job]
        if not info then return false end
        local g = info.grades[tostring(grade)]
        P[cid].job = {
            name = job, label = info.label, onduty = info.defaultDuty, type = info.type or 'none',
            grade = g and { name = g.name, level = tonumber(grade), payment = g.payment } or { name = 'No Grades', level = 0, payment = 30 },
        }
        updated(cid)
        return true
    end

    local function makePlayer(cid, offline)
        if not P[cid] then return nil end
        local data = deepcopy(P[cid])
        if offline then data.source = nil end
        return {
            PlayerData = data,
            Offline = offline == true,
            Functions = {
                SetJob = function(job, grade) return setJob(cid, job, grade) end,
                SetJobDuty = function(onDuty) P[cid].job.onduty = onDuty == true; updated(cid) end,
                Save = function() end,
            },
        }
    end

    function fw.addPlayer(cid, src, job, grade, first)
        local info = SHARED.Jobs[job]
        P[cid] = {
            citizenid = cid, source = src,
            charinfo = { firstname = first, lastname = 'Test' },
            job = { name = job, label = info.label, onduty = true, grade = { level = grade } },
        }
        if src then online[src] = cid end
    end

    -- qb-core/server/events.lua: OnPlayerUpdated('job') re-fires OnJobUpdate
    env.AddEventHandler('QBCore:Server:OnPlayerUpdated', function(src, key, val)
        if key == 'job' then env.TriggerEvent('QBCore:Server:OnJobUpdate', src, val) end
    end)

    local QBCore = { Shared = SHARED, Functions = {} }
    function QBCore.Functions.GetPlayer(src) local cid = online[tonumber(src)]; return cid and makePlayer(cid) or nil end
    function QBCore.Functions.GetPlayerByCitizenId(cid) if isOnline(cid) then return makePlayer(cid) end end
    function QBCore.Functions.GetOfflinePlayerByCitizenId(cid) return makePlayer(cid, true) end

    local qbcore = {}
    function qbcore:GetCoreObject() return QBCore end
    function qbcore:GetShared(ns, item) return deepcopy(item and SHARED[ns][item] or SHARED[ns]) end
    function qbcore:UpdateJob(name, job)
        if not SHARED.Jobs[name] then return false, 'job_not_exists' end
        SHARED.Jobs[name] = deepcopy(job)
        return true, 'success'
    end
    fw.exports = { ['qb-core'] = qbcore }

    -- helpers used by the suites (framework-neutral names)
    function fw.grade(cid, job)
        local pd = P[cid]
        if pd and pd.job.name == job then return pd.job.grade.level end
    end
    function fw.primaryJob(cid) return P[cid] and P[cid].job.name end
    function fw.gradeData(job, grade)
        local info = SHARED.Jobs[job]
        return info and deepcopy(info.grades[tostring(grade)])
    end
    function fw.externalSetJob(cid, job, grade) setJob(cid, job, grade) end
    function fw.externalRemoveJob(cid) setJob(cid, 'unemployed', 0) end
    function fw.setDuty(cid, onDuty)
        P[cid].job.onduty = onDuty
        updated(cid)
    end
    function fw.logout(src)
        online[src] = nil
        env.TriggerEvent('QBCore:Server:OnPlayerUnload', src)
    end
    function fw.login(src, cid)
        online[src] = cid
        P[cid].source = src
        env.TriggerEvent('QBCore:Server:PlayerLoaded', makePlayer(cid))
    end
    function fw.jobsFile() return nil end -- cmd_chain never rewrites qb-core's jobs.lua

    function fw.sql(sql, p)
        if not sql:find('FROM players') then return nil end
        local rows = {}
        for cid, pd in pairs(P) do
            if pd.job.name == p[1] then
                rows[#rows + 1] = { citizenid = cid, charinfo = env.json.encode(pd.charinfo), job = env.json.encode(pd.job) }
            end
        end
        return rows
    end

    return fw
end

return M
