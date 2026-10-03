if not Bridge then
    error('[cmd_chain] No supported framework found. Start qbx_core or qb-core before cmd_chain.')
end

-- roster.manage_all grants every roster.* capability plus structure.manage.
local MANAGE_ALL_GRANTS = { 'roster.hire', 'roster.fire', 'roster.promote', 'roster.set_division', 'roster.set_callsign', 'structure.manage' }

CC = {
    ready = false,
    depts = {},     -- [deptId] = compiled department
    deptOrder = {}, -- dept ids, sorted, for deterministic "first department" picks
    jobToDept = {}, -- [jobName] = deptId
    rows = {},      -- [deptId][citizenid] = { callsign, divisions, hiredAt }
    online = {},    -- [src] = { citizenid, name, primary, grades = { [deptId] = grade }, duty = { [deptId] = bool } }
    srcByCid = {},  -- [citizenid] = src
    suppress = {},  -- ['citizenid:deptId'] = true while cmd_chain itself is writing (no sync audit)
}

CC.errors = {
    not_ready = 'Chain of Command is still starting.',
    actor_not_found = 'Actor not found.',
    unknown_department = 'Unknown department.',
    department_disabled = 'That department is disabled. Check the server console.',
    unknown_action = 'Unknown action.',
    department_required = 'Specify a department.',
    not_in_department = 'You are not in that department.',
    no_permission = 'Your rank does not allow that.',
    rate_limited = 'Slow down. Too many roster actions.',
    invalid_target = 'Invalid target.',
    target_not_found = 'Target not found.',
    cannot_target_self = 'You cannot do that to yourself.',
    target_rank_too_high = 'You can only change members below your rank.',
    rank_ceiling = 'You cannot set a rank equal to or above your own.',
    invalid_grade = 'That grade is not a rank in this department.',
    grade_missing_in_framework = 'That grade does not exist in the framework job. Add it to your jobs file.',
    already_member = 'Already a member of this department.',
    not_a_member = 'Not a member of this department.',
    not_a_promotion = 'The new rank must be higher than the current rank.',
    not_a_demotion = 'The new rank must be lower than the current rank.',
    invalid_callsign = 'Callsign does not match the department format.',
    callsign_taken = 'Callsign already in use.',
    invalid_division = 'Unknown division.',
    max_jobs = 'That player already holds the maximum number of jobs.',
    structure_locked = 'Rank editing is turned off (Config.Structure.editable).',
    unknown_rank = 'That rank does not exist.',
    invalid_rank = 'Invalid rank data.',
    invalid_rank_name = 'Rank name must be 1-50 characters.',
    invalid_payment = 'Invalid pay amount.',
    invalid_capability = 'Capability names may only use letters, numbers, dots, dashes and underscores.',
    cannot_grant_capability = 'You can only grant capabilities you have yourself.',
    affects_higher_ranks = 'That change would alter the permissions of your rank or ranks above it.',
    rank_in_use = 'Members still hold that rank. Move them first.',
    last_rank = 'A department needs at least one rank.',
    job_not_found = 'The framework job does not exist.',
    framework_rejected = 'The framework rejected the change. Check the server console.',
    update_qb_core = 'Your qb-core is too old for runtime job edits. Update qb-core.',
    player_not_found = 'Player not found.',
    internal_error = 'Internal error. Check the server console.',
}

function CC.describe(err)
    return CC.errors[err] or tostring(err)
end

function CC.debug(msg, ...)
    if Config.Debug then print(('[cmd_chain] ' .. msg):format(...)) end
end

-- ───────────────────────────── config ─────────────────────────────

---Compiles a rank list into { [grade] = rank }. A rank has its own caps plus every cap
---of every rank below it.
---@param list { grade: integer, name: string, caps: string[]?, payment: integer? }[]
---@return table? byGrade, table|string topDown_or_err, integer? lowest
function CC.compileRanks(list)
    local ranks = {}
    for i = 1, #list do ranks[i] = list[i] end
    table.sort(ranks, function(a, b) return a.grade < b.grade end)

    local byGrade, inherited, topDown = {}, {}, {}
    for i = 1, #ranks do
        local rank = ranks[i]
        if byGrade[rank.grade] then return nil, ('grade %s is listed twice'):format(rank.grade) end
        local own = {}
        for _, cap in ipairs(rank.caps or {}) do
            inherited[cap] = true
            own[#own + 1] = cap
        end
        table.sort(own)
        local caps = {}
        for cap in pairs(inherited) do caps[cap] = true end
        if caps['roster.manage_all'] then
            for _, cap in ipairs(MANAGE_ALL_GRANTS) do caps[cap] = true end
        end
        byGrade[rank.grade] = { grade = rank.grade, name = rank.name, caps = caps, ownCaps = own, payment = rank.payment }
        table.insert(topDown, 1, { grade = rank.grade, name = rank.name })
    end
    return byGrade, topDown, ranks[1] and ranks[1].grade
end

---Replaces a department's ranks.
function CC.applyRanks(deptId, list)
    local byGrade, topDown, lowest = CC.compileRanks(list)
    if not byGrade then error(('[cmd_chain] department %s: %s'):format(deptId, topDown)) end
    if not lowest then error(('[cmd_chain] department %s has no ranks'):format(deptId)) end
    local dept = CC.depts[deptId]
    dept.ranks, dept.rankList, dept.lowest = byGrade, topDown, lowest
end

---Plain rank records (top to bottom) for saving, the editor and the boot cache.
function CC.rankRecords(deptId)
    local records = {}
    for _, entry in ipairs(CC.depts[deptId].rankList) do
        local rank = CC.depts[deptId].ranks[entry.grade]
        local caps = {}
        for i, cap in ipairs(rank.ownCaps) do caps[i] = cap end
        records[#records + 1] = { grade = rank.grade, name = rank.name, payment = rank.payment, caps = caps }
    end
    return records
end

local function compileDepartments()
    for id, def in pairs(Config.Departments) do
        assert(type(def.job) == 'string', ('[cmd_chain] department %s has no job'):format(id))
        assert(not CC.jobToDept[def.job], ('[cmd_chain] job %s is mapped to two departments (%s, %s)'):format(def.job, CC.jobToDept[def.job], id))
        assert(type(def.ranks) == 'table' and #def.ranks > 0, ('[cmd_chain] department %s has no ranks'):format(id))

        local divisionSet = {}
        for _, division in ipairs(def.divisions or {}) do divisionSet[division] = true end

        CC.depts[id] = {
            id = id,
            label = def.label or id,
            job = def.job,
            callsignFormat = def.callsignFormat,
            divisions = def.divisions or {},
            divisionSet = divisionSet,
        }
        CC.applyRanks(id, def.ranks)
        CC.jobToDept[def.job] = id
        CC.rows[id] = {}
        CC.deptOrder[#CC.deptOrder + 1] = id
    end
    table.sort(CC.deptOrder)
end

compileDepartments()

---The configured rank for a grade. Grades between configured ranks inherit the
---nearest configured rank below them.
function CC.effectiveRank(byGrade, grade)
    if grade == nil then return nil end
    if byGrade[grade] then return byGrade[grade] end
    local best
    for g, rank in pairs(byGrade) do
        if g < grade and (not best or g > best.grade) then best = rank end
    end
    return best
end

function CC.rankFor(deptId, grade)
    local dept = CC.depts[deptId]
    if not dept then return nil end
    return CC.effectiveRank(dept.ranks, grade)
end

function CC.hasCap(deptId, grade, cap)
    local rank = CC.rankFor(deptId, grade)
    return rank ~= nil and rank.caps[cap] == true
end

function CC.capList(deptId, grade)
    local rank = CC.rankFor(deptId, grade)
    local list = {}
    if rank then
        for cap in pairs(rank.caps) do list[#list + 1] = cap end
        table.sort(list)
    end
    return list
end

function CC.rankName(deptId, grade)
    local rank = CC.depts[deptId] and CC.depts[deptId].ranks[grade]
    return rank and rank.name or ('Grade %s'):format(grade)
end

-- ───────────────────────────── member rows ─────────────────────────────

local function copy(list)
    local out = {}
    for i = 1, #(list or {}) do out[i] = list[i] end
    return out
end

function CC.ensureRow(deptId, cid)
    local row = CC.rows[deptId][cid]
    if row then return row end
    MySQL.insert.await('INSERT IGNORE INTO cmd_chain_members (citizenid, dept, divisions) VALUES (?, ?, ?)', { cid, deptId, '[]' })
    row = { callsign = nil, divisions = {}, hiredAt = os.time() }
    CC.rows[deptId][cid] = row
    return row
end

function CC.deleteRow(deptId, cid)
    if not CC.rows[deptId][cid] then return false end
    MySQL.query.await('DELETE FROM cmd_chain_members WHERE citizenid = ? AND dept = ?', { cid, deptId })
    CC.rows[deptId][cid] = nil
    return true
end

function CC.buildMember(deptId, cid, grade, onDuty, name, online)
    local dept = CC.depts[deptId]
    local row = CC.rows[deptId][cid] or {}
    return {
        citizenid = cid,
        name = name,
        dept = deptId,
        deptLabel = dept.label,
        rank = CC.rankName(deptId, grade),
        grade = grade,
        callsign = row.callsign,
        divisions = copy(row.divisions),
        onDuty = onDuty == true,
        online = online == true,
        hiredAt = row.hiredAt,
    }
end

---Current member data for a citizen in a department, online or offline. nil if not a member.
function CC.memberOf(cid, deptId)
    local src = CC.srcByCid[cid]
    local state = src and CC.online[src]
    if state then
        local grade = state.grades[deptId]
        if grade == nil then return nil end
        return CC.buildMember(deptId, cid, grade, state.duty[deptId], state.name, true)
    end
    local player = Bridge.getPlayerByCitizenId(cid, true)
    if not player then return nil end
    local dept = CC.depts[deptId]
    local grade = Bridge.getJobGrade(player, dept.job)
    if grade == nil then return nil end
    return CC.buildMember(deptId, cid, grade, Bridge.isOnDuty(player, dept.job), Bridge.getName(player), Bridge.getSource(player) ~= nil)
end

-- ───────────────────────────── events ─────────────────────────────

local function deptAudience(deptId, cid)
    local targets = {}
    for src, state in pairs(CC.online) do
        if state.citizenid == cid or state.grades[deptId] ~= nil then targets[#targets + 1] = src end
    end
    return targets
end

---member is nil when the citizen left the department.
function CC.emitMember(cid, deptId, member)
    TriggerEvent('cmd_chain:memberUpdated', cid, member, deptId)
    for _, src in ipairs(deptAudience(deptId, cid)) do
        TriggerClientEvent('cmd_chain:memberUpdated', src, cid, member, deptId)
    end
    local src = CC.srcByCid[cid]
    if src then CC.pushClient(src) end
end

function CC.emitDuty(cid, deptId, onDuty)
    TriggerEvent('cmd_chain:dutyChanged', cid, onDuty, deptId)
    for _, src in ipairs(deptAudience(deptId, cid)) do
        TriggerClientEvent('cmd_chain:dutyChanged', src, cid, onDuty, deptId)
    end
end

function CC.pushClient(src)
    local state = CC.online[src]
    local payload = { members = {}, caps = {}, primary = nil }
    if state then
        for deptId, grade in pairs(state.grades) do
            payload.members[deptId] = CC.buildMember(deptId, state.citizenid, grade, state.duty[deptId], state.name, true)
            payload.caps[deptId] = CC.capList(deptId, grade)
        end
        payload.primary = state.primary
    end
    TriggerClientEvent('cmd_chain:client:sync', src, payload)
end

-- ───────────────────────────── sync with the framework ─────────────────────────────

---Brings member rows in line with the framework (the source of truth for rank).
---Changes made outside cmd_chain (e.g. /setjob) are audited with a NULL actor.
---@param info { name: string, duty: table<string, boolean>, online: boolean }
function CC.reconcileCitizen(cid, grades, prevGrades, info)
    for _, deptId in ipairs(CC.deptOrder) do
        if not CC.depts[deptId].enabled then goto continue end
        local quiet = CC.suppress[cid .. ':' .. deptId]
        local grade = grades[deptId]
        local hadRow = CC.rows[deptId][cid] ~= nil
        local prev = prevGrades and prevGrades[deptId]

        if grade ~= nil and not hadRow then
            CC.ensureRow(deptId, cid)
            if not quiet then
                Audit.log(deptId, nil, cid, 'sync_hire', nil, grade)
                CC.emitMember(cid, deptId, CC.buildMember(deptId, cid, grade, info.duty[deptId], info.name, info.online))
            end
        elseif grade == nil and hadRow then
            CC.deleteRow(deptId, cid)
            if not quiet then
                Audit.log(deptId, nil, cid, 'sync_fire', prev, nil)
                CC.emitMember(cid, deptId, nil)
            end
        elseif grade ~= nil and prev ~= nil and prev ~= grade and not quiet then
            Audit.log(deptId, nil, cid, 'sync_grade', prev, grade)
            CC.emitMember(cid, deptId, CC.buildMember(deptId, cid, grade, info.duty[deptId], info.name, info.online))
        end
        ::continue::
    end
end

function CC.dropPlayer(src)
    local state = CC.online[src]
    if not state then return end
    CC.online[src] = nil
    if CC.srcByCid[state.citizenid] == src then CC.srcByCid[state.citizenid] = nil end
    for deptId, onDuty in pairs(state.duty) do
        if onDuty then CC.emitDuty(state.citizenid, deptId, false) end
    end
end

function CC.refreshPlayer(src)
    src = tonumber(src)
    if not src then return end
    local player = Bridge.getPlayer(src)
    local prev = CC.online[src]
    if not player then
        CC.dropPlayer(src)
        return
    end

    local cid = Bridge.getCitizenId(player)
    if prev and prev.citizenid ~= cid then
        CC.dropPlayer(src) -- character switch
        prev = nil
    end

    local primaryJob = Bridge.getJob(player)
    local state = {
        citizenid = cid,
        name = Bridge.getName(player),
        primary = CC.jobToDept[primaryJob],
        grades = {},
        duty = {},
    }
    for _, deptId in ipairs(CC.deptOrder) do
        local job = CC.depts[deptId].job
        local grade = Bridge.getJobGrade(player, job)
        if grade ~= nil and CC.depts[deptId].enabled then
            state.grades[deptId] = grade
            state.duty[deptId] = Bridge.isOnDuty(player, job)
        end
    end
    if state.primary and state.grades[state.primary] == nil then state.primary = nil end

    CC.online[src] = state
    CC.srcByCid[cid] = src

    CC.reconcileCitizen(cid, state.grades, prev and prev.grades, { name = state.name, duty = state.duty, online = true })

    for _, deptId in ipairs(CC.deptOrder) do
        local before = prev and prev.duty[deptId] or false
        local after = state.duty[deptId] or false
        if before ~= after then CC.emitDuty(cid, deptId, after) end
    end

    CC.pushClient(src)
end

---Re-syncs a citizen after a write. Offline citizens are left alone: QBCore saves
---offline players asynchronously, so reading back now could see stale data.
function CC.syncCitizen(cid)
    local src = CC.srcByCid[cid]
    if src then CC.refreshPlayer(src) end
end

-- ───────────────────────────── rate limiting ─────────────────────────────

local hits = {}

function CC.rateLimited(src)
    local now = GetGameTimer()
    local windowMs = Config.RateLimit.window * 1000
    local list, kept = hits[src] or {}, {}
    for i = 1, #list do
        if now - list[i] < windowMs then kept[#kept + 1] = list[i] end
    end
    if #kept >= Config.RateLimit.max then
        hits[src] = kept
        return true
    end
    kept[#kept + 1] = now
    hits[src] = kept
    return false
end

-- ───────────────────────────── rank structure (v1.1) ─────────────────────────────
-- With Config.Structure.editable, rank definitions (name, pay, caps per grade) live in
-- cmd_chain_ranks and are pushed into the framework job. A player's rank is still only
-- their framework job grade.

CC.structureEnabled = Config.Structure ~= nil and Config.Structure.editable == true
local CACHE_FILE = 'structure.cache.json'

---Pushes a department's ranks into the framework job. Returns true if anything changed.
function CC.pushRanks(deptId)
    local dept = CC.depts[deptId]
    local changed = false
    for grade, rank in pairs(dept.ranks) do
        local current = Bridge.getJobGradeData(dept.job, grade)
        local payment = rank.payment or 0
        if not current or current.name ~= rank.name or tonumber(current.payment or 0) ~= payment then
            local ok, err = Bridge.upsertJobGrade(dept.job, grade, { name = rank.name, payment = payment })
            if ok then
                changed = true
            else
                print(('^1[cmd_chain] could not create grade %d (%s) in job %s: %s^0'):format(grade, rank.name, dept.job, CC.describe(err)))
            end
        end
    end
    return changed
end

---Saves framework job data to disk where the framework supports it (Qbox jobs.lua).
function CC.persistFramework()
    if not Config.Structure.writeQbxJobsFile then return end
    local ok, err = Bridge.persistJobs()
    if not ok then print(('^1[cmd_chain] could not save jobs file: %s^0'):format(err)) end
end

---Boot cache: read synchronously at load so grades exist in the framework before anyone
---logs in. (QBCore resets a player's job if their grade is missing at login.)
function CC.saveCache()
    local data = {}
    for _, deptId in ipairs(CC.deptOrder) do data[deptId] = CC.rankRecords(deptId) end
    SaveResourceFile(GetCurrentResourceName(), CACHE_FILE, json.encode(data), -1)
end

local function applyCache()
    local raw = LoadResourceFile(GetCurrentResourceName(), CACHE_FILE)
    if not raw or raw == '' then return end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return end
    for deptId, records in pairs(data) do
        local dept = CC.depts[deptId]
        if dept and type(records) == 'table' and #records > 0 and pcall(CC.applyRanks, deptId, records) then
            if Bridge.getJobGrades(dept.job) then CC.pushRanks(deptId) end
        end
    end
end

function CC.saveRank(deptId, record)
    MySQL.query.await([[
        INSERT INTO cmd_chain_ranks (dept, grade, name, payment, caps) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), payment = VALUES(payment), caps = VALUES(caps)
    ]], { deptId, record.grade, record.name, record.payment or 0, #record.caps == 0 and '[]' or json.encode(record.caps) })
end

function CC.deleteRank(deptId, grade)
    MySQL.query.await('DELETE FROM cmd_chain_ranks WHERE dept = ? AND grade = ?', { deptId, grade })
end

---Loads a department's ranks from the database, seeding from config.lua on first start.
function CC.loadStructure(dept)
    local rows = MySQL.query.await('SELECT grade, name, payment, caps FROM cmd_chain_ranks WHERE dept = ?', { dept.id }) or {}
    if #rows > 0 then
        local records = {}
        for i, row in ipairs(rows) do
            local ok, caps = pcall(json.decode, row.caps or '[]')
            records[i] = {
                grade = tonumber(row.grade),
                name = row.name,
                payment = tonumber(row.payment) or 0,
                caps = ok and type(caps) == 'table' and caps or {},
            }
        end
        CC.applyRanks(dept.id, records)
        return
    end

    -- First start: seed from config. Keep the framework's pay for grades it already has.
    local def = Config.Departments[dept.id]
    local records = {}
    for i, rank in ipairs(def.ranks) do
        local current = Bridge.getJobGradeData(dept.job, rank.grade)
        records[i] = {
            grade = rank.grade,
            name = rank.name,
            payment = math.tointeger(tonumber(current and current.payment or rank.payment) or 0) or 0,
            caps = rank.caps or {},
        }
        CC.saveRank(dept.id, records[i])
    end
    CC.applyRanks(dept.id, records)
    print(('[cmd_chain] department %s: rank structure seeded from config.lua (%d ranks)'):format(dept.id, #records))
end

---After a structure edit: save the jobs file and cache, notify scripts, refresh clients.
function CC.afterStructureChange(deptId)
    CC.persistFramework()
    CC.saveCache()
    TriggerEvent('cmd_chain:structureUpdated', deptId)
    TriggerClientEvent('cmd_chain:structureUpdated', -1, deptId)
    for src, state in pairs(CC.online) do
        if state.grades[deptId] ~= nil then CC.pushClient(src) end
    end
end

if CC.structureEnabled then applyCache() end

-- ───────────────────────────── startup ─────────────────────────────

local function createTables()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cmd_chain_members` (
          `citizenid`  VARCHAR(50) NOT NULL,
          `dept`       VARCHAR(50) NOT NULL,
          `callsign`   VARCHAR(16) NULL DEFAULT NULL,
          `divisions`  JSON NULL DEFAULT NULL,
          `hired_at`   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`citizenid`, `dept`),
          UNIQUE KEY `uq_dept_callsign` (`dept`, `callsign`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cmd_chain_audit` (
          `id`               BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
          `dept`             VARCHAR(50) NOT NULL,
          `actor_citizenid`  VARCHAR(50) NULL DEFAULT NULL,
          `target_citizenid` VARCHAR(50) NULL DEFAULT NULL,
          `action`           VARCHAR(32) NOT NULL,
          `old_value`        TEXT NULL DEFAULT NULL,
          `new_value`        TEXT NULL DEFAULT NULL,
          `created_at`       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
          PRIMARY KEY (`id`),
          KEY `idx_dept_time` (`dept`, `created_at`),
          KEY `idx_target` (`target_citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
    -- v1.0 -> v1.1: structure changes have no target player.
    MySQL.query.await('ALTER TABLE `cmd_chain_audit` MODIFY `target_citizenid` VARCHAR(50) NULL DEFAULT NULL')
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `cmd_chain_ranks` (
          `dept`       VARCHAR(50) NOT NULL,
          `grade`      SMALLINT UNSIGNED NOT NULL,
          `name`       VARCHAR(50) NOT NULL,
          `payment`    INT UNSIGNED NOT NULL DEFAULT 0,
          `caps`       JSON NULL DEFAULT NULL,
          `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
          PRIMARY KEY (`dept`, `grade`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    ]])
end

local function loadRows()
    local rows = MySQL.query.await('SELECT citizenid, dept, callsign, divisions, UNIX_TIMESTAMP(hired_at) AS hired_at FROM cmd_chain_members') or {}
    for i = 1, #rows do
        local row = rows[i]
        if CC.rows[row.dept] then
            local ok, divisions = pcall(json.decode, row.divisions or '[]')
            CC.rows[row.dept][row.citizenid] = {
                callsign = row.callsign,
                divisions = ok and type(divisions) == 'table' and divisions or {},
                hiredAt = tonumber(row.hired_at),
            }
        end
    end
end

---Returns false when the department's job is missing from the framework.
local function jobExists(dept)
    if Bridge.getJobGrades(dept.job) then return true end
    print(('^1[cmd_chain] department %s: job "%s" does not exist in %s. Department disabled until fixed.^0'):format(dept.id, dept.job, Bridge.name))
    return false
end

local function warnMissingGrades(dept)
    local grades = Bridge.getJobGrades(dept.job) or {}
    for grade, rank in pairs(dept.ranks) do
        if not grades[grade] then
            print(('^3[cmd_chain] department %s: rank %s uses grade %d, which job "%s" does not have. Add it to your jobs file.^0'):format(dept.id, rank.name, grade, dept.job))
        end
    end
end

local function reconcileDepartment(dept)
    local holders = {}
    for _, member in ipairs(Bridge.getJobMembers(dept.job)) do
        holders[member.citizenid] = member.grade
        if not CC.rows[dept.id][member.citizenid] then
            CC.ensureRow(dept.id, member.citizenid)
            Audit.log(dept.id, nil, member.citizenid, 'sync_hire', nil, member.grade)
        end
    end
    for cid in pairs(CC.rows[dept.id]) do
        if holders[cid] == nil then
            CC.deleteRow(dept.id, cid)
            Audit.log(dept.id, nil, cid, 'sync_fire', nil, nil)
        end
    end
end

MySQL.ready(function()
    CreateThread(function()
        createTables()
        loadRows()
        local frameworkChanged = false
        for _, deptId in ipairs(CC.deptOrder) do
            local dept = CC.depts[deptId]
            dept.enabled = jobExists(dept)
            if dept.enabled and CC.structureEnabled then
                CC.loadStructure(dept)
                if CC.pushRanks(deptId) then frameworkChanged = true end
            end
        end
        if frameworkChanged then CC.persistFramework() end
        if CC.structureEnabled then CC.saveCache() end
        for _, deptId in ipairs(CC.deptOrder) do
            local dept = CC.depts[deptId]
            if dept.enabled then
                warnMissingGrades(dept)
                reconcileDepartment(dept)
            end
        end
        CC.ready = true
        for _, id in ipairs(GetPlayers()) do CC.refreshPlayer(tonumber(id)) end
        print(('[cmd_chain] ready on %s with %d department(s)'):format(Bridge.name, #CC.deptOrder))
    end)
end)

Bridge.onJobUpdate(function(src)
    if CC.ready then CC.refreshPlayer(src) end
end)

Bridge.onPlayerLoaded(function(src)
    if CC.ready then CC.refreshPlayer(src) end
end)

Bridge.onPlayerUnload(function(src)
    CC.dropPlayer(tonumber(src))
end)

AddEventHandler('playerDropped', function()
    local src = source
    CC.dropPlayer(src)
    hits[src] = nil
end)

-- ───────────────────────────── client callbacks ─────────────────────────────

local lastSync = {}

lib.callback.register('cmd_chain:sync', function(source)
    local now = GetGameTimer()
    if CC.ready and (not lastSync[source] or now - lastSync[source] > 1000) then
        lastSync[source] = now
        CC.refreshPlayer(source)
    end
    return true
end)

lib.callback.register('cmd_chain:getRoster', function(source, deptId)
    local state = CC.online[source]
    local dept = CC.depts[deptId]
    if not CC.ready or not state or not dept or state.grades[deptId] == nil then return nil end
    return {
        id = dept.id,
        label = dept.label,
        ranks = dept.rankList,
        divisions = dept.divisions,
        callsignFormat = dept.callsignFormat,
        myGrade = state.grades[deptId],
        myCitizenId = state.citizenid,
        canEditStructure = CC.structureEnabled and (API.IsStructureOwner(source) or CC.hasCap(deptId, state.grades[deptId], 'structure.manage')),
        roster = API.GetRoster(deptId),
    }
end)

---Resolves a target given as an online server id or a citizenid.
function CC.resolveTargetCid(target)
    local id = tonumber(target)
    if id then
        local player = Bridge.getPlayer(id)
        return player and Bridge.getCitizenId(player) or nil
    end
    if type(target) == 'string' and target ~= '' then return target end
end

local function runAction(actor, action, deptId, target, value)
    local cid = CC.resolveTargetCid(target)
    if not cid then return false, 'target_not_found' end
    if action == 'hire' then return API.Hire(actor, cid, tonumber(value), deptId) end
    if action == 'fire' then return API.Fire(actor, cid, deptId) end
    if action == 'promote' then return API.Promote(actor, cid, tonumber(value), deptId) end
    if action == 'demote' then return API.Demote(actor, cid, tonumber(value), deptId) end
    if action == 'callsign' then
        if value == nil or value == '' or value == 'none' then value = nil end
        return API.SetCallsign(actor, cid, value, deptId)
    end
    if action == 'division' or action == 'divisions' then
        local list = {}
        if type(value) == 'table' then
            list = value
        elseif type(value) == 'string' and value ~= 'none' then
            for division in value:gmatch('[^,%s]+') do list[#list + 1] = division end
        end
        return API.SetDivisions(actor, cid, list, deptId)
    end
    return false, 'unknown_action'
end

lib.callback.register('cmd_chain:action', function(source, action, deptId, target, value)
    local ok, err = runAction(source, action, deptId, target, value)
    return ok, not ok and CC.describe(err) or nil
end)

lib.callback.register('cmd_chain:getStructure', function(source, deptId)
    if deptId == nil and API.IsStructureOwner(source) and not (CC.online[source] and next(CC.online[source].grades)) then
        -- Owner outside any department: let them pick one.
        local list = {}
        for _, id in ipairs(CC.deptOrder) do
            if CC.depts[id].enabled then list[#list + 1] = { id = id, label = CC.depts[id].label } end
        end
        return { pick = list }
    end
    local data, err = API.GetStructureEditor(source, deptId)
    if not data then return nil, CC.describe(err) end
    return data
end)

lib.callback.register('cmd_chain:structure', function(source, action, deptId, grade, data)
    local ok, err
    if action == 'set' then
        ok, err = API.SetRank(source, deptId, grade, data)
    elseif action == 'remove' then
        ok, err = API.RemoveRank(source, deptId, grade)
    else
        ok, err = false, 'unknown_action'
    end
    return ok, not ok and CC.describe(err) or nil
end)

-- ───────────────────────────── commands ─────────────────────────────

local function reply(src, ok, msg)
    if src == 0 then
        print(('[cmd_chain] %s'):format(msg))
    else
        TriggerClientEvent('ox_lib:notify', src, { title = 'Chain of Command', description = msg, type = ok and 'success' or 'error' })
    end
end

lib.addCommand('cc', {
    help = 'Chain of Command roster actions',
    params = {
        -- No `type` on the last three: ox_lib's 'string' type rejects numeric args (ids, grades).
        { name = 'action', type = 'string', help = 'hire | fire | promote | demote | callsign | division' },
        { name = 'target', help = 'server id or citizenid' },
        { name = 'value', help = 'grade, callsign, or divisions (comma-separated); "none" clears', optional = true },
        { name = 'dept', help = 'department id (only needed if you are in several)', optional = true },
    },
}, function(source, args)
    local action = args.action:lower()
    local value, dept = args.value, args.dept
    if action == 'fire' and dept == nil then dept, value = value, nil end
    local ok, err = runAction(source, action, dept, args.target, value)
    reply(source, ok, ok and ('Done: %s %s'):format(action, args.target) or CC.describe(err))
end)

-- Console / owner: ccrank <dept> <grade> <payment> <name...>   or   ccrank <dept> <grade> remove
lib.addCommand('ccrank', {
    help = 'Chain of Command: create/update a rank (name and pay), or remove it',
    params = {
        { name = 'dept', help = 'department id' },
        { name = 'grade', type = 'number', help = 'grade number (0-255)' },
        { name = 'payment', help = 'pay per paycheck, or "remove"' },
        { name = 'name', type = 'longString', help = 'rank name', optional = true },
    },
}, function(source, args)
    local ok, err
    if tostring(args.payment):lower() == 'remove' then
        ok, err = API.RemoveRank(source, args.dept, args.grade)
    elseif not tonumber(args.payment) then
        ok, err = false, 'invalid_payment'
    else
        ok, err = API.SetRank(source, args.dept, args.grade, { name = args.name, payment = tonumber(args.payment) })
    end
    reply(source, ok, ok and ('Rank %s saved in %s'):format(args.grade, args.dept) or CC.describe(err))
end)
