-- Qbox (qbx_core) mock: exports, events and player_groups as cmd_chain's bridge uses them.
-- Behaviour mirrors qbx_core main (server/player.lua, server/groups.lua).
local M = {}

function M.new(env, S, deepcopy, opts)
    local fw = { name = 'qbx', maxJobs = 2 }

    -- Default police grades as shipped by Qbox (0-4). With the editor off, the owner is
    -- expected to have added 5 and 6 by hand (README install step 4).
    local JOBS = {
        unemployed = { label = 'Civilian', defaultDuty = true, offDutyPay = false, grades = { [0] = { name = 'Freelancer', payment = 10 } } },
        mechanic = { label = 'Mechanic', type = 'mechanic', defaultDuty = true, offDutyPay = false, grades = { [0] = { name = 'Recruit', payment = 50 } } },
        police = {
            label = 'LSPD', type = 'leo', defaultDuty = true, offDutyPay = false,
            grades = {
                [0] = { name = 'Recruit', payment = 50 },
                [1] = { name = 'Officer', payment = 75 },
                [2] = { name = 'Sergeant', payment = 100 },
                [3] = { name = 'Lieutenant', payment = 125 },
                [4] = { name = 'Chief', isboss = true, bankAuth = true, payment = 150 },
            },
        },
    }
    if not opts.editable then
        JOBS.police.grades[5] = { name = 'Captain', payment = 175 }
        JOBS.police.grades[6] = { name = 'Chief', isboss = true, payment = 200 }
    end
    fw.JOBS = JOBS
    S.files['qbx_core/shared/jobs.lua'] = S.files['qbx_core/shared/jobs.lua'] or '-- original jobs file'

    local P, online = {}, {}
    fw.P, fw.online = P, online

    function env.GetResourceState(name) return name == 'qbx_core' and 'started' or 'missing' end
    function env.GetPlayers()
        local list = {}
        for src in pairs(online) do list[#list + 1] = tostring(src) end
        return list
    end

    local function isOnline(cid)
        local src = P[cid] and P[cid].source
        return src ~= nil and online[src] == cid
    end

    local function snapshot(cid, offline)
        local pd = P[cid]
        if not pd then return nil end
        local data = deepcopy(pd)
        if offline then data.source = nil end
        return { PlayerData = data, Offline = offline == true }
    end

    local function toPlayerJob(name, grade)
        local job = JOBS[name]
        local g = job.grades[grade] or {}
        return { name = name, label = job.label, type = job.type, onduty = job.defaultDuty or false,
            payment = g.payment or 0, isboss = g.isboss or false, grade = { name = g.name, level = grade } }
    end

    function fw.addPlayer(cid, src, job, grade, first)
        P[cid] = {
            citizenid = cid, source = src,
            charinfo = { firstname = first, lastname = 'Test' },
            job = toPlayerJob(job, job == 'unemployed' and 0 or grade),
            jobs = {},
        }
        P[cid].job.grade.level = grade
        if job ~= 'unemployed' then P[cid].jobs[job] = grade end
        if src then online[src] = cid end
    end

    local function fireJobUpdate(cid)
        if isOnline(cid) then env.TriggerEvent('QBCore:Server:OnJobUpdate', P[cid].source, deepcopy(P[cid].job)) end
    end

    local qbx = {}
    function qbx:GetPlayer(src) local cid = online[tonumber(src)]; return cid and snapshot(cid) or nil end
    function qbx:GetPlayerByCitizenId(cid) if isOnline(cid) then return snapshot(cid) end end
    function qbx:GetOfflinePlayer(cid) return snapshot(cid, true) end
    function qbx:GetJob(name) return deepcopy(JOBS[name]) end
    function qbx:GetJobs() return deepcopy(JOBS) end
    function qbx:UpsertJobGrade(name, grade, data, commit)
        assert(commit == false, 'cmd_chain must not use qbx_core commitToFile')
        if JOBS[name] then JOBS[name].grades[grade] = deepcopy(data) end
    end
    function qbx:RemoveJobGrade(name, grade, commit)
        assert(commit == false, 'cmd_chain must not use qbx_core commitToFile')
        if JOBS[name] then JOBS[name].grades[grade] = nil end
    end
    function qbx:SetPlayerPrimaryJob(cid, name)
        local pd = P[cid]
        if not pd then return false, { code = 'player_not_found' } end
        local grade = name == 'unemployed' and 0 or pd.jobs[name]
        if not grade then return false, { code = 'player_not_in_job' } end
        pd.job = toPlayerJob(name, grade)
        fireJobUpdate(cid)
        return true
    end
    function qbx:AddPlayerToJob(cid, name, grade)
        local pd = P[cid]
        if not pd then return false, { code = 'player_not_found' } end
        if not JOBS[name] or not JOBS[name].grades[grade] then return false, { code = 'job_missing_grade' } end
        if pd.jobs[name] == grade then return true end
        local count = 0
        for _ in pairs(pd.jobs) do count = count + 1 end
        if count >= fw.maxJobs and not pd.jobs[name] then return false, { code = 'max_jobs' } end
        pd.jobs[name] = grade
        if isOnline(cid) then env.TriggerEvent('qbx_core:server:onGroupUpdate', pd.source, name, grade) end
        if pd.job.name == name then qbx:SetPlayerPrimaryJob(cid, name) end
        return true
    end
    function qbx:RemovePlayerFromJob(cid, name)
        local pd = P[cid]
        if not pd then return false, { code = 'player_not_found' } end
        if not pd.jobs[name] then return true end
        pd.jobs[name] = nil
        if pd.job.name == name then pd.job = toPlayerJob('unemployed', 0) end
        if isOnline(cid) then env.TriggerEvent('qbx_core:server:onGroupUpdate', pd.source, name) end
        fireJobUpdate(cid)
        return true
    end
    fw.exports = { qbx_core = qbx }

    -- helpers used by the suites (framework-neutral names)
    function fw.grade(cid, job) return P[cid] and P[cid].jobs[job] end
    function fw.primaryJob(cid) return P[cid] and P[cid].job.name end
    function fw.gradeData(job, grade) return JOBS[job] and deepcopy(JOBS[job].grades[grade]) end
    function fw.externalSetJob(cid, job, grade)
        qbx:AddPlayerToJob(cid, job, grade)
        qbx:SetPlayerPrimaryJob(cid, job)
    end
    function fw.externalRemoveJob(cid, job) qbx:RemovePlayerFromJob(cid, job) end
    function fw.setDuty(cid, onDuty)
        P[cid].job.onduty = onDuty
        env.TriggerEvent('QBCore:Server:SetDuty', P[cid].source, onDuty)
    end
    function fw.logout(src)
        online[src] = nil
        env.TriggerEvent('QBCore:Server:OnPlayerUnload', src)
    end
    function fw.login(src, cid)
        online[src] = cid
        P[cid].source = src
        env.TriggerEvent('QBCore:Server:PlayerLoaded', snapshot(cid))
    end
    ---Parsed qbx_core/shared/jobs.lua as written by cmd_chain (nil if untouched).
    function fw.jobsFile()
        local text = S.files['qbx_core/shared/jobs.lua']
        if not text or text == '-- original jobs file' then return nil end
        return assert(load(text, 'jobs.lua', 't', {}))()
    end

    function fw.sql(sql, p)
        if not sql:find('FROM player_groups') then return nil end
        local rows = {}
        for cid, pd in pairs(P) do
            local g = pd.jobs[p[1]]
            if g then rows[#rows + 1] = { citizenid = cid, grade = g, charinfo = env.json.encode(pd.charinfo) } end
        end
        return rows
    end

    return fw
end

return M
