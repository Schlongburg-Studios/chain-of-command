# Tests

Automated tests for the `cmd_chain` server logic. They run the real resource files in a sandbox with mocked FiveM natives, oxmysql, ox_lib, and **QBCore or Qbox**. No game server is needed.

These tests complement the manual checklist in [`../TESTING.md`](../TESTING.md); they don't replace it. They check our logic against mocks built from the frameworks' current source. Only a real server proves the frameworks behave the way the mocks assume.

## Run

With Lua 5.4:
```bash
lua tests/run.lua
```

Without Lua (uses [lupa](https://pypi.org/project/lupa/), which bundles Lua 5.4):
```bash
pip install lupa
python tests/run.py
```

Options: `-v` prints passing checks too. A word filters suites, e.g. `python tests/run.py structure`. The exit code is 1 if anything fails.

## What runs

Each suite runs in a **fresh sandbox** for every combination:

| Framework | Editor | Suites |
| --- | --- | --- |
| Qbox | on | roster, sync, structure, qbx_multijob |
| QBCore | on | roster, sync, structure |
| Qbox | off | roster, sync, qbx_multijob |
| QBCore | off | roster, sync |

| Suite | Covers |
| --- | --- |
| `suites/roster.lua` | The CLAUDE.md must-pass checks (Captain can't promote to Captain, Cadet can't hire, offline member in roster), rank ceiling, inherited permissions, hire/fire/promote/demote, callsigns, divisions, offline targets, rate limit, console actor, client callback and `/cc` paths |
| `suites/sync.lua` | Startup reconcile, external `/setjob` (sync_hire / sync_grade / sync_fire), duty events, logout/login |
| `suites/structure.lua` | v1.1 rank editor: seeding, grade push, Qbox `jobs.lua` write (job `type` kept, backup), QBCore never writing qb-core files, owner ACE, `structure.manage` limits, delete guards, `ccrank`, restart from the database, boot cache before the database is ready, editor off |
| `suites/qbx_multijob.lua` | Qbox: promoting a secondary-job officer keeps their primary job, duty only on the primary job, `max_jobs` errors, hire sets primary when unemployed |

The default world is CHIEF (grade 6, src 1), CAPT (5, src 2) and CADET (0, src 3) online; CIV (src 4) and CIV2 (src 5) online civilians; and OFF1, an offline Officer (grade 1). Framework police grades match the shipped defaults (0–4). With the editor off, grades 5 and 6 are pre-added, as README install step 4 asks.

## Layout

```
tests/
  run.lua  run.py      runners
  lib/env.lua          sandbox: natives, events, oxmysql + ox_lib mocks, loads cmd_chain
  lib/qbx.lua          Qbox mock (exports, events, player_groups)
  lib/qb.lua           QBCore mock (core object, exports, events, players table)
  lib/json.lua         JSON for the sandbox
  lib/t.lua            check() helper
  suites/*.lua         test suites
```

The oxmysql mock **fails any query whose parameter array has a `nil` hole** (see CLAUDE.md), and the Qbox mock fails if cmd_chain uses qbx_core's `commitToFile`.

## Adding a test

A suite is `return function(E, T, Env, base) ... end`:
- `E.env.API` and `E.env.CC` are the resource's server tables.
- `E.fw` holds framework helpers: `grade`, `primaryJob`, `gradeData`, `externalSetJob`, `externalRemoveJob`, `setDuty`, `login`, `logout`, `jobsFile`.
- `E.S.db` is the mocked database.
- `Env.new(base)` builds another sandbox, e.g. to simulate a restart.
- Use `T.check(name, condition, extra)`.

Register new suites in the `runs` table in `run.lua`.

If a framework changes behaviour, update the mock in `lib/qbx.lua` or `lib/qb.lua` to match its current source first, then the bridge.
