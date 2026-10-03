Config = {}

-- Print extra information to the server console.
Config.Debug = false

-- Roster actions allowed per player within the time window (seconds).
Config.RateLimit = { max = 5, window = 10 }

-- In-game rank editor (v1.1).
--   editable = true:  ranks below only SEED the database on first start. After that, ranks
--                     are edited in game (/ranks or /roster -> Rank structure) and saved in the
--                     database; cmd_chain creates/updates the framework job grades to match.
--   editable = false: ranks come from this file only (v1.0 behaviour). Grades must already
--                     exist in your framework's jobs file.
-- Who can edit: ranks with 'structure.manage' (only ranks below their own), and anyone with
-- the ACE permission `cmd_chain.structure` (all ranks), e.g. in server.cfg:
--   add_ace group.admin cmd_chain.structure allow
Config.Structure = {
    editable = true,
    writeQbxJobsFile = true, -- Qbox: also save grades to qbx_core/shared/jobs.lua (backups kept)
    maxPayment = 100000,     -- highest pay an editor can set for one grade
}

-- Each department maps to exactly one framework job. Rank ALWAYS comes from that
-- job's grade.
--
-- ranks: top to bottom. A rank has its own caps plus every cap of every rank below it.
-- 'roster.manage_all' counts as every 'roster.*' capability plus 'structure.manage'.
-- payment (optional): pay for new grades when seeding; existing framework pay is kept.
--
-- Built-in capabilities:
--   roster.hire, roster.fire, roster.promote (promote and demote),
--   roster.set_division, roster.set_callsign, roster.manage_all,
--   structure.manage (edit ranks below your own)
-- Any other capability name (e.g. 'reports.write') is free-form, for other scripts.
--
-- callsignFormat: a Lua pattern; '^%d%-%a%-%d%d$' matches 1-A-12. Set nil to allow any.
Config.Departments = {
    lspd = {
        label = 'Los Santos Police Department',
        job = 'police',
        callsignFormat = '^%d%-%a%-%d%d$',
        ranks = {
            { grade = 6, name = 'Chief',      caps = { 'roster.manage_all' }, payment = 200 },
            { grade = 5, name = 'Captain',    caps = { 'roster.promote', 'roster.fire' }, payment = 175 },
            { grade = 4, name = 'Lieutenant', caps = { 'roster.hire', 'roster.set_division' } },
            { grade = 3, name = 'Sergeant',   caps = { 'roster.set_callsign', 'reports.approve' } },
            { grade = 2, name = 'Corporal',   caps = {} },
            { grade = 1, name = 'Officer',    caps = { 'reports.write' } },
            { grade = 0, name = 'Cadet',      caps = { 'reports.view_own' } },
        },
        divisions = { 'patrol', 'detectives', 'swat', 'k9', 'fto' },
    },

    -- ems = {
    --     label = 'Emergency Medical Services',
    --     job = 'ambulance',
    --     callsignFormat = '^M%-%d%d$',
    --     ranks = {
    --         { grade = 4, name = 'Chief',     caps = { 'roster.manage_all' } },
    --         { grade = 3, name = 'Doctor',    caps = { 'roster.hire', 'roster.set_callsign' } },
    --         { grade = 2, name = 'Paramedic', caps = {} },
    --         { grade = 1, name = 'EMT',       caps = {} },
    --         { grade = 0, name = 'Trainee',   caps = {} },
    --     },
    --     divisions = { 'ground', 'air' },
    -- },
}
