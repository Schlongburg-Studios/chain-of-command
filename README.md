# Chain of Command (`cmd_chain`)

Define your departments, ranks, divisions, callsigns and permissions **once**. Every police, EMS or DOJ script reads from Chain of Command instead of hardcoding job names.

- Works with **QBCore** and **Qbox**, detected automatically. Supports Qbox multi-job.
- Rank always comes from the framework job grade. Chain of Command never stores a second copy, so ranks can't drift out of sync.
- Higher ranks inherit every permission of the ranks below them.
- **In-game rank editor (v1.1):** add as many ranks as you need, and rename them or change their pay and permissions without touching a file. Changes are saved and the framework job grades are created for you.
- Every roster change is checked on the server for permission and rank, rate-limited and written to an audit log.
- Free and MIT-licensed. Dependencies: `ox_lib` and `oxmysql`.

---

## 5-minute install

1. **Download** and put the `cmd_chain` folder in your `resources` directory.
2. **Ensure order** in `server.cfg`. Your framework must start first:
   ```cfg
   ensure oxmysql
   ensure ox_lib
   ensure qbx_core      # or: ensure qb-core
   ensure cmd_chain
   ```
3. **Database:** nothing to do. The tables are created on first start. If you prefer to run SQL yourself, use `cmd_chain/sql/install.sql`.
4. **Job grades:** with the rank editor on (`Config.Structure.editable = true`, the default), **skip this step**. Chain of Command creates any missing grades from `config.lua` on first start. With the editor off, each rank in `config.lua` needs the same grade in your framework's job. The default `police` job only has grades 0–4, so add grades 5 and 6 if you keep the example config:
   - QBCore, `qb-core/shared/jobs.lua` (string keys):
     ```lua
     ['5'] = { name = 'Captain', payment = 175 },
     ['6'] = { name = 'Chief', isboss = true, bankAuth = true, payment = 200 },
     ```
   - Qbox, `qbx_core/shared/jobs.lua` (number keys):
     ```lua
     [5] = { name = 'Captain', payment = 175 },
     [6] = { name = 'Chief', isboss = true, bankAuth = true, payment = 200 },
     ```
   On start, Chain of Command warns in the console about any configured grade the framework is missing.
5. **Appoint your first Chief** from the server console:
   ```
   cc hire <citizenid> 6 lspd
   ```
   Restart and done. Your Chief can now run `/roster` in game.
6. **Optional: let admins edit any rank.** Add this to `server.cfg`:
   ```cfg
   add_ace group.admin cmd_chain.structure allow
   ```

> Already have officers? Nothing to migrate. On start, everyone who holds the `police` job is picked up automatically, offline players included.

---

## In-game use

| Command | What it does |
| --- | --- |
| `/roster [dept]` | Opens the roster menu: everyone, online and offline, highest rank first. Shows rank, callsign, divisions and duty. Select a member to see the actions your rank allows. |
| `/cc hire <id\|citizenid> [grade] [dept]` | Hire. Grade defaults to the lowest rank. |
| `/cc fire <id\|citizenid> [dept]` | Fire. |
| `/cc promote <id\|citizenid> <grade> [dept]` | Promote. |
| `/cc demote <id\|citizenid> <grade> [dept]` | Demote. |
| `/cc callsign <id\|citizenid> <callsign\|none> [dept]` | Set or clear a callsign. |
| `/cc division <id\|citizenid> <a,b,c\|none> [dept]` | Set divisions, comma-separated. |
| `/ranks [dept]` | Rank structure editor (also in `/roster` → **Rank structure**). |
| `ccrank <dept> <grade> <pay> <name>` | Console/owner: create or update a rank. `ccrank <dept> <grade> remove` deletes it. |

`dept` is only needed if you belong to more than one department (Qbox multi-job). The `cc` commands also work from the server console, which bypasses rank checks and is audited with a `NULL` actor.

### The rules

- A rank has its own capabilities **plus every capability of every rank below it**.
- You can only change members **strictly below** your rank.
- You can never set a rank **equal to or above your own**. A Captain can promote up to Lieutenant, never to Captain.
- `roster.manage_all` counts as every `roster.*` capability plus `structure.manage`.
- Roster actions are rate-limited per player (`Config.RateLimit`, default 5 actions per 10 seconds).

### Editing the rank structure (v1.1)

Open `/ranks` or `/roster` → **Rank structure**. From there you can:
- **Add a rank** at any unused grade number (0–255).
- **Rename** a rank, **set its pay**, or **edit its capabilities**.
- **Delete** a rank, but only when nobody holds it, online or offline. Move members off it first.

**Who can edit:**

| Editor | Can edit |
| --- | --- |
| Server console, or anyone with ACE `cmd_chain.structure` | Every rank in every department, including adding ranks above the current top rank. Can grant any capability, including custom ones. |
| A rank with `structure.manage` (Chiefs get it through `roster.manage_all`) | Only ranks **strictly below** their own. Can only grant capabilities they hold, and can't make a change that would alter the permissions of their own rank or any rank above it (e.g. removing a capability that higher ranks inherit). |

Every change is written to the audit log (`rank_create`, `rank_update`, `rank_remove`) with the old and new rank data.

**Where the data lives:**
- **Database:** rank definitions (name, pay, capabilities) are stored in `cmd_chain_ranks`. That table is the master copy. `config.lua` ranks are only used to seed it on first start. A player's rank is still only their framework job grade.
- **Qbox:** grades are also saved into `qbx_core/shared/jobs.lua` (`Config.Structure.writeQbxJobsFile`). The original file is kept as `jobs.lua.cmd_chain-original.bak`, and the previous version as `jobs.lua.bak`. Every job field is kept, including `type = 'leo'`. Comments and hand formatting in that file are not kept. (Chain of Command writes this file itself because qbx_core's built-in save drops each job's `type`.)
- **QBCore:** grades are applied in memory on every start. Chain of Command never rewrites `qb-core/shared/jobs.lua`, because that file also holds other settings. A cache file (`cmd_chain/structure.cache.json`) is applied the moment the resource loads, so grades exist before anyone logs in.
  > ⚠️ On QBCore, a player whose grade is missing from the jobs list when they log in is set to unemployed by qb-core. **Keep `cmd_chain` running.** If you ever remove it, first copy your ranks into `qb-core/shared/jobs.lua`.

**Turning the editor off later:** on QBCore, grades that only the editor created disappear from memory, and holders of those grades are reset to unemployed by qb-core at their next login. Move everyone off those grades first, or add the grades to `qb-core/shared/jobs.lua`. On Qbox the grades stay in `jobs.lua`.

**Not supported yet:** renumbering or reordering existing ranks. A grade number is how the framework links each player to their rank, so moving a rank would mean rewriting every holder's job. To put a rank "between" two others, add it at a free number. Remember that other scripts may compare grade numbers.

### Changes made outside Chain of Command

If an admin uses the framework's `/setjob`, Chain of Command notices, creates or removes the member record, and writes it to the audit log as `sync_hire`, `sync_fire` or `sync_grade` with a `NULL` actor.

---

## Config reference (`config.lua`)

```lua
Config.Debug = false
Config.RateLimit = { max = 5, window = 10 } -- actions per window (seconds), per player

Config.Structure = {
  editable = true,          -- in-game rank editor; false = ranks come from this file only (v1.0 behaviour)
  writeQbxJobsFile = true,  -- Qbox: also save grades to qbx_core/shared/jobs.lua (backups kept)
  maxPayment = 100000,      -- highest pay an editor can set for one grade
}

Config.Departments = {
  lspd = {                                   -- department id
    label = 'Los Santos Police Department',
    job = 'police',                          -- framework job name (one job per department)
    callsignFormat = '^%d%-%a%-%d%d$',       -- Lua pattern, e.g. 1-A-12. nil = any (max 16 chars)
    ranks = {                                -- grade = framework job grade
      { grade = 6, name = 'Chief',      caps = { 'roster.manage_all' }, payment = 200 }, -- payment: seed only
      { grade = 5, name = 'Captain',    caps = { 'roster.promote', 'roster.fire' }, payment = 175 },
      { grade = 4, name = 'Lieutenant', caps = { 'roster.hire', 'roster.set_division' } },
      { grade = 3, name = 'Sergeant',   caps = { 'roster.set_callsign', 'reports.approve' } },
      { grade = 2, name = 'Corporal',   caps = { } },
      { grade = 1, name = 'Officer',    caps = { 'reports.write' } },
      { grade = 0, name = 'Cadet',      caps = { 'reports.view_own' } },
    },
    divisions = { 'patrol', 'detectives', 'swat', 'k9', 'fto' },
  },
}
```

| Capability | Allows |
| --- | --- |
| `roster.hire` | Hire |
| `roster.fire` | Fire |
| `roster.promote` | Promote **and** demote |
| `roster.set_callsign` | Set callsigns |
| `roster.set_division` | Set divisions |
| `structure.manage` | Edit ranks below your own (v1.1) |
| `roster.manage_all` | All of the above |
| anything else | Free-form, for your other scripts (e.g. `reports.approve`, `mdt.access`) |

A framework grade between two configured ranks gets the capabilities of the nearest configured rank below it.

---

## API (v1.x)

The API is versioned and **won't break within 1.x**. Fields and optional arguments may be added in minor releases.

### The member object

```lua
{
  citizenid = 'ABC12345',
  name      = 'John Doe',
  dept      = 'lspd',
  deptLabel = 'Los Santos Police Department',
  rank      = 'Sergeant',       -- rank name from config
  grade     = 3,                -- framework job grade
  callsign  = '1-A-12',         -- or nil
  divisions = { 'patrol', 'fto' },
  onDuty    = true,
  online    = true,
  hiredAt   = 1759400000,       -- unix time, or nil
}
```

### Server exports

```lua
-- Who is this? (server id or citizenid; deptId optional for multi-job)
local member = exports.cmd_chain:GetMember(source)            -- or GetMember('ABC12345', 'lspd')
if member then print(member.rank, member.callsign) end

-- Permission check (deptId optional: without it, any of the player's departments counts)
if exports.cmd_chain:HasPermission(source, 'reports.approve') then ... end

-- Department config + online members
local dept = exports.cmd_chain:GetDepartment('lspd')
-- { id, label, job, enabled, callsignFormat, divisions, members = { member, ... },
--   ranks = { { grade, name, caps (effective), ownCaps (v1.1), payment (v1.1) } } }

-- Everyone, online and offline, highest rank first
local roster = exports.cmd_chain:GetRoster('lspd')

-- Writes: actorSrc is the player performing the action (0 = server console).
-- Every write returns ok, err. deptId is optional.
local ok, err = exports.cmd_chain:Hire(actorSrc, 'ABC12345', 0)          -- grade optional
ok, err = exports.cmd_chain:Fire(actorSrc, 'ABC12345')
ok, err = exports.cmd_chain:Promote(actorSrc, 'ABC12345', 3)
ok, err = exports.cmd_chain:Demote(actorSrc, 'ABC12345', 1)
ok, err = exports.cmd_chain:SetCallsign(actorSrc, 'ABC12345', '1-A-12')  -- nil clears
ok, err = exports.cmd_chain:SetDivisions(actorSrc, 'ABC12345', { 'swat', 'k9' })

-- Rank structure (v1.1). Same rules as the in-game editor; actorSrc 0 = console.
ok, err = exports.cmd_chain:SetRank(actorSrc, 'lspd', 7, { name = 'Commander', payment = 250, caps = { 'mdt.admin' } })
ok, err = exports.cmd_chain:SetRank(actorSrc, 'lspd', 1, { payment = 90 })   -- partial update: other fields kept
ok, err = exports.cmd_chain:RemoveRank(actorSrc, 'lspd', 7)                   -- refused while anyone holds grade 7

-- Audit log, newest first (server only)
local rows = exports.cmd_chain:GetAuditLog('lspd', 50)                  -- optional 3rd arg: target citizenid
```

**Error codes** (`err`): `not_ready`, `actor_not_found`, `unknown_department`, `department_disabled`, `department_required`, `not_in_department`, `no_permission`, `rate_limited`, `invalid_target`, `target_not_found`, `cannot_target_self`, `target_rank_too_high`, `rank_ceiling`, `invalid_grade`, `grade_missing_in_framework`, `already_member`, `not_a_member`, `not_a_promotion`, `not_a_demotion`, `invalid_callsign`, `callsign_taken`, `invalid_division`, `max_jobs` (Qbox), `player_not_found`, `internal_error`.
Rank editor (v1.1): `structure_locked`, `unknown_rank`, `invalid_rank`, `invalid_rank_name`, `invalid_payment`, `invalid_capability`, `cannot_grant_capability`, `affects_higher_ranks`, `rank_in_use`, `last_rank`, `job_not_found`, `framework_rejected`, `update_qb_core`.

### Client exports

These are cached for UI only. The server always re-checks.

```lua
local me = exports.cmd_chain:GetMyMember()          -- optional deptId
if exports.cmd_chain:HasPermission('roster.hire') then
    -- show the Hire button
end
```

### Events

Both events fire on the server, and on the clients of that department's members plus the affected player.

```lua
-- member is nil when the citizen left the department
AddEventHandler('cmd_chain:memberUpdated', function(citizenid, member, deptId) end)      -- server
RegisterNetEvent('cmd_chain:memberUpdated', function(citizenid, member, deptId) end)     -- client

AddEventHandler('cmd_chain:dutyChanged', function(citizenid, onDuty, deptId) end)        -- server
RegisterNetEvent('cmd_chain:dutyChanged', function(citizenid, onDuty, deptId) end)       -- client

-- v1.1: a department's rank structure changed (re-read GetDepartment if you cache ranks)
AddEventHandler('cmd_chain:structureUpdated', function(deptId) end)                      -- server
RegisterNetEvent('cmd_chain:structureUpdated', function(deptId) end)                     -- client (all players)
```

> On the server, listen with `AddEventHandler`, **never** `RegisterNetEvent`. Otherwise clients could fake these events.

### Example integration: an MDT

```lua
-- server.lua of your MDT
lib.callback.register('mdt:approveReport', function(source, reportId)
    if not exports.cmd_chain:HasPermission(source, 'reports.approve') then
        return false, 'Only Sergeants and above can approve reports.'
    end
    local me = exports.cmd_chain:GetMember(source)
    MySQL.update.await('UPDATE mdt_reports SET approved_by = ?, approver_callsign = ? WHERE id = ?',
        { me.citizenid, me.callsign, reportId })
    return true
end)

-- Keep a live unit list without polling
AddEventHandler('cmd_chain:dutyChanged', function(citizenid, onDuty, deptId)
    if deptId == 'lspd' then TriggerClientEvent('mdt:unitDuty', -1, citizenid, onDuty) end
end)
```

```lua
-- client.lua of your MDT: hide buttons the player can't use (the server still checks)
local canApprove = exports.cmd_chain:HasPermission('reports.approve')
```

---

## Framework notes

| | QBCore | Qbox |
| --- | --- | --- |
| Jobs per character | 1. Hiring replaces the current job. | Up to `qbx:max_jobs_per_player` (default 1). Hiring **adds** the job and doesn't remove other jobs. |
| Duty | Primary job | Primary job only. Secondary jobs show `onDuty = false`. |
| Grade keys in jobs.lua | Strings (`['0']`) | Numbers (`[0]`) |

Promoting or demoting an online QBCore player resets their duty to the job's `defaultDuty`. That's QBCore's own `SetJob` behaviour.

## Data

| Table | Purpose |
| --- | --- |
| `cmd_chain_members` | citizenid, dept, callsign, divisions (JSON), hired_at, updated_at. **No rank column.** |
| `cmd_chain_audit` | Every change: dept, actor, target (NULL for rank-structure changes), action, old value, new value, time. |
| `cmd_chain_ranks` | v1.1 rank definitions per department: grade, name, payment, caps (JSON). Not a player's rank. |

Audit actions: `hire`, `fire`, `promote`, `demote`, `set_callsign`, `set_divisions`, `sync_hire`, `sync_fire`, `sync_grade`, `rank_create`, `rank_update`, `rank_remove`.

## Upgrading from 1.0

1. Replace the `cmd_chain` folder, keeping your `config.lua`.
2. Your old `config.lua` has no `Config.Structure`, so the editor stays **off** and nothing changes. To turn it on, add the `Config.Structure` block from the new `config.lua`.
3. Restart. Database changes apply automatically: the new `cmd_chain_ranks` table, and `target_citizenid` in the audit table becomes nullable.

## Not in v1

No MDT, reports, dispatch, payroll, Discord sync or web panel. Those are separate resources that build on this API. ESX support is planned for v1.2.

## Development

Automated tests run the server logic against mocked QBCore and Qbox, with no game server needed:
```bash
lua tests/run.lua
```
Or without Lua: `pip install lupa`, then `python tests/run.py`. See [tests/README.md](tests/README.md). The manual checklist for a real server is in [TESTING.md](TESTING.md).

## License

MIT. See [LICENSE](LICENSE).
