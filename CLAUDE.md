# CLAUDE.md: Chain of Command (`cmd_chain`)

You are building **Chain of Command**, a free, MIT-licensed FiveM resource. The full requirements are in `SPEC.md`. Read it first and follow it exactly.

## Rules
- Lua 5.4 (`lua54 'yes'`), fxmanifest `fx_version 'cerulean'`, `game 'gta5'`.
- Dependencies: `ox_lib` and `oxmysql` only. No other hard dependencies.
- Support QBCore and Qbox through `bridge/qb.lua` and `bridge/qbx.lua`. Auto-detect the framework. Never call framework APIs outside `bridge/`.
- **Verify every framework function name against current official docs and source before using it.** Don't rely on memory. If you're unsure, stop and ask.
- **A player's rank always comes from the framework job grade.** Never store a player's rank or grade in the database.
- **Rank definitions** (name, pay, capabilities per grade) live in `cmd_chain_ranks` when `Config.Structure.editable` is on. Every change must also go into the framework job through the bridge. With the editor off, they come from `config.lua` only.
- All writes go server-side with a permission check, a rank-ceiling check and an audit-log entry. Never trust client-sent identity or rank. This includes rank-structure edits: non-owners can only edit ranks below their own, can only grant capabilities they hold, and can never change the effective permissions of their own rank or any rank above it.
- Never put `nil` inside an oxmysql parameter array; it can shift the parameters after it. Use SQL `NULL` or leave the column out.
- The public API in SPEC.md section 4 is a contract. Don't rename or remove anything without a major version bump. Additions (fields, optional trailing arguments, new exports or events) go in minor versions.
- Keep scope tight. No MDT, dispatch, payroll, Discord or web UI. Those are separate resources. In-game menus use ox_lib.

## Layout
```
cmd_chain/
  fxmanifest.lua
  config.lua
  bridge/qb.lua  bridge/qbx.lua
  server/main.lua  server/api.lua  server/audit.lua
  client/main.lua
  sql/install.sql
  structure.cache.json            (generated at runtime; do not commit)
README.md  LICENSE  CHANGELOG.md  TESTING.md  .gitignore   (repo root)
tests/                            automated tests (not shipped; see tests/README.md)
release/                          GitHub release notes and Cfx.re forum post drafts
dist/                             built release zips (git-ignored; build with git archive)
```

## Definition of done (per change)
1. It works on a clean QBCore server and a clean Qbox server.
2. README and the API docs are updated.
3. A CHANGELOG entry is written.
4. The automated tests pass (`lua tests/run.lua` or `python tests/run.py`). Add or update tests for the change.
5. The manual checklist in `TESTING.md` passes. It must include:
   - A Captain cannot promote anyone to Captain.
   - A Cadet cannot hire.
   - An offline member still appears in the roster.
   - A rank-structure editor cannot grant a capability they lack, or change the permissions of their own rank or higher.
   - A rank someone holds cannot be deleted.
   - Editor-created grades survive a full restart. On QBCore, holders keep their job after logging back in.
