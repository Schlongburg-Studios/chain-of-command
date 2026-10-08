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

    -- Qbox fires several job events for one /setjob. While the first handler waits on the database,
    -- the second one runs. It must not "hire" the same citizen again (duplicate audit row, duplicate event).
    do
        local before2, updatesBefore = #db.audit, #updates
        db.members['CIV2:lspd'] = nil
        E.S.duringMemberWrite = function() CC.refreshPlayer(5) end -- CIV2 is src 5
        fw.externalSetJob('CIV2', 'police', 1)
        local hires = 0
        for i = before2 + 1, #db.audit do
            if db.audit[i].action == 'sync_hire' and db.audit[i].target == 'CIV2' then hires = hires + 1 end
        end
        T.check('overlapping job events write ONE sync_hire audit row', hires == 1, hires)
        local events = 0
        for i = updatesBefore + 1, #updates do
            if updates[i].cid == 'CIV2' then events = events + 1 end
        end
        T.check('overlapping job events emit ONE memberUpdated', events == 1, events)
        T.check('and the member row exists exactly once', db.members['CIV2:lspd'] ~= nil)

        -- the same for removal
        local before3 = #db.audit
        E.S.duringMemberDelete = function() CC.refreshPlayer(5) end
        fw.externalRemoveJob('CIV2', 'police')
        E.S.flushTimers()
        local fires = 0
        for i = before3 + 1, #db.audit do
            if db.audit[i].action == 'sync_fire' and db.audit[i].target == 'CIV2' then fires = fires + 1 end
        end
        T.check('overlapping job events write ONE sync_fire audit row', fires == 1, fires)
        T.check('removed member row is gone', db.members['CIV2:lspd'] == nil)
    end

    -- /setjob on someone who already holds the job. qbx_core removes the old job, then adds the new
    -- one (two events); that is ONE promotion, not a fire and a hire: callsign and divisions stay.
    do
        db.members['CIV2:lspd'] = nil
        fw.externalSetJob('CIV2', 'police', 1)
        API.SetCallsign(0, 'CIV2', '1-A-33', 'lspd')
        API.SetDivisions(0, 'CIV2', { 'swat' }, 'lspd')
        local hired = db.members['CIV2:lspd'].hired_at
        local row = CC.rows.lspd.CIV2
        local a, u = #db.audit, #updates
        fw.externalSetJobReplacing('CIV2', 'police', 3)
        E.S.flushTimers()
        local actions = {}
        for i = a + 1, #db.audit do actions[#actions + 1] = db.audit[i].action end
        T.check('replacing /setjob (promotion) is audited as ONE sync_grade', #actions == 1 and actions[1] == 'sync_grade'
            and db.audit[#db.audit].old == '1' and db.audit[#db.audit].new == '3', table.concat(actions, ','))
        T.check('replacing /setjob keeps the callsign', CC.rows.lspd.CIV2 and CC.rows.lspd.CIV2.callsign == '1-A-33')
        T.check('replacing /setjob keeps the divisions', CC.rows.lspd.CIV2 and CC.rows.lspd.CIV2.divisions[1] == 'swat')
        T.check('replacing /setjob keeps the member row (hire date unchanged)', db.members['CIV2:lspd'] and db.members['CIV2:lspd'].hired_at == hired)
        local events = {}
        for i = u + 1, #updates do
            if updates[i].cid == 'CIV2' then events[#events + 1] = updates[i] end
        end
        T.check('replacing /setjob emits ONE memberUpdated with the new rank', #events == 1 and events[1].member and events[1].member.grade == 3, #events)
        T.check('nothing is left pending', next(CC.pendingFire) == nil)

        -- same grade again: nothing changed, nothing to audit
        a = #db.audit
        fw.externalSetJobReplacing('CIV2', 'police', 3)
        E.S.flushTimers()
        T.check('replacing /setjob with the same grade writes no audit row', #db.audit == a)
        T.check('...and keeps the member', CC.rows.lspd.CIV2 ~= nil)

        -- demotion the same way
        fw.externalSetJobReplacing('CIV2', 'police', 2)
        E.S.flushTimers()
        T.check('replacing /setjob (demotion) is one sync_grade', db.audit[#db.audit].action == 'sync_grade' and db.audit[#db.audit].old == '3' and db.audit[#db.audit].new == '2')

        -- a real removal is still a fire, once the window has passed
        a = #db.audit
        fw.externalSetJobReplacing('CIV2', 'unemployed', 0)
        T.check('a removal is not applied yet...', CC.rows.lspd.CIV2 ~= nil and #db.audit == a)
        E.S.flushTimers()
        T.check('...until the window passes: then sync_fire', CC.rows.lspd.CIV2 == nil and db.audit[#db.audit].action == 'sync_fire' and db.audit[#db.audit].old == '2')

        -- the player disconnects inside the window: still a fire
        fw.externalSetJob('CIV2', 'police', 1)
        a = #db.audit
        fw.externalRemoveJob('CIV2', 'police')
        fw.logout(5)
        E.S.flushTimers()
        T.check('a removal followed by a disconnect is still a fire', CC.rows.lspd.CIV2 == nil and db.audit[#db.audit].action == 'sync_fire')
        fw.login(5, 'CIV2')
        E.S.flushTimers()
    end

    fw.externalSetJob('CIV', 'police', 3)
    T.check('external grade change audited as sync_grade', db.audit[#db.audit].action == 'sync_grade' and db.audit[#db.audit].old == '2' and db.audit[#db.audit].new == '3')

    fw.externalRemoveJob('CIV', 'police')
    T.check('a removal waits briefly (it may be the first half of a /setjob)', db.members['CIV:lspd'] ~= nil)
    E.S.flushTimers()
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
