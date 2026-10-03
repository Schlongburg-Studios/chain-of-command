-- Roster rules, permissions, callsigns, divisions, offline members, console, rate limit.
-- Runs on every framework / editor combination.
return function(E, T)
    local API, CC, fw, db = E.env.API, E.env.CC, E.fw, E.S.db
    local function lastAudit() return db.audit[#db.audit] end

    T.check('framework detected', E.env.Bridge.name == fw.name)
    T.check('ready', CC.ready)

    -- definition-of-done checks (CLAUDE.md)
    local ok, err = API.Promote(2, 'CADET', 5)
    T.check('Captain cannot promote anyone to Captain', not ok and err == 'rank_ceiling', err)
    ok, err = API.Promote(2, 'CADET', 6)
    T.check('Captain cannot promote to Chief', not ok and err == 'rank_ceiling', err)
    ok, err = API.Hire(3, 'CIV', 0)
    T.check('Cadet cannot hire', not ok and err == 'no_permission', err)
    local offline
    for _, m in ipairs(API.GetRoster('lspd')) do
        if m.citizenid == 'OFF1' then offline = m end
    end
    T.check('offline member appears in roster', offline and offline.online == false and offline.rank == 'Officer', offline and offline.rank)

    -- roster shape
    local roster = API.GetRoster('lspd')
    T.check('roster sorted top-down', roster[1].citizenid == 'CHIEF' and roster[#roster].grade == 0)
    T.check('startup created member rows for job holders', db.members['OFF1:lspd'] ~= nil and db.members['CHIEF:lspd'] ~= nil)

    -- rank ceiling and targeting
    ok, err = API.Fire(2, 'CHIEF')
    T.check('Captain cannot fire Chief', not ok and err == 'target_rank_too_high', err)
    ok, err = API.Promote(1, 'CHIEF', 5)
    T.check('cannot target self', not ok and err == 'cannot_target_self', err)
    ok, err = API.Promote(2, 'CADET', 4)
    T.check('Captain promotes Cadet to Lieutenant', ok and fw.grade('CADET', 'police') == 4, err)
    local a = lastAudit()
    T.check('promotion audited with actor and values', a.action == 'promote' and a.actor == 'CAPT' and a.old == '0' and a.new == '4', a.action)
    local syncRows = 0
    for _, row in ipairs(db.audit) do
        if row.action == 'sync_grade' then syncRows = syncRows + 1 end
    end
    T.check('no duplicate sync audit for our own write', syncRows == 0)
    ok, err = API.Promote(2, 'CADET', 3)
    T.check('promote rejects a lower grade', not ok and err == 'not_a_promotion', err)
    ok, err = API.Demote(2, 'CADET', 3)
    T.check('demote works', ok and fw.grade('CADET', 'police') == 3, err)
    ok, err = API.Demote(2, 'CADET', 3)
    T.check('demote rejects same grade', not ok and err == 'not_a_demotion', err)

    -- permissions
    T.check('Chief inherits everything', API.HasPermission(1, 'reports.view_own') and API.HasPermission(1, 'roster.hire') and API.HasPermission(1, 'roster.set_callsign'))
    T.check('Captain inherits Sergeant caps', API.HasPermission(2, 'reports.approve'))
    T.check('grade 0 lacks reports.write', not CC.hasCap('lspd', 0, 'reports.write') and CC.hasCap('lspd', 0, 'reports.view_own'))
    T.check('civilian has no permissions', not API.HasPermission(4, 'reports.view_own'))
    T.check('HasPermission with unknown dept is false', not API.HasPermission(1, 'roster.hire', 'nope'))

    -- hiring
    ok, err = API.Hire(3, 'CIV', 0)
    T.check('Sergeant cannot hire', not ok and err == 'no_permission', err)
    ok, err = API.Hire(2, 'CIV', 1)
    T.check('Captain hires a civilian', ok and fw.grade('CIV', 'police') == 1 and db.members['CIV:lspd'] ~= nil, err)
    ok, err = API.Hire(2, 'CIV', 1)
    T.check('cannot hire an existing member', not ok and err == 'already_member', err)
    ok, err = API.Hire(2, 'CIV2', 5)
    T.check('cannot hire at own rank', not ok and err == 'rank_ceiling', err)
    ok, err = API.Hire(2, 'CIV2', 9)
    T.check('cannot hire into an unconfigured grade', not ok and err == 'invalid_grade', err)
    ok, err = API.Hire(2, 'NOBODY', 0)
    T.check('unknown target', not ok and err == 'target_not_found', err)

    -- callsigns
    ok, err = API.SetCallsign(2, 'CIV', 'bad')
    T.check('callsign format enforced', not ok and err == 'invalid_callsign', err)
    ok, err = API.SetCallsign(2, 'CIV', '1-A-12')
    T.check('callsign set', ok and db.members['CIV:lspd'].callsign == '1-A-12', err)
    ok, err = API.SetCallsign(2, 'CADET', '1-a-12')
    T.check('callsign unique, case-insensitive', not ok and err == 'callsign_taken', err)
    ok, err = API.SetCallsign(3, 'CIV', '2-B-22')
    T.check('Sergeant sets an Officer callsign', ok, err)
    ok, err = API.SetCallsign(3, 'CAPT', '3-C-33')
    T.check('Sergeant cannot set a Captain callsign', not ok and err == 'target_rank_too_high', err)
    ok, err = API.SetCallsign(2, 'CIV', nil)
    T.check('callsign cleared (no nil hole in SQL params)', ok and db.members['CIV:lspd'].callsign == nil, err)

    -- divisions
    ok, err = API.SetDivisions(2, 'CIV', { 'swat', 'patrol' })
    T.check('divisions stored in config order', ok and db.members['CIV:lspd'].divisions == '["patrol","swat"]', db.members['CIV:lspd'].divisions)
    ok, err = API.SetDivisions(2, 'CIV', { 'navy' })
    T.check('unknown division rejected', not ok and err == 'invalid_division', err)
    ok, err = API.SetDivisions(2, 'CIV', {})
    T.check('divisions cleared to []', ok and db.members['CIV:lspd'].divisions == '[]', db.members['CIV:lspd'].divisions)

    -- offline targets and lookups
    ok, err = API.Promote(2, 'OFF1', 2)
    T.check('promote an offline member', ok and fw.grade('OFF1', 'police') == 2, err)
    local m = API.GetMember('OFF1')
    T.check('GetMember offline by citizenid', m and m.grade == 2 and m.online == false and m.rank == 'Corporal', m and m.rank)
    T.check('GetMember by server id', API.GetMember(1).rank == 'Chief')
    T.check('GetMember for a non-member is nil', API.GetMember(5) == nil)
    local dept = API.GetDepartment('lspd')
    T.check('GetDepartment lists online members and ranks', #dept.members >= 3 and dept.ranks[1].name == 'Chief')

    -- firing
    ok, err = API.Fire(2, 'CIV')
    T.check('Captain fires an Officer', ok and db.members['CIV:lspd'] == nil and fw.grade('CIV', 'police') == nil, err)
    a = lastAudit()
    T.check('fire audited', a.action == 'fire' and a.old == '1')
    ok, err = API.Fire(2, 'CIV')
    T.check('cannot fire a non-member', not ok and err == 'not_a_member', err)

    -- rate limit
    E.S.frozen = true
    local limited = false
    for _ = 1, 7 do
        local _, e = API.SetCallsign(2, 'CADET', nil)
        if e == 'rate_limited' then limited = true end
    end
    T.check('rate limit kicks in', limited)
    E.S.frozen = false
    E.S.clock = E.S.clock + 60000

    -- console
    ok, err = API.Hire(0, 'CIV2', 6, 'lspd')
    T.check('console can bootstrap a Chief', ok and fw.grade('CIV2', 'police') == 6, err)
    a = lastAudit()
    T.check('console audit actor is NULL', a.actor == nil and a.action == 'hire')
    ok, err = API.Hire(0, 'CIV', 0)
    T.check('console must name the department to hire', not ok and err == 'department_required', err)

    -- client-facing paths: identity always comes from the server-side source
    local ok2, msg = E.S.callbacks['cmd_chain:action'](3, 'promote', 'lspd', 'OFF1', 6)
    T.check('client callback cannot escalate', ok2 == false, msg)
    E.S.commands.cc(3, { action = 'hire', target = '4' })
    T.check('Sergeant /cc hire is refused', fw.grade('CIV', 'police') == nil)
    E.S.commands.cc(2, { action = 'hire', target = '4', value = '1' })
    T.check('Captain /cc hire by server id works', fw.grade('CIV', 'police') == 1)
    local lastSync
    for _, e in ipairs(E.S.clientEvents) do
        if e.name == 'cmd_chain:client:sync' and e.src == 2 then lastSync = e.args[1] end
    end
    T.check('client sync carries members and caps', lastSync and lastSync.members.lspd and #lastSync.caps.lspd > 0)
end
