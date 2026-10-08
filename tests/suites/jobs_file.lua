-- Qbox only: FiveM does not let one resource write into another unless server.cfg says
-- `add_filesystem_permission cmd_chain write qbx_core`. Without it jobs.lua cannot be saved, and
-- qbx_core would remove players from grades it does not know at its next start. cmd_chain must say
-- so loudly, never overwrite without a backup, and refuse to create more unsaved state.
return function(E, T, Env, base)
    local function boot(setup)
        local e = Env.new({ root = base.root, framework = 'qbx', editable = true, grants = setup.grants, defer = true })
        if setup.before then setup.before(e) end
        e.start()
        return e
    end
    local function out(e) return table.concat(e.S.prints or {}, '\n') end

    -- Capture console output for the whole file (run.lua silences print inside suites).
    local function withOutput(fn)
        local lines = {}
        local realPrint = print
        print = function(...)
            local parts = {}
            for i = 1, select('#', ...) do parts[#parts + 1] = tostring((select(i, ...))) end
            lines[#lines + 1] = table.concat(parts, '\t')
        end
        local ok, err = pcall(fn)
        print = realPrint
        assert(ok, err)
        return table.concat(lines, '\n')
    end

    -- With the permission (the default in the other suites): saved, no warning, flag clear.
    do
        local E2
        local text = withOutput(function() E2 = boot({}) end)
        T.check('granted: no warning is printed', not text:find('CANNOT SAVE', 1, true), text)
        T.check('granted: jobs file is not flagged', E2.env.CC.jobsFileBroken == false)
        T.check('granted: jobs.lua was written', E2.S.files['qbx_core/shared/jobs.lua'] ~= E2.S.originalJobs)
        T.check('granted: original backed up', E2.S.files['qbx_core/shared/jobs.lua.cmd_chain-original.bak'] == E2.S.originalJobs)
    end

    -- Without the permission: sandbox refuses every write into qbx_core.
    local blocked, text
    text = withOutput(function() blocked = boot({ grants = {} }) end)
    local CC, API, fw, S = blocked.env.CC, blocked.env.API, blocked.fw, blocked.S

    T.check('refused: a loud red block names the problem', text:find('CANNOT SAVE qbx_core/shared/jobs.lua', 1, true) ~= nil, text)
    T.check('refused: it prints the exact server.cfg line', text:find('add_filesystem_permission cmd_chain write qbx_core', 1, true) ~= nil)
    T.check('refused: it says what is at stake', text:find('cleanPlayerGroups', 1, true) ~= nil)
    T.check('refused: the block is printed once, not per attempt', select(2, text:gsub('CANNOT SAVE', '')) == 1)
    T.check('refused: flagged', CC.jobsFileBroken == true)
    T.check('refused: jobs.lua untouched', S.files['qbx_core/shared/jobs.lua'] == S.originalJobs)
    T.check('refused: no backup files were created', S.files['qbx_core/shared/jobs.lua.cmd_chain-original.bak'] == nil and S.files['qbx_core/shared/jobs.lua.bak'] == nil)
    T.check('refused: cmd_chain still runs (rosters, permissions keep working)', CC.ready == true and API.GetMember(1) ~= nil)

    -- Rank edits are refused instead of creating more in-memory-only state.
    for _, case in ipairs({
        { 'SetRank (rename)', function() return API.SetRank(0, 'lspd', 2, { name = 'Senior Officer' }) end },
        { 'SetRank (new grade)', function() return API.SetRank(0, 'lspd', 7, { name = 'Commissioner', payment = 300, caps = {} }) end },
        { 'RemoveRank', function() return API.RemoveRank(0, 'lspd', 2) end },
    }) do
        local ok, err = case[2]()
        T.check('refused: ' .. case[1] .. ' is blocked', ok == false and err == 'jobs_file_unwritable', err)
    end
    T.check('refused: nothing was renamed', fw.gradeData('police', 2).name == 'Corporal')
    T.check('refused: the error has a readable message', blocked.env.CC.describe('jobs_file_unwritable'):find('restart', 1, true) ~= nil)

    -- Nobody can be put into a grade that exists only in memory (they would be removed at restart).
    for _, grade in ipairs({ 5, 6 }) do
        local ok, err = API.Hire(0, 'CIV', grade, 'lspd')
        T.check(('refused: hiring into memory-only grade %d is blocked'):format(grade), ok == false and err == 'jobs_file_unwritable', err)
    end
    T.check('refused: the blocked hires changed nothing', fw.grade('CIV', 'police') == nil and S.db.members['CIV:lspd'] == nil)
    local ok, err = API.Promote(0, 'OFF1', 5, 'lspd')
    T.check('refused: promoting into a memory-only grade (5) is blocked', ok == false and err == 'jobs_file_unwritable', err)

    -- Grades 0-4 are already in jobs.lua (cmd_chain only renamed them), so they still work.
    for _, grade in ipairs({ 0, 1, 2, 3, 4 }) do
        T.check(('refused: grade %d is in the file on disk'):format(grade), CC.jobsFileBroken and blocked.env.Bridge.gradeOnDisk('police', grade) == true)
    end
    ok, err = API.Hire(0, 'CIV', 0, 'lspd')
    T.check('refused: hiring into grade 0 still works', ok == true, err)
    ok, err = API.Promote(0, 'CIV', 4, 'lspd')
    T.check('refused: promoting to grade 4 still works', ok == true, err)
    T.check('refused: grade 5 is not on disk', blocked.env.Bridge.gradeOnDisk('police', 5) == false and blocked.env.Bridge.gradeOnDisk('nojob', 0) == false)

    -- The server owner adds the permission and restarts. By now the boot cache (written during the
    -- failed start) pushes the grades into the framework before the database is ready, so nothing
    -- "changes" at boot; jobs.lua on disk is still stale and must be fixed anyway.
    local fixed
    text = withOutput(function()
        fixed = Env.new({
            root = base.root, framework = 'qbx', editable = true,
            db = { ranks = S.db.ranks },
            files = { ['cmd_chain/structure.cache.json'] = S.files['cmd_chain/structure.cache.json'] },
        })
    end)
    T.check('after adding the permission: no red block', not text:find('CANNOT SAVE', 1, true), text)
    T.check('after adding the permission: flag clear', fixed.env.CC.jobsFileBroken == false)
    local file = fixed.fw.jobsFile()
    T.check('after adding the permission: jobs.lua now has grades 0-6', file and file.police.grades[0].name == 'Cadet' and file.police.grades[6].name == 'Chief')
    T.check('after adding the permission: original backed up', fixed.S.files['qbx_core/shared/jobs.lua.cmd_chain-original.bak'] == fixed.S.originalJobs)
    T.check('after adding the permission: rank edits work again', fixed.env.API.SetRank(0, 'lspd', 2, { name = 'Senior Officer' }) == true)

    -- Another restart changes nothing: jobs.lua stays byte-identical and the backup is not overwritten.
    local before, backup = fixed.S.files['qbx_core/shared/jobs.lua'], fixed.S.files['qbx_core/shared/jobs.lua.cmd_chain-original.bak']
    local again
    text = withOutput(function()
        again = Env.new({
            root = base.root, framework = 'qbx', editable = true,
            db = { ranks = fixed.S.db.ranks },
            files = {
                ['cmd_chain/structure.cache.json'] = fixed.S.files['cmd_chain/structure.cache.json'],
                ['qbx_core/shared/jobs.lua'] = before,
                ['qbx_core/shared/jobs.lua.cmd_chain-original.bak'] = backup,
            },
        })
    end)
    T.check('restart: jobs.lua unchanged', again.S.files['qbx_core/shared/jobs.lua'] == before)
    T.check('restart: original backup not overwritten', again.S.files['qbx_core/shared/jobs.lua.cmd_chain-original.bak'] == backup)
    T.check('restart: no "seeded" line and no red block', not text:find('seeded', 1, true) and not text:find('CANNOT SAVE', 1, true), text)

    -- The backup must exist before jobs.lua is overwritten.
    local noBackup
    text = withOutput(function()
        noBackup = boot({ before = function(e) e.S.denyPattern = '.bak' end })
    end)
    T.check('backup fails: jobs.lua is NOT overwritten', noBackup.S.files['qbx_core/shared/jobs.lua'] == S.originalJobs)
    T.check('backup fails: flagged and reported', noBackup.env.CC.jobsFileBroken == true and text:find('CANNOT SAVE', 1, true) ~= nil)

    -- A write that reports success but does not land is also a failure.
    local lying
    text = withOutput(function()
        lying = boot({ before = function(e)
            local real = e.env.SaveResourceFile
            e.env.SaveResourceFile = function(res, file, data, len)
                if file == 'shared/jobs.lua' then return true end -- claims success, writes nothing
                return real(res, file, data, len)
            end
        end })
    end)
    T.check('silent write failure is caught by the read-back', lying.env.CC.jobsFileBroken == true and text:find('CANNOT SAVE', 1, true) ~= nil)

    -- editor off: nothing to write, nothing to warn about
    local off = Env.new({ root = base.root, framework = 'qbx', editable = false, grants = {} })
    T.check('editor off: no jobs file problem', off.env.CC.jobsFileBroken == false)
end
