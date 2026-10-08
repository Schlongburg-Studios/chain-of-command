-- v1.1 rank structure editor. Runs with Config.Structure.editable = true on both frameworks.
return function(E, T, Env, base)
    local API, CC, fw, S = E.env.API, E.env.CC, E.fw, E.S
    local db = S.db
    local json = E.env.json
    local function lastAudit() return db.audit[#db.audit] end
    local function rankRows()
        local n = 0
        for k in pairs(db.ranks) do if k:find('^lspd:') then n = n + 1 end end
        return n
    end

    -- first start
    T.check('structure seeded from config into the database', rankRows() == 7)
    local g6, g0, g4 = fw.gradeData('police', 6), fw.gradeData('police', 0), fw.gradeData('police', 4)
    T.check('missing grades created with config pay', g6 and g6.name == 'Chief' and g6.payment == 200)
    T.check('existing grades renamed, framework pay kept', g0 and g0.name == 'Cadet' and g0.payment == 50)
    T.check('other grade fields kept (pay)', g4 and g4.name == 'Lieutenant' and g4.payment == 150)
    T.check('config boss flags applied (Chief is boss, Lieutenant no longer)', g6.isboss == true and g4.isboss == nil)
    T.check('boot cache written', S.files['cmd_chain/structure.cache.json'] ~= nil)
    T.check('no missing-grade problems after seeding', (function()
        for grade in pairs(CC.depts.lspd.ranks) do
            if not fw.gradeData('police', grade) then return false end
        end
        return true
    end)())

    if fw.name == 'qbx' then
        local file = fw.jobsFile()
        T.check('qbx: jobs.lua written and valid Lua', file ~= nil)
        T.check('qbx: jobs.lua keeps every job type', file and file.police.type == 'leo' and file.mechanic.type == 'mechanic')
        T.check('qbx: jobs.lua has the new grades', file and file.police.grades[6].name == 'Chief' and file.police.grades[6].bankAuth == true and file.police.grades[4].bankAuth == nil and file.police.grades[4].isboss == nil)
        T.check('qbx: original jobs.lua backed up', S.files['qbx_core/shared/jobs.lua.cmd_chain-original.bak'] == S.originalJobs)
    else
        local touched = false
        for path in pairs(S.files) do
            if path:find('^qb%-core/') then touched = true end
        end
        T.check('qb: qb-core files never written', not touched)
    end

    -- Chief (structure.manage via roster.manage_all)
    local ok, err
    T.check('Chief has structure.manage via manage_all', CC.hasCap('lspd', 6, 'structure.manage'))
    ok, err = API.SetRank(1, 'lspd', 7, { name = 'Commissioner', payment = 300 })
    T.check('Chief cannot add a rank above own', not ok and err == 'target_rank_too_high', err)
    ok, err = API.SetRank(1, 'lspd', 6, { name = 'Big Chief' })
    T.check('Chief cannot edit own rank', not ok and err == 'target_rank_too_high', err)
    ok, err = API.SetRank(1, 'lspd', 2, { name = 'Senior Officer' })
    T.check('Chief renames a lower rank', ok and fw.gradeData('police', 2).name == 'Senior Officer' and CC.rankName('lspd', 2) == 'Senior Officer', err)
    T.check('rename saved to the database', db.ranks['lspd:2'].name == 'Senior Officer')
    if fw.name == 'qbx' then
        T.check('qbx: rename saved to jobs.lua', fw.jobsFile().police.grades[2].name == 'Senior Officer')
    end
    local a = lastAudit()
    T.check('rank change audited with NULL target', a.action == 'rank_update' and a.target == nil and a.actor == 'CHIEF')
    ok, err = API.SetRank(1, 'lspd', 1, { payment = 90 })
    T.check('Chief sets pay (name kept)', ok and fw.gradeData('police', 1).payment == 90 and fw.gradeData('police', 1).name == 'Officer', err)
    ok, err = API.SetRank(1, 'lspd', 1, { payment = 10 ^ 9 })
    T.check('pay above max rejected', not ok and err == 'invalid_payment', err)
    ok, err = API.SetRank(1, 'lspd', 1, { caps = { 'bad cap!' } })
    T.check('invalid capability name rejected', not ok and err == 'invalid_capability', err)
    ok, err = API.SetRank(1, 'lspd', 1, { name = '' })
    T.check('empty rank name rejected', not ok and err == 'invalid_rank_name', err)

    -- non-editors
    ok, err = API.SetRank(3, 'lspd', 0, { name = 'Recruit' })
    T.check('rank without structure.manage cannot edit', not ok and err == 'no_permission', err)

    -- owner via ACE (CIV is a civilian)
    S.aces['4:cmd_chain.structure'] = true
    ok, err = API.SetRank(4, 'lspd', 7, { name = 'Commissioner', payment = 300, caps = { 'roster.manage_all' } })
    T.check('ACE owner adds a rank above Chief', ok and fw.gradeData('police', 7).name == 'Commissioner' and CC.depts.lspd.rankList[1].grade == 7, err)
    T.check('new top rank inherits everything', CC.hasCap('lspd', 7, 'reports.view_own') and CC.hasCap('lspd', 7, 'structure.manage'))
    a = lastAudit()
    T.check('owner change audited with owner as actor', a.action == 'rank_create' and a.actor == 'CIV')
    ok, err = API.SetRank(4, 'lspd', 3, { caps = { 'roster.set_callsign', 'reports.approve', 'mdt.access' } })
    T.check('owner grants a custom capability', ok and API.HasPermission(2, 'mdt.access'), err)
    ok, err = API.SetRank(4, 'lspd', 5, { caps = { 'roster.promote', 'roster.fire', 'structure.manage' } })
    T.check('owner gives Captain structure.manage', ok, err)

    -- Captain edits within limits
    ok, err = API.SetRank(2, 'lspd', 3, { caps = { 'roster.set_callsign', 'reports.approve', 'mdt.access', 'mdt.admin' } })
    T.check('cannot grant a capability you lack', not ok and err == 'cannot_grant_capability', err)
    ok, err = API.SetRank(2, 'lspd', 4, { caps = { 'roster.set_division' } })
    T.check('cannot remove a capability your own rank inherits', not ok and err == 'affects_higher_ranks', err)
    ok, err = API.SetRank(2, 'lspd', 2, { caps = { 'reports.write' } })
    T.check('Captain grants a held capability to a lower rank', ok, err)
    ok, err = API.SetRank(2, 'lspd', 5, { name = 'Major' })
    T.check('Captain cannot edit own rank', not ok and err == 'target_rank_too_high', err)
    local editor = API.GetStructureEditor(2, 'lspd')
    T.check('editor payload: Captain can edit only lower ranks', editor and editor.maxGrade == 4 and (function()
        for _, r in ipairs(editor.ranks) do
            if (r.grade < 5) ~= r.editable then return false end
        end
        return true
    end)())
    local ownerEditor = API.GetStructureEditor(4, 'lspd')
    T.check('editor payload: owner can edit everything', ownerEditor and ownerEditor.owner and ownerEditor.maxGrade == 255)

    -- delete rules
    ok, err = API.RemoveRank(4, 'lspd', 1)
    T.check('cannot delete a rank an offline member holds', not ok and err == 'rank_in_use', err)
    ok, err = API.SetRank(4, 'lspd', 12, { name = 'Temp' })
    T.check('owner adds an empty rank', ok and fw.gradeData('police', 12) ~= nil, err)
    ok, err = API.RemoveRank(1, 'lspd', 12)
    T.check('Chief cannot delete a rank above own', not ok and err == 'target_rank_too_high', err)
    ok, err = API.RemoveRank(4, 'lspd', 12)
    T.check('owner deletes an empty rank', ok and fw.gradeData('police', 12) == nil and db.ranks['lspd:12'] == nil and CC.depts.lspd.ranks[12] == nil, err)
    T.check('delete audited', lastAudit().action == 'rank_remove')
    ok, err = API.RemoveRank(4, 'lspd', 99)
    T.check('deleting an unknown rank fails', not ok and err == 'unknown_rank', err)

    -- end to end: hire into an editor-created grade
    API.SetRank(4, 'lspd', 8, { name = 'Deputy Commissioner' })
    ok, err = API.Hire(0, 'CIV', 8, 'lspd')
    T.check('hire into an editor-created grade', ok and fw.grade('CIV', 'police') == 8, err)

    -- console
    ok, err = API.SetRank(0, nil, 9, { name = 'X' })
    T.check('console must name the department', not ok and err == 'department_required', err)
    local cmdOk = pcall(E.S.commands.ccrank, 0, { dept = 'lspd', grade = 9, payment = '120', name = 'Deputy Chief' })
    T.check('ccrank creates a rank', cmdOk and fw.gradeData('police', 9).name == 'Deputy Chief')
    E.S.commands.ccrank(0, { dept = 'lspd', grade = 9, payment = 'remove' })
    T.check('ccrank remove deletes it', fw.gradeData('police', 9) == nil)

    -- public data
    local dept = API.GetDepartment('lspd')
    local r7
    for _, r in ipairs(dept.ranks) do if r.grade == 7 then r7 = r end end
    T.check('GetDepartment ranks include payment and ownCaps', r7 and r7.payment == 300 and r7.ownCaps[1] == 'roster.manage_all')

    -- reload from the database (same records)
    local before = json.encode(CC.rankRecords('lspd'))
    CC.loadStructure(CC.depts.lspd)
    T.check('reload from the database matches', json.encode(CC.rankRecords('lspd')) == before)

    -- full restart: new sandbox with the saved database, fresh framework defaults
    local E2 = Env.new({ root = base.root, framework = base.framework, editable = true, db = { ranks = db.ranks } })
    T.check('restart: structure loaded from the database', E2.env.CC.rankName('lspd', 7) == 'Commissioner' and E2.env.CC.rankName('lspd', 2) == 'Senior Officer')
    T.check('restart: editor-created grades pushed into the framework again', E2.fw.gradeData('police', 7) and E2.fw.gradeData('police', 8).name == 'Deputy Commissioner')

    -- boot cache is applied before the database is ready
    local E3 = Env.new({
        root = base.root, framework = base.framework, editable = true, defer = true,
        files = { ['cmd_chain/structure.cache.json'] = S.files['cmd_chain/structure.cache.json'] },
    })
    T.check('boot cache creates grades before the database is ready', not E3.env.CC.ready and E3.fw.gradeData('police', 7) and E3.fw.gradeData('police', 7).name == 'Commissioner')

    -- editor off
    local E4 = Env.new({ root = base.root, framework = base.framework, editable = false })
    local off, offErr = E4.env.API.SetRank(0, 'lspd', 7, { name = 'X' })
    T.check('editor off: SetRank refused', not off and offErr == 'structure_locked', offErr)
    T.check('editor off: no rank rows written', next(E4.S.db.ranks) == nil)
end
