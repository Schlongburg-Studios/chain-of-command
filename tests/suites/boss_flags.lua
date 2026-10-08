-- Optional `isboss` / `bankAuth` on config.lua ranks: applied to the framework grade at every start,
-- left alone when not written, validated, not touched when the editor is off, kept by rank edits.
return function(E, T, Env, base)
    local qbx = base.framework == 'qbx'

    local function boot(config, editable)
        return Env.new({ root = base.root, framework = base.framework, editable = editable ~= false, config = config })
    end
    local function rankIn(config, grade)
        for _, r in ipairs(config.Departments.lspd.ranks) do
            if r.grade == grade then return r end
        end
    end

    -- shipped config: Chief is the boss, the Lieutenant (the stock job's old boss grade) is not
    local fw, API = E.fw, E.env.API
    local chief, lt = fw.gradeData('police', 6), fw.gradeData('police', 4)
    T.check('shipped config: Chief is boss', chief.isboss == true)
    T.check('shipped config: Lieutenant boss flag removed (key gone, not false)', lt.isboss == nil)
    T.check('shipped config: Lieutenant keeps its pay', lt.payment == 150)
    if qbx then
        T.check('qbx: Chief has bankAuth', chief.bankAuth == true)
        T.check('qbx: Lieutenant bankAuth removed', lt.bankAuth == nil)
    else
        T.check('qb: bankAuth is never written (qb-core has none)', chief.bankAuth == nil)
    end

    -- not written in config.lua = left exactly as the framework has it
    local plain = boot(function(c)
        for _, r in ipairs(c.Departments.lspd.ranks) do r.isboss, r.bankAuth = nil, nil end
    end)
    local g4, g6 = plain.fw.gradeData('police', 4), plain.fw.gradeData('police', 6)
    T.check('no flags in config: stock boss grade untouched', g4.isboss == true)
    T.check('no flags in config: new grade gets no flags', g6.isboss == nil and g6.bankAuth == nil)
    if qbx then T.check('no flags in config: stock bankAuth untouched', g4.bankAuth == true) end

    -- true / false are both applied
    local both = boot(function(c)
        rankIn(c, 1).isboss, rankIn(c, 1).bankAuth = true, true
        rankIn(c, 6).isboss, rankIn(c, 6).bankAuth = false, false
    end)
    T.check('false removes the flag from a grade that had it', both.fw.gradeData('police', 6).isboss == nil)
    T.check('true sets it on any grade', both.fw.gradeData('police', 1).isboss == true)
    if qbx then T.check('qbx: bankAuth true is set', both.fw.gradeData('police', 1).bankAuth == true) end

    -- re-applied at every start: someone changed it by hand while cmd_chain was stopped
    local first = boot()
    -- (the mock's gradeData returns copies, so flip the flag in the framework's own job table)
    if qbx then first.fw.JOBS.police.grades[6].isboss = nil else first.fw.SHARED.Jobs.police.grades['6'].isboss = nil end
    first.env.CC.pushRanks('lspd')
    T.check('pushRanks puts a removed flag back', first.fw.gradeData('police', 6).isboss == true)
    T.check('pushRanks again changes nothing', first.env.CC.pushRanks('lspd') == false)

    -- a rank edit keeps the flags
    local ok, err = API.SetRank(0, 'lspd', 6, { name = 'Boss' })
    T.check('SetRank rename succeeds', ok == true, err)
    T.check('SetRank rename keeps the boss flag', fw.gradeData('police', 6).name == 'Boss' and fw.gradeData('police', 6).isboss == true)
    if qbx then
        local file = fw.jobsFile()
        T.check('qbx: jobs.lua carries the flags', file and file.police.grades[6].isboss == true and file.police.grades[6].bankAuth == true and file.police.grades[4].isboss == nil)
    end

    -- validation: a typo fails loudly at start, naming the rank
    local okLoad, loadErr = pcall(boot, function(c) rankIn(c, 6).isboss = 'yes' end)
    T.check('isboss = "yes" is rejected at start', not okLoad and tostring(loadErr):find('isboss must be true or false', 1, true) ~= nil, loadErr)
    T.check('the error names the department and rank', tostring(loadErr):find('lspd', 1, true) ~= nil and tostring(loadErr):find('Chief', 1, true) ~= nil)
    okLoad, loadErr = pcall(boot, function(c) rankIn(c, 4).bankAuth = 1 end)
    T.check('bankAuth = 1 is rejected too', not okLoad and tostring(loadErr):find('bankAuth must be true or false', 1, true) ~= nil, loadErr)

    -- editor off: cmd_chain does not touch the framework's grades, so the flags are not applied
    local off = boot(nil, false)
    T.check('editor off: framework grades untouched (stock flags stay)', off.fw.gradeData('police', 4).isboss == true)
end
