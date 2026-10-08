# Changelog

All notable changes to Chain of Command (`cmd_chain`). This project follows [Semantic Versioning](https://semver.org/): the public API (exports and events) never breaks within a major version.

## [1.1.0] - 2026-10-02

### Added
- **In-game rank structure editor** (`/ranks`, or `/roster` → Rank structure): add ranks at any free grade (0–255), rename them, set pay, edit capabilities, and delete empty ranks.
- Rank definitions are saved in the new `cmd_chain_ranks` table and pushed into the framework job grades. `config.lua` ranks seed the table on first start.
- Qbox: grades are saved to `qbx_core/shared/jobs.lua`, with backups (`jobs.lua.cmd_chain-original.bak`, `jobs.lua.bak`). Every job field is kept, including `type`.
- QBCore: grades are applied in memory on every start, plus a boot cache (`structure.cache.json`) so grades exist before players log in.
- `structure.manage` capability: edit ranks strictly below your own, granting only capabilities you hold. Included in `roster.manage_all`.
- ACE permission `cmd_chain.structure` for server owners/admins: edit every rank.
- Server exports `SetRank(actorSrc, deptId, grade, data)` and `RemoveRank(actorSrc, deptId, grade)`.
- Event `cmd_chain:structureUpdated (deptId)` on server and all clients.
- `GetDepartment` ranks now include `ownCaps` and `payment`.
- Console command `ccrank <dept> <grade> <pay> <name>` / `ccrank <dept> <grade> remove`.
- `Config.Structure` (`editable`, `writeQbxJobsFile`, `maxPayment`). A config without it keeps the v1.0 behaviour.
- Audit actions `rank_create`, `rank_update`, `rank_remove`.
- Automated tests in `tests/` (repo only, not shipped): QBCore and Qbox mocks, editor on and off. Run them with `lua tests/run.lua` or `python tests/run.py`.
- Optional `isboss` / `bankAuth` (true or false) on `config.lua` ranks: the framework's boss flags, applied to the grade at every start. Not written = left as the framework has it. The shipped config makes the Chief the boss and clears the flags from the Lieutenant (the stock police job's old boss grade). `bankAuth` is Qbox only.
- Qbox: an admin `/setjob` on someone who already holds the job (remove, then add, as two events) is recorded as one `sync_grade` and keeps the callsign and divisions, instead of `sync_fire` + `sync_hire`. A removal is applied after a 0.5 s grace period.
- Two job events arriving while a member row is being written no longer produce a duplicate `sync_hire` audit row and a duplicate `memberUpdated` event.
- Qbox: saving `jobs.lua` needs `add_filesystem_permission cmd_chain write qbx_core` in `server.cfg` (FiveM blocks writes into another resource). If it is missing, a red `CANNOT SAVE qbx_core/shared/jobs.lua` block names the exact line to add; rank edits and hires/promotions into ranks that are not in `jobs.lua` yet are refused (`jobs_file_unwritable`) so nobody is removed from their job by `qbx:cleanPlayerGroups` at the next restart. The backups are checked before `jobs.lua` is overwritten, and the written file is read back.

### Changed
- `cmd_chain_audit.target_citizenid` is now nullable (migrated automatically on start).

### Fixed
- Audit rows and clearing a callsign no longer pass `nil` inside oxmysql parameter arrays, which could shift the remaining parameters (affected console actions and `SetCallsign(..., nil)`).

## [1.0.0] - 2026-10-02

### Added
- Departments mapped to framework jobs, with ranks mapped to job grades. Rank always comes from the framework and is never stored.
- Top-down permissions: each rank inherits every capability of the ranks below it. `roster.manage_all` grants every `roster.*` capability.
- Divisions and callsigns: callsigns are format-checked against a Lua pattern and unique per department, ignoring case.
- Duty state read from the framework, with `cmd_chain:dutyChanged` events.
- Roster actions: hire, fire, promote, demote, set callsign, set divisions. Each one is checked on the server for permission and rank ceiling, rate-limited, and written to `cmd_chain_audit`.
- Framework bridges for QBCore (`bridge/qb.lua`) and Qbox (`bridge/qbx.lua`), detected automatically. Qbox multi-job is supported.
- Automatic sync with job changes made outside Chain of Command (e.g. `/setjob`), audited as `sync_hire`, `sync_fire` and `sync_grade`.
- Server exports: `GetMember`, `HasPermission`, `GetDepartment`, `GetRoster`, `GetAuditLog`, `Hire`, `Fire`, `Promote`, `Demote`, `SetCallsign`, `SetDivisions`.
- Client exports: `GetMyMember`, `HasPermission` (cached, UI only).
- Events: `cmd_chain:memberUpdated (citizenid, member, deptId)` and `cmd_chain:dutyChanged (citizenid, onDuty, deptId)`.
- `/roster` menu (ox_lib) and `/cc` commands. The commands work from the server console, which bootstraps the first Chief.
- Tables are created automatically on start. `sql/install.sql` is included for manual installs.
