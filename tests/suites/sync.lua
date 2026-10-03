-- Sync with the framework: startup reconcile, external /setjob changes, duty, logout/login.
-- Runs on every framework / editor combination.
return function(E, T, Env, base)
    local API, CC, fw, db = E.env.API, E.env.CC, E.fw, E.S.db

    -- startup reconcile with a stale row (GHOST no longer holds the job)
    local E2 = Env.new({
        root = base.root, framework = base.framework, editable = base.editable,
        db = { members = { ['GHOST:lspd'] = { citizenid = 'GHOST', dept = 'lspd', divisions = '[]', hired_at = 0 } } },
    })
    T.check('startup removes rows for citizens without the job', E2.S.db.members['GHOST:lspd'] == nil)
    local sawFire, sawHire = false, false
    for _, row in ipairs(E2.S.db.audit) do
        if row.action == 'sync_fire' and row.target == 'GHOST' then sawFire = true end
        if row.action == 'sync_hire' and row.target == 'OFF1' then sawHire = true end
    end
    T.check('startup audits sync_fire for stale rows', sawFire)
    T.check('startup audits sync_hire for job holders without rows', sawHire)

    -- events
    local updates, duty = {}, {}
    E.env.AddEventHandler('cmd_chain:memberUpdated', function(cid, member, dept) updates[#updates + 1] = { cid = cid, member = member, dept = dept } end)
    E.env.AddEventHandler('cmd_chain:dutyChanged', function(cid, onDuty, dept) duty[#duty + 1] = { cid = cid, onDuty = onDuty, dept = dept } end)

    -- external /setjob
    local before = #db.audit
    fw.externalSetJob('CIV', 'police', 2)
    T.check('external hire creates a member row', db.members['CIV:lspd'] ~= nil)
    local found = false
    for i = before + 1, #db.audit do
        if db.audit[i].action == 'sync_hire' and db.audit[i].actor == nil and db.audit[i].target == 'CIV' then found = true end
    end
    T.check('external hire audited as sync_hire with NULL actor', found)
    T.check('external hire emits memberUpdated', updates[#updates] and updates[#updates].cid == 'CIV' and updates[#updates].member.grade == 2)

    fw.externalSetJob('CIV', 'police', 3)
    T.check('external grade change audited as sync_grade', db.audit[#db.audit].action == 'sync_grade' and db.audit[#db.audit].old == '2' and db.audit[#db.audit].new == '3')

    fw.externalRemoveJob('CIV', 'police')
    T.check('external removal deletes the row', db.members['CIV:lspd'] == nil and db.audit[#db.audit].action == 'sync_fire')
    T.check('external removal emits memberUpdated with nil member', updates[#updates].cid == 'CIV' and updates[#updates].member == nil and updates[#updates].dept == 'lspd')

    -- duty
    duty = {}
    fw.setDuty('CHIEF', false)
    T.check('going off duty emits dutyChanged(false)', #duty == 1 and duty[1].cid == 'CHIEF' and duty[1].onDuty == false)
    fw.setDuty('CHIEF', true)
    T.check('going on duty emits dutyChanged(true)', #duty == 2 and duty[2].onDuty == true)
    T.check('roster reflects duty', API.GetMember(1).onDuty == true)

    -- API writes emit memberUpdated exactly once
    updates = {}
    API.SetCallsign(1, 'CAPT', '1-K-01')
    T.check('memberUpdated fires once with the new callsign', #updates == 1 and updates[1].member.callsign == '1-K-01')

    -- logout / login
    duty = {}
    fw.logout(2)
    T.check('logout while on duty emits dutyChanged(false)', #duty == 1 and duty[1].cid == 'CAPT' and duty[1].onDuty == false)
    T.check('HasPermission is false once logged out', not API.HasPermission(2, 'roster.fire'))
    local capt
    for _, m in ipairs(API.GetRoster('lspd')) do
        if m.citizenid == 'CAPT' then capt = m end
    end
    T.check('logged-out member stays in the roster as offline', capt and capt.online == false)
    fw.login(2, 'CAPT')
    T.check('login restores permissions', API.HasPermission(2, 'roster.fire'))
    T.check('player is not resynced as a new hire on login', db.audit[#db.audit].target ~= 'CAPT' or db.audit[#db.audit].action ~= 'sync_hire')
end
