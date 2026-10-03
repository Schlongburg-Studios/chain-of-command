-- Qbox only: multi-job behaviour.
return function(E, T)
    local API, fw = E.env.API, E.fw

    -- CADET's primary job becomes mechanic; police stays as a secondary job.
    fw.P.CADET.jobs.mechanic = 0
    fw.exports.qbx_core:SetPlayerPrimaryJob('CADET', 'mechanic')
    T.check('setup: primary is mechanic, police kept', fw.primaryJob('CADET') == 'mechanic' and fw.grade('CADET', 'police') == 0)

    local ok, err = API.Promote(2, 'CADET', 3)
    T.check('promoting a secondary-job officer works', ok and fw.grade('CADET', 'police') == 3, err)
    T.check('promotion keeps the other primary job', fw.primaryJob('CADET') == 'mechanic' and fw.grade('CADET', 'mechanic') == 0)

    local m = API.GetMember(3, 'lspd')
    T.check('GetMember with dept for a secondary job', m and m.grade == 3 and m.rank == 'Sergeant')
    T.check('secondary job is never on duty', m and m.onDuty == false)
    T.check('GetMember without dept falls back to the first department held', API.GetMember(3).dept == 'lspd')

    -- hiring someone who already has the maximum number of jobs
    fw.maxJobs = 1
    fw.P.CIV.jobs.mechanic = 0
    fw.exports.qbx_core:SetPlayerPrimaryJob('CIV', 'mechanic')
    ok, err = API.Hire(2, 'CIV', 0)
    T.check('max_jobs error passes through', not ok and err == 'max_jobs', err)
    T.check('failed hire changes nothing', fw.grade('CIV', 'police') == nil and E.S.db.members['CIV:lspd'] == nil)

    -- hiring an unemployed player makes the job primary
    fw.maxJobs = 2
    ok, err = API.Hire(2, 'CIV2', 0)
    T.check('hire of an unemployed player sets police as primary', ok and fw.primaryJob('CIV2') == 'police', err)
end
