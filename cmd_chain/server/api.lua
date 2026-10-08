-- Public server API (SPEC section 4). This is a contract: never rename or remove
-- anything without a major version bump. Every write: resolve the actor from the
-- framework -> permission check -> rank-ceiling check -> rate limit -> write -> audit.

API = {}

-- ───────────────────────────── helpers ─────────────────────────────

local function getDept(deptId)
    local dept = CC.depts[deptId]
    if not dept then return nil, 'unknown_department' end
    if not dept.enabled then return nil, 'department_disabled' end
    return dept
end

---actorSrc 0 is the server console: trusted, skips permission and rank checks.
local function resolveActor(actorSrc)
    actorSrc = tonumber(actorSrc)
    if actorSrc == 0 then return { console = true } end
    if not actorSrc then return nil, 'actor_not_found' end
    local player = Bridge.getPlayer(actorSrc)
    if not player then return nil, 'actor_not_found' end
    return { src = actorSrc, player = player, citizenid = Bridge.getCitizenId(player) }
end

---Picks the department: explicit id, else the actor's primary-job department, else the
---first department the actor belongs to. The console must name it unless the target
---belongs to exactly one department.
local function resolveDept(actor, deptId, targetCid)
    if deptId then return getDept(deptId) end
    if actor.console then
        local found
        for _, id in ipairs(CC.deptOrder) do
            if CC.rows[id][targetCid] then
                if found then return nil, 'department_required' end
                found = id
            end
        end
        if not found then return nil, 'department_required' end
        return getDept(found)
    end
    local primary = CC.jobToDept[(Bridge.getJob(actor.player))]
    if primary and CC.depts[primary].enabled then return CC.depts[primary] end
    for _, id in ipairs(CC.deptOrder) do
        local dept = CC.depts[id]
        if dept.enabled and Bridge.getJobGrade(actor.player, dept.job) ~= nil then return dept end
    end
    return nil, 'not_in_department'
end

---Shared checks for every roster write. Identity and rank come from the framework only.
local function prepare(actorSrc, deptId, targetCid, cap)
    if not CC.ready then return nil, 'not_ready' end
    if type(targetCid) ~= 'string' or targetCid == '' then return nil, 'invalid_target' end

    local actor, err = resolveActor(actorSrc)
    if not actor then return nil, err end
    if not actor.console and CC.rateLimited(actor.src) then return nil, 'rate_limited' end

    local dept
    dept, err = resolveDept(actor, deptId, targetCid)
    if not dept then return nil, err end

    local target = Bridge.getPlayerByCitizenId(targetCid, true)
    if not target then return nil, 'target_not_found' end

    local ctx = {
        actor = actor,
        dept = dept,
        targetCid = targetCid,
        target = target,
        targetGrade = Bridge.getJobGrade(target, dept.job),
    }

    if not actor.console then
        actor.grade = Bridge.getJobGrade(actor.player, dept.job)
        if actor.grade == nil then return nil, 'not_in_department' end
        if not CC.hasCap(dept.id, actor.grade, cap) then return nil, 'no_permission' end
        if actor.citizenid == targetCid then return nil, 'cannot_target_self' end
        -- Actors can only change members strictly below their own rank.
        if ctx.targetGrade ~= nil and ctx.targetGrade >= actor.grade then return nil, 'target_rank_too_high' end
    end
    return ctx
end

---A new grade must be a configured rank, exist in the framework job, and sit strictly
---below the actor's own grade.
local function checkNewGrade(ctx, grade)
    local n = tonumber(grade)
    grade = n and math.tointeger(n)
    if not grade or not ctx.dept.ranks[grade] then return nil, 'invalid_grade' end
    local frameworkGrades = Bridge.getJobGrades(ctx.dept.job)
    if not frameworkGrades or not frameworkGrades[grade] then return nil, 'grade_missing_in_framework' end
    -- A grade that is only in memory would vanish (with its holders) at the next restart.
    if CC.jobsFileBroken and Bridge.gradeOnDisk and not Bridge.gradeOnDisk(ctx.dept.job, grade) then
        return nil, 'jobs_file_unwritable'
    end
    if not ctx.actor.console and grade >= ctx.actor.grade then return nil, 'rank_ceiling' end
    return grade
end

---Runs a framework write with sync-audit suppressed (the API writes its own audit row).
local function frameworkWrite(ctx, fn)
    local key = ctx.targetCid .. ':' .. ctx.dept.id
    CC.suppress[key] = true
    local ok, res, err = pcall(fn)
    if ok and res then CC.syncCitizen(ctx.targetCid) end
    CC.suppress[key] = nil
    if not ok then
        print(('^1[cmd_chain] framework write failed: %s^0'):format(res))
        return false, 'internal_error'
    end
    return res, err
end

---Emits memberUpdated after a write. grade nil = left the department.
local function emitAfter(ctx, grade)
    local cid, deptId = ctx.targetCid, ctx.dept.id
    if grade == nil then
        CC.emitMember(cid, deptId, nil)
        return
    end
    local member = CC.srcByCid[cid] and CC.memberOf(cid, deptId)
        or CC.buildMember(deptId, cid, grade, false, Bridge.getName(ctx.target), false)
    CC.emitMember(cid, deptId, member)
end

local function actorCid(ctx)
    return ctx.actor.citizenid -- nil for the console
end

-- ───────────────────────────── reads ─────────────────────────────

---@param id integer|string server id (number) or citizenid (string)
---@param deptId string? optional; defaults to the primary-job department, then the first one held
---@return table? member { citizenid, name, dept, deptLabel, rank, grade, callsign, divisions, onDuty, online, hiredAt }
function API.GetMember(id, deptId)
    if not CC.ready then return nil end
    local player
    if type(id) == 'number' then
        player = Bridge.getPlayer(id)
    elseif type(id) == 'string' and id ~= '' then
        player = Bridge.getPlayerByCitizenId(id, true)
    end
    if not player then return nil end

    if deptId then
        local dept = CC.depts[deptId]
        if not dept or not dept.enabled or Bridge.getJobGrade(player, dept.job) == nil then return nil end
    else
        local primary = CC.jobToDept[(Bridge.getJob(player))]
        if primary and CC.depts[primary].enabled then
            deptId = primary
        else
            for _, idx in ipairs(CC.deptOrder) do
                local dept = CC.depts[idx]
                if dept.enabled and Bridge.getJobGrade(player, dept.job) ~= nil then
                    deptId = idx
                    break
                end
            end
        end
        if not deptId then return nil end
    end

    local dept = CC.depts[deptId]
    return CC.buildMember(deptId, Bridge.getCitizenId(player), Bridge.getJobGrade(player, dept.job),
        Bridge.isOnDuty(player, dept.job), Bridge.getName(player), Bridge.getSource(player) ~= nil)
end

---@param src integer
---@param cap string
---@param deptId string? optional; without it, true if any of the player's departments grants cap
---@return boolean
function API.HasPermission(src, cap, deptId)
    src = tonumber(src)
    if not CC.ready or not src or type(cap) ~= 'string' then return false end
    if not CC.online[src] then CC.refreshPlayer(src) end
    local state = CC.online[src]
    if not state then return false end
    if deptId then
        return state.grades[deptId] ~= nil and CC.hasCap(deptId, state.grades[deptId], cap)
    end
    for id, grade in pairs(state.grades) do
        if CC.hasCap(id, grade, cap) then return true end
    end
    return false
end

---@return table? { id, label, job, callsignFormat, callsignExample, divisions, ranks = { { grade, name, caps } }, members = online members }
---callsignFormat is the validation pattern, for scripts only; show players callsignExample instead.
function API.GetDepartment(deptId)
    local dept = CC.depts[deptId]
    if not dept then return nil end
    local ranks = {}
    for i, rank in ipairs(dept.rankList) do
        local def = dept.ranks[rank.grade]
        ranks[i] = {
            grade = rank.grade,
            name = rank.name,
            caps = CC.capList(deptId, rank.grade), -- effective (inherited) capabilities
            ownCaps = def.ownCaps,                 -- v1.1: capabilities set on this rank itself
            payment = def.payment,                 -- v1.1: nil unless the rank editor is on
        }
    end
    local members = {}
    for _, state in pairs(CC.online) do
        local grade = state.grades[deptId]
        if grade ~= nil then
            members[#members + 1] = CC.buildMember(deptId, state.citizenid, grade, state.duty[deptId], state.name, true)
        end
    end
    table.sort(members, function(a, b) return a.grade > b.grade end)
    return {
        id = dept.id,
        label = dept.label,
        job = dept.job,
        enabled = dept.enabled == true,
        callsignFormat = dept.callsignFormat,
        callsignExample = dept.callsignExample, -- v1.1: player-facing example, e.g. '1-A-12'
        divisions = dept.divisions,
        ranks = ranks,
        members = members,
    }
end

---All members, online and offline, highest rank first.
---@return table[]? members
function API.GetRoster(deptId)
    local dept = CC.depts[deptId]
    if not CC.ready or not dept or not dept.enabled then return nil end
    local list = {}
    for _, holder in ipairs(Bridge.getJobMembers(dept.job)) do
        local src = CC.srcByCid[holder.citizenid]
        local state = src and CC.online[src]
        local onDuty = state and state.duty[deptId] or false
        list[#list + 1] = CC.buildMember(deptId, holder.citizenid, holder.grade, onDuty, holder.name, state ~= nil)
    end
    table.sort(list, function(a, b)
        if a.grade ~= b.grade then return a.grade > b.grade end
        return a.name < b.name
    end)
    return list
end

---Newest first. Server-side only.
function API.GetAuditLog(deptId, limit, targetCid)
    if not CC.depts[deptId] then return {} end
    return Audit.get(deptId, limit, targetCid)
end

-- ───────────────────────────── writes ─────────────────────────────

---@return boolean ok, string? err
function API.Hire(actorSrc, targetCid, grade, deptId)
    local ctx, err = prepare(actorSrc, deptId, targetCid, 'roster.hire')
    if not ctx then return false, err end
    if ctx.targetGrade ~= nil then return false, 'already_member' end

    local newGrade
    newGrade, err = checkNewGrade(ctx, grade == nil and ctx.dept.lowest or grade)
    if not newGrade then return false, err end

    local ok
    ok, err = frameworkWrite(ctx, function() return Bridge.setJob(targetCid, ctx.dept.job, newGrade) end)
    if not ok then return false, err end

    CC.ensureRow(ctx.dept.id, targetCid)
    Audit.log(ctx.dept.id, actorCid(ctx), targetCid, 'hire', nil, newGrade)
    emitAfter(ctx, newGrade)
    return true
end

---@return boolean ok, string? err
function API.Fire(actorSrc, targetCid, deptId)
    local ctx, err = prepare(actorSrc, deptId, targetCid, 'roster.fire')
    if not ctx then return false, err end
    if ctx.targetGrade == nil then return false, 'not_a_member' end

    local ok
    ok, err = frameworkWrite(ctx, function() return Bridge.removeJob(targetCid, ctx.dept.job) end)
    if not ok then return false, err end

    CC.deleteRow(ctx.dept.id, targetCid)
    Audit.log(ctx.dept.id, actorCid(ctx), targetCid, 'fire', ctx.targetGrade, nil)
    emitAfter(ctx, nil)
    return true
end

local function changeGrade(direction, actorSrc, targetCid, newGrade, deptId)
    local ctx, err = prepare(actorSrc, deptId, targetCid, 'roster.promote')
    if not ctx then return false, err end
    if ctx.targetGrade == nil then return false, 'not_a_member' end

    local grade
    grade, err = checkNewGrade(ctx, newGrade)
    if not grade then return false, err end
    if direction == 'promote' and grade <= ctx.targetGrade then return false, 'not_a_promotion' end
    if direction == 'demote' and grade >= ctx.targetGrade then return false, 'not_a_demotion' end

    local ok
    ok, err = frameworkWrite(ctx, function() return Bridge.setJob(targetCid, ctx.dept.job, grade) end)
    if not ok then return false, err end

    CC.ensureRow(ctx.dept.id, targetCid)
    Audit.log(ctx.dept.id, actorCid(ctx), targetCid, direction, ctx.targetGrade, grade)
    emitAfter(ctx, grade)
    return true
end

---@return boolean ok, string? err
function API.Promote(actorSrc, targetCid, newGrade, deptId)
    return changeGrade('promote', actorSrc, targetCid, newGrade, deptId)
end

---@return boolean ok, string? err
function API.Demote(actorSrc, targetCid, newGrade, deptId)
    return changeGrade('demote', actorSrc, targetCid, newGrade, deptId)
end

---callsign nil or '' clears it.
---On 'invalid_callsign' a third value names the department, so callers can show its example.
---@return boolean ok, string? err, string? deptId
function API.SetCallsign(actorSrc, targetCid, callsign, deptId)
    local ctx, err = prepare(actorSrc, deptId, targetCid, 'roster.set_callsign')
    if not ctx then return false, err end
    if ctx.targetGrade == nil then return false, 'not_a_member' end

    if callsign ~= nil then
        if type(callsign) ~= 'string' then return false, 'invalid_callsign', ctx.dept.id end
        callsign = callsign:match('^%s*(.-)%s*$')
        if callsign == '' then callsign = nil end
    end

    local id = ctx.dept.id
    if callsign then
        if #callsign > 16 then return false, 'invalid_callsign', id end
        if ctx.dept.callsignFormat and not callsign:match(ctx.dept.callsignFormat) then return false, 'invalid_callsign', id end
        local wanted = callsign:upper()
        for cid, row in pairs(CC.rows[id]) do
            if cid ~= targetCid and row.callsign and row.callsign:upper() == wanted then
                return false, 'callsign_taken'
            end
        end
    end

    local row = CC.ensureRow(id, targetCid)
    local old = row.callsign
    if old == callsign then return true end

    -- No nil inside parameter arrays: a nil hole can shift oxmysql parameters.
    if callsign then
        MySQL.update.await('UPDATE cmd_chain_members SET callsign = ? WHERE citizenid = ? AND dept = ?', { callsign, targetCid, id })
    else
        MySQL.update.await('UPDATE cmd_chain_members SET callsign = NULL WHERE citizenid = ? AND dept = ?', { targetCid, id })
    end
    row.callsign = callsign
    Audit.log(id, actorCid(ctx), targetCid, 'set_callsign', old, callsign)
    emitAfter(ctx, ctx.targetGrade)
    return true
end

---divisions: array of division ids from the department config. Empty array clears.
---@return boolean ok, string? err
function API.SetDivisions(actorSrc, targetCid, divisions, deptId)
    local ctx, err = prepare(actorSrc, deptId, targetCid, 'roster.set_division')
    if not ctx then return false, err end
    if ctx.targetGrade == nil then return false, 'not_a_member' end
    if type(divisions) ~= 'table' then return false, 'invalid_division' end

    local wanted = {}
    for _, division in pairs(divisions) do
        if type(division) ~= 'string' or not ctx.dept.divisionSet[division:lower()] then return false, 'invalid_division' end
        wanted[division:lower()] = true
    end
    local list = {}
    for _, division in ipairs(ctx.dept.divisions) do
        if wanted[division] then list[#list + 1] = division end
    end

    local row = CC.ensureRow(ctx.dept.id, targetCid)
    local old = row.divisions
    if table.concat(old, ',') == table.concat(list, ',') then return true end

    -- Encode empty lists explicitly: json.encode({}) yields '{}', not '[]'.
    local encoded = #list == 0 and '[]' or json.encode(list)
    MySQL.update.await('UPDATE cmd_chain_members SET divisions = ? WHERE citizenid = ? AND dept = ?', { encoded, targetCid, ctx.dept.id })
    row.divisions = list
    Audit.log(ctx.dept.id, actorCid(ctx), targetCid, 'set_divisions', old, list)
    emitAfter(ctx, ctx.targetGrade)
    return true
end

-- ───────────────────────────── rank structure (v1.1) ─────────────────────────────
-- Editors: the console, anyone with ACE `cmd_chain.structure` (owners: every rank), or a
-- member whose rank has 'structure.manage' (only ranks strictly below their own, only
-- capabilities they hold, and never in a way that changes their own or higher ranks).

local MAX_GRADE = 255 -- Qbox stores grades as TINYINT UNSIGNED

---@return boolean
function API.IsStructureOwner(src)
    src = tonumber(src)
    if src == 0 then return true end
    return src ~= nil and IsPlayerAceAllowed(tostring(src), 'cmd_chain.structure')
end

local function prepareStructure(actorSrc, deptId)
    if not CC.ready then return nil, 'not_ready' end
    if not CC.structureEnabled then return nil, 'structure_locked' end
    if CC.jobsFileBroken then return nil, 'jobs_file_unwritable' end
    actorSrc = tonumber(actorSrc)
    if not actorSrc then return nil, 'actor_not_found' end

    local actor = { src = actorSrc, owner = API.IsStructureOwner(actorSrc), console = actorSrc == 0 }
    if not actor.console then
        actor.player = Bridge.getPlayer(actorSrc)
        if not actor.player then return nil, 'actor_not_found' end
        actor.citizenid = Bridge.getCitizenId(actor.player)
        if CC.rateLimited(actorSrc) then return nil, 'rate_limited' end
    end

    local dept, err
    if deptId then
        dept, err = getDept(deptId)
    elseif actor.console then
        err = 'department_required'
    else
        dept, err = resolveDept(actor, nil, nil)
        if not dept and actor.owner then err = 'department_required' end
    end
    if not dept then return nil, err end

    if not actor.owner then
        actor.grade = Bridge.getJobGrade(actor.player, dept.job)
        if actor.grade == nil then return nil, 'not_in_department' end
        if not CC.hasCap(dept.id, actor.grade, 'structure.manage') then return nil, 'no_permission' end
    end
    return { actor = actor, dept = dept }
end

local function parseGrade(grade)
    local n = tonumber(grade)
    n = n and math.tointeger(n)
    if not n or n < 0 or n > MAX_GRADE then return nil end
    return n
end

---Validates (partial) rank data, filling gaps from the existing rank.
local function normalizeRank(grade, data, existing)
    if type(data) ~= 'table' then return nil, 'invalid_rank' end

    local name = existing and existing.name
    if data.name ~= nil then
        if type(data.name) ~= 'string' then return nil, 'invalid_rank_name' end
        name = data.name:match('^%s*(.-)%s*$')
    end
    if not name or #name < 1 or #name > 50 then return nil, 'invalid_rank_name' end

    local payment = existing and existing.payment or 0
    if data.payment ~= nil then
        local n = tonumber(data.payment)
        payment = n and math.tointeger(n)
        if not payment or payment < 0 or payment > (Config.Structure.maxPayment or 100000) then return nil, 'invalid_payment' end
    end

    local caps = existing and existing.ownCaps or {}
    if data.caps ~= nil then
        if type(data.caps) ~= 'table' then return nil, 'invalid_capability' end
        local seen, list = {}, {}
        for _, cap in pairs(data.caps) do
            if type(cap) ~= 'string' or #cap > 64 or not cap:match('^[%w_%.%-]+$') then return nil, 'invalid_capability' end
            if not seen[cap] then
                seen[cap] = true
                list[#list + 1] = cap
            end
        end
        if #list > 50 then return nil, 'invalid_capability' end
        table.sort(list)
        caps = list
    end

    local copyCaps = {}
    for i, cap in ipairs(caps) do copyCaps[i] = cap end
    return { grade = grade, name = name, payment = payment, caps = copyCaps }
end

local function sameSet(a, b)
    for k in pairs(a) do if not b[k] then return false end end
    for k in pairs(b) do if not a[k] then return false end end
    return true
end

---Non-owners may only change ranks strictly below their own, and only in ways that leave
---the effective permissions of their own rank and every rank above it untouched.
local function checkScope(ctx, grade, newRecords)
    if ctx.actor.owner then return true end
    if grade >= ctx.actor.grade then return nil, 'target_rank_too_high' end

    local after, err = CC.compileRanks(newRecords)
    if not after then return nil, err end
    local before = ctx.dept.ranks

    local grades = { [ctx.actor.grade] = true }
    for g in pairs(before) do grades[g] = true end
    for g in pairs(after) do grades[g] = true end
    for g in pairs(grades) do
        if g >= ctx.actor.grade then
            local a, b = CC.effectiveRank(before, g), CC.effectiveRank(after, g)
            if (a == nil) ~= (b == nil) or (a and not sameSet(a.caps, b.caps)) then
                return nil, 'affects_higher_ranks'
            end
        end
    end
    return true
end

local function recordsWith(deptId, record, removeGrade)
    local list = {}
    for _, existing in ipairs(CC.rankRecords(deptId)) do
        if existing.grade ~= removeGrade and (not record or existing.grade ~= record.grade) then
            list[#list + 1] = existing
        end
    end
    if record then list[#list + 1] = record end
    return list
end

---Creates or updates a rank. data = { name?, payment?, caps? } (name required for new ranks).
---@return boolean ok, string? err
function API.SetRank(actorSrc, deptId, grade, data)
    local ctx, err = prepareStructure(actorSrc, deptId)
    if not ctx then return false, err end
    grade = parseGrade(grade)
    if not grade then return false, 'invalid_grade' end

    local dept = ctx.dept
    local existing = dept.ranks[grade]
    local record
    record, err = normalizeRank(grade, data, existing)
    if not record then return false, err end

    -- Only grant capabilities you hold yourself.
    if not ctx.actor.owner then
        local had = {}
        for _, cap in ipairs(existing and existing.ownCaps or {}) do had[cap] = true end
        for _, cap in ipairs(record.caps) do
            if not had[cap] and not CC.hasCap(dept.id, ctx.actor.grade, cap) then return false, 'cannot_grant_capability' end
        end
    end

    local newRecords = recordsWith(dept.id, record)
    local ok
    ok, err = checkScope(ctx, grade, newRecords)
    if not ok then return false, err end

    ok, err = Bridge.upsertJobGrade(dept.job, grade, { name = record.name, payment = record.payment })
    if not ok then return false, err end

    CC.saveRank(dept.id, record)
    local old = existing and { grade = grade, name = existing.name, payment = existing.payment, caps = existing.ownCaps } or nil
    CC.applyRanks(dept.id, newRecords)
    Audit.log(dept.id, ctx.actor.citizenid, nil, existing and 'rank_update' or 'rank_create', old, record)
    CC.afterStructureChange(dept.id)
    return true
end

---Deletes a rank. Refused while anyone (online or offline) holds that grade.
---@return boolean ok, string? err
function API.RemoveRank(actorSrc, deptId, grade)
    local ctx, err = prepareStructure(actorSrc, deptId)
    if not ctx then return false, err end
    grade = parseGrade(grade)
    if not grade then return false, 'invalid_grade' end

    local dept = ctx.dept
    local existing = dept.ranks[grade]
    if not existing then return false, 'unknown_rank' end
    if #dept.rankList <= 1 then return false, 'last_rank' end

    local newRecords = recordsWith(dept.id, nil, grade)
    local ok
    ok, err = checkScope(ctx, grade, newRecords)
    if not ok then return false, err end

    for _, holder in ipairs(Bridge.getJobMembers(dept.job)) do
        if holder.grade == grade then return false, 'rank_in_use' end
    end

    ok, err = Bridge.removeJobGrade(dept.job, grade)
    if not ok then return false, err end

    CC.deleteRank(dept.id, grade)
    CC.applyRanks(dept.id, newRecords)
    Audit.log(dept.id, ctx.actor.citizenid, nil, 'rank_remove',
        { grade = grade, name = existing.name, payment = existing.payment, caps = existing.ownCaps }, nil)
    CC.afterStructureChange(dept.id)
    return true
end

---Data for the in-game editor. nil, err when the player may not edit this department.
function API.GetStructureEditor(src, deptId)
    local ctx, err = prepareStructure(src, deptId)
    if not ctx then return nil, err end
    local dept = ctx.dept

    local holders = {}
    for _, holder in ipairs(Bridge.getJobMembers(dept.job)) do
        holders[holder.grade] = (holders[holder.grade] or 0) + 1
    end

    local known, ranks = {}, {}
    for _, cap in ipairs({ 'roster.manage_all', 'roster.hire', 'roster.fire', 'roster.promote', 'roster.set_division', 'roster.set_callsign', 'structure.manage' }) do
        known[cap] = true
    end
    for _, record in ipairs(CC.rankRecords(dept.id)) do
        for _, cap in ipairs(record.caps) do known[cap] = true end
        record.holders = holders[record.grade] or 0
        record.editable = ctx.actor.owner or record.grade < ctx.actor.grade
        ranks[#ranks + 1] = record
    end

    local knownList = {}
    for cap in pairs(known) do knownList[#knownList + 1] = cap end
    table.sort(knownList)

    return {
        id = dept.id,
        label = dept.label,
        framework = Bridge.name,
        savedToJobsFile = Bridge.name == 'qbx' and Config.Structure.writeQbxJobsFile == true,
        owner = ctx.actor.owner,
        myGrade = ctx.actor.grade,
        myCaps = ctx.actor.owner and knownList or CC.capList(dept.id, ctx.actor.grade),
        knownCaps = knownList,
        maxGrade = ctx.actor.owner and MAX_GRADE or (ctx.actor.grade - 1),
        maxPayment = Config.Structure.maxPayment or 100000,
        ranks = ranks,
    }
end

-- ───────────────────────────── exports ─────────────────────────────

exports('GetMember', API.GetMember)
exports('HasPermission', API.HasPermission)
exports('GetDepartment', API.GetDepartment)
exports('GetRoster', API.GetRoster)
exports('GetAuditLog', API.GetAuditLog)
exports('Hire', API.Hire)
exports('Fire', API.Fire)
exports('Promote', API.Promote)
exports('Demote', API.Demote)
exports('SetCallsign', API.SetCallsign)
exports('SetDivisions', API.SetDivisions)
exports('SetRank', API.SetRank)
exports('RemoveRank', API.RemoveRank)
