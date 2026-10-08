# Chain of Command (`cmd_chain`): v1.x spec

**What it is:** A free, open-source FiveM resource that defines a server's departments, ranks, divisions, callsigns and permissions **once**. Every police, EMS or DOJ script reads from it instead of hardcoding job names.

**Why it exists:** Server owners say police scripts "don't communicate," and that single-department hardcoding makes "retrofitting job names across ten scripts... misery." Chain of Command is the shared source of truth, and the foundation the paid pd-mdt suite plugs into.

**Success test (14 days after release):** at least 25 servers running it (visible on FiveStats or 5Metrics), or at least 10 sales of the doc pack. Kill below 10 servers and under 3 sales.

---

## 1. Scope

**In v1.0**
- Departments (LSPD, BCSO, SAHP, EMS, DOJ, or any custom name), each mapped to one framework job.
- Ranks per department, mapped to that job's grades. Ordered from top (Chief) to bottom (Cadet).
- **Top-down permissions:** each rank gets named capabilities, and higher ranks inherit everything below them.
- Divisions (Patrol, Detectives, SWAT, K9, FTO, custom) as tags on officers.
- Callsigns with a configurable format and uniqueness checks.
- On/off duty state, read from the framework.
- Roster actions: hire, fire, promote, demote, set division, set callsign. Each action is permission-checked and written to the audit log.
- Framework adapters for **QBCore** and **Qbox**.
- A public API (exports and events) that other scripts call.

**In v1.1: in-game rank structure editor**
- Owners and authorised ranks build the rank structure in game: add ranks at any free grade (0–255), rename them, set pay per grade, edit capabilities, and delete empty ranks.
- Rank **definitions** (name, pay, capabilities per grade) are saved in the database and pushed into the framework job grades. `config.lua` ranks only seed the database on first start.
- Turned on by `Config.Structure.editable`. A config without `Config.Structure` keeps the v1.0 behaviour.

**Later:** ESX adapter (v1.2). Renumbering or reordering existing ranks, which needs a safe way to move every holder's grade, including offline players.

**Not in v1.x:** MDT, reports, dispatch, payroll, Discord sync, a web panel. These are paid add-ons or separate resources. Setting a grade's pay in the rank editor only edits the framework's own per-grade pay. It is not a payroll system.

## 2. Config (example)

```lua
Config.RateLimit = { max = 5, window = 10 }   -- roster/structure actions per player per window (s)

Config.Structure = {                          -- v1.1
  editable = true,          -- in-game rank editor; false = ranks come from config only (v1.0)
  writeQbxJobsFile = true,  -- Qbox: also save grades to qbx_core/shared/jobs.lua (with backups)
  maxPayment = 100000,      -- highest pay an editor can set for one grade
}

Config.Departments = {
  lspd = {
    label = 'Los Santos Police Department',
    job = 'police',                      -- framework job name
    callsignFormat = '^%d%-%a%-%d%d$',   -- server-side check only; never shown to players
    callsignExample = '1-A-12',          -- v1.1: what players see ("Format: 1-A-12")
    ranks = {                            -- top to bottom; grade = framework job grade
      -- With the editor on, these only seed cmd_chain_ranks on first start.
      { grade = 6, name = 'Chief',      caps = { 'roster.manage_all' }, payment = 200 },
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

**Permission rule:** a rank has its own capabilities plus every capability of every rank below it. A Chief therefore has everything. An actor can only change members **strictly below** their own rank. Promoting someone to your own rank or higher is never allowed. `roster.manage_all` counts as every `roster.*` capability plus `structure.manage`.

**Rank-structure rule (v1.1):**
- **Owners** (the server console, or ACE `cmd_chain.structure`) can edit every rank.
- **Members with `structure.manage`** can edit ranks strictly below their own only. They can grant only capabilities they hold, and can never make a change that alters the effective permissions of their own rank or any rank above it.
- A rank can't be deleted while anyone holds that grade, online or offline. A department always keeps at least one rank.

## 3. Data (oxmysql)

| Table | Columns |
| --- | --- |
| `cmd_chain_members` | citizenid, dept, callsign, divisions (JSON), hired_at, updated_at |
| `cmd_chain_audit` | id, dept, actor_citizenid (NULL = console/external), target_citizenid (NULL = structure change), action, old_value, new_value, created_at |
| `cmd_chain_ranks` (v1.1) | dept, grade, name, payment, caps (JSON), updated_at |

**A player's rank is never stored.** It always comes from the framework job grade, so there's one source of truth and no sync bugs.

`cmd_chain_ranks` holds rank **definitions**, not player ranks. With the editor on, it is the master copy of the structure, and the framework's grades are kept in line with it:
- **Qbox:** grades are updated in memory and written to `qbx_core/shared/jobs.lua`. Every job field is kept, including `type`. Backups are written first.
- **QBCore:** grades are updated in memory on every start, plus a boot cache (`cmd_chain/structure.cache.json`) applied when the resource loads. `qb-core/shared/jobs.lua` is never rewritten.

## 4. Public API: the contract other scripts depend on

Version this API and never break it in a minor release. Minor releases may add fields, optional trailing arguments and new exports or events.

**Server exports**
- `GetMember(src | citizenid, deptId?)` returns `{ citizenid, name, dept, deptLabel, rank, grade, callsign, divisions, onDuty, online, hiredAt }` or `nil`.
- `HasPermission(src, cap, deptId?)` returns a boolean.
- `GetDepartment(deptId)` returns the config, the ranks (`{ grade, name, caps, ownCaps, payment }`) and the list of online members.
- `GetRoster(deptId)` returns all members, online and offline.
- `GetAuditLog(deptId, limit?, targetCitizenid?)` returns audit rows, newest first.
- `Promote(actorSrc, targetCitizenid, newGrade, deptId?)` returns `ok, err`. The same pattern applies to `Demote`, `Hire` (grade optional), `Fire`, `SetCallsign` and `SetDivisions`.
- v1.1: `SetRank(actorSrc, deptId, grade, { name?, payment?, caps? })` and `RemoveRank(actorSrc, deptId, grade)` return `ok, err`.

`actorSrc = 0` is the server console: trusted, skips rank checks, and is audited with a NULL actor.

**Client exports**
- `GetMyMember(deptId?)`
- `HasPermission(cap, deptId?)` (cached, for UI only; the server always re-checks)

**Events (server and client)**
- `cmd_chain:memberUpdated` with `(citizenid, member, deptId)`. `member` is `nil` when the citizen left the department.
- `cmd_chain:dutyChanged` with `(citizenid, onDuty, deptId)`
- v1.1: `cmd_chain:structureUpdated` with `(deptId)`

## 5. Framework adapters

One file per framework under `bridge/`. Both expose the same functions:
- **Players:** `getPlayer`, `getPlayerByCitizenId` (online or offline), `getCitizenId`, `getSource`, `getName`.
- **Jobs:** `getJob` (primary job: name, grade, duty), `getJobs` and `getJobGrade` (multi-job), `isOnDuty`, `setJob`, `removeJob`, `getJobGrades`, `getJobMembers` (online and offline).
- **Events:** `onJobUpdate`, `onPlayerLoaded`, `onPlayerUnload`.
- **v1.1 grade editing:** `getJobGradeData`, `upsertJobGrade`, `removeJobGrade`, `persistJobs`.

Auto-detect which framework is running at start; Qbox is checked first because it also provides `qb-core`. **Before writing or changing an adapter, check the current QBCore and Qbox docs and source.** API names drift, and Qbox supports multiple jobs.

Known framework behaviour the adapters must respect:
- **Qbox `SetJob`** removes the player's current primary job, so promotions and hires use `AddPlayerToJob`.
- **Qbox's built-in save** (`commitToFile`) drops each job's `type`, so `persistJobs` writes `jobs.lua` itself.
- **QBCore resets a player to unemployed** if their grade is missing at login, so grades must be applied before players load.

## 6. Security (non-negotiable)

- Every write happens server-side, with a permission check and a rank-ceiling check.
- Never trust client input for the actor's identity or rank. Get both from the framework.
- Rate-limit roster and rank-structure actions.
- Every change goes to the audit log, including rank-structure changes.
- Rank-structure edits follow the rules in section 2. A member can never use the editor to raise their own permissions or those of ranks above them.

## 7. Release checklist

- Clean install on a fresh QBCore server **and** a fresh Qbox server.
- README with a 5-minute setup, the config reference, and API docs with copy-paste examples.
- An example integration: how an MDT calls `HasPermission`.
- MIT LICENSE file, a Cfx.re forum "Releases" post, GitHub tags.
- `TESTING.md` manual checklist passes on both frameworks.

## 8. Decisions

1. **Name:** Chain of Command. Resource folder `cmd_chain`. *(Decided 2026-10-02.)*
2. **License:** MIT. *(Decided 2026-10-02.)*
3. **pd-mdt relationship:** refactor pd-mdt to read ranks and permissions from `cmd_chain`, so it becomes the first paid add-on. *(Do after v1 ships.)*
4. **In-game rank editor ships in v1.1** (not v1.0), with pay per grade and ACE `cmd_chain.structure` for owners. *(Decided 2026-10-02.)*
5. **Qbox:** the editor writes grades to `qbx_core/shared/jobs.lua`. **QBCore:** grades are applied in memory on each start, and `qb-core/shared/jobs.lua` is never rewritten. *(Decided 2026-10-02.)*
6. **Rank definitions may live in the database** (`cmd_chain_ranks`) and be pushed to the framework. Player ranks still come only from the framework grade. *(Decided 2026-10-02.)*
7. **ESX moves to v1.2.** *(Decided 2026-10-02.)*
