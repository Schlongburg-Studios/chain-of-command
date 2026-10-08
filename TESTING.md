# Manual test checklist: Chain of Command v1.1.0

Run the whole list once on a **clean QBCore** server and once on a **clean Qbox** server. Tick each box per framework.

**Qbox setup:** `server.cfg` needs `add_filesystem_permission cmd_chain write qbx_core` after `ensure cmd_chain` (README step 2). Without it cmd_chain cannot save `jobs.lua`; rows 42a–42c test exactly that, so run them first and add the line at 42c.

**Setup:** you need 3 characters you can log into (two clients, or relog between characters). Note their citizenids:
- **A** = Chief (grade 6)
- **B** = Captain (grade 5)
- **C** = Cadet (grade 0)
- **D** = civilian (unemployed). You'll also log D out for the offline tests.

With the rank editor on (default), grades 5 and 6 are created automatically on first start. To run rows 1–41 the v1.0 way, set `Config.Structure.editable = false` and add the grades yourself (README, install step 4).

| # | Step | Expected | QB | Qbox |
|---|---|---|---|---|
| **Install** |||||
| 1 | Start the server with `cmd_chain` after the framework | Console: `[cmd_chain] ready on qb` (or `qbx`) `with 1 department(s)`. No red errors. | ☐ | ☐ |
| 2 | Check the database | Tables `cmd_chain_members` and `cmd_chain_audit` exist | ☐ | ☐ |
| 3 | Temporarily set a rank to grade 9 in config and restart | Yellow warning naming grade 9. Revert afterwards. | ☐ | ☐ |
| **Bootstrap** |||||
| 4 | Console: `cc hire <A> 6 lspd` | `Done`. A has police grade 6 in the framework. Audit row `hire` with `actor_citizenid` NULL. | ☐ | ☐ |
| 5 | Console: `setjob`/admin-menu B to police 5 and C to police 0 (framework tools) | Audit rows `sync_hire` for B and C. Both appear in `/roster`. | ☐ | ☐ |
| **Required checks (definition of done)** |||||
| 6 | As B (Captain): `/cc promote <C> 5` | **Denied**: "You cannot set a rank equal to or above your own." C is still grade 0. | ☐ | ☐ |
| 7 | As B: `/cc promote <C> 6` | **Denied**, same message | ☐ | ☐ |
| 8 | As C (Cadet): `/cc hire <D server id>` | **Denied**: "Your rank does not allow that." D is still unemployed. | ☐ | ☐ |
| 9 | Log C out completely. As A: `/roster` | **C is listed as "Offline"** with rank Cadet | ☐ | ☐ |
| **Permissions and rank ceiling** |||||
| 10 | As B: `/cc fire <A citizenid>` | Denied: "You can only change members below your rank." | ☐ | ☐ |
| 11 | As B: `/cc promote <B's own id> 4` | Denied (cannot target yourself) | ☐ | ☐ |
| 12 | As B: `/cc promote <C> 4` (C offline is fine) | Done. C is now Lieutenant in the framework. Audit `promote` old 0, new 4, actor B. | ☐ | ☐ |
| 13 | As B: `/cc demote <C> 3` | Done. Audit `demote` 4 → 3. | ☐ | ☐ |
| 14 | As B: `/cc promote <C> 2` | Denied: "must be higher than the current rank" | ☐ | ☐ |
| 15 | As C (now Sergeant, online): `/cc hire <D id>` | Denied (Sergeants can't hire) | ☐ | ☐ |
| 16 | As B: `/cc hire <D id> 1` | Done. D is police grade 1 (QB: replaces job; Qbox: job added, set primary if D was unemployed). | ☐ | ☐ |
| 17 | As B: `/cc hire <D id> 1` again | Denied: "Already a member" | ☐ | ☐ |
| **Callsigns and divisions** |||||
| 18 | As C (Sergeant): `/cc callsign <D> abc` | Denied: format | ☐ | ☐ |
| 19 | As C: `/cc callsign <D> 1-A-12` | Done. Shows `[1-A-12]` in `/roster`. | ☐ | ☐ |
| 20 | As B: `/cc callsign <C> 1-a-12` | Denied: "Callsign already in use" (case-insensitive) | ☐ | ☐ |
| 21 | As C: `/cc callsign <B> 2-B-22` | Denied: B outranks C | ☐ | ☐ |
| 22 | As B: `/cc division <D> swat,patrol` | Done. Roster shows `patrol, swat`. | ☐ | ☐ |
| 23 | As B: `/cc division <D> navy` | Denied: unknown division | ☐ | ☐ |
| 24 | As B: `/cc division <D> none` | Divisions cleared | ☐ | ☐ |
| **Roster menu** |||||
| 25 | As C (Sergeant): `/roster`, select D | Only "Set callsign" shown (no promote/fire/divisions) | ☐ | ☐ |
| 26 | As B: `/roster`, select A | "No actions available" | ☐ | ☐ |
| 27 | As B: `/roster` → Hire / Promote / Divisions / Fire via the menu | Each works and shows a success notification. The promote list stops below Captain. | ☐ | ☐ |
| **Fire, sync, duty** |||||
| 28 | As B: `/cc fire <D>` | D is unemployed (Qbox: police job removed). Gone from roster. Audit `fire`. | ☐ | ☐ |
| 29 | Admin `/setjob` D to police 2 (outside cmd_chain) | D appears in roster. Audit `sync_hire`, actor NULL. | ☐ | ☐ |
| 30 | Admin `/setjob` D to police 3 | Audit `sync_grade` 2 → 3 | ☐ | ☐ |
| 30a | Give D a callsign (`/cc callsign <D> 1-A-12`) then admin `/setjob` D to police 4 | Audit `sync_grade` 3 → 4 **only** (no `sync_fire` / `sync_hire`); callsign `1-A-12` still shown in `/roster`. (Qbox with `qbx:setjob_replaces true`: the framework removes then adds.) | ☐ | ☐ |
| 31 | Admin `/setjob` D to unemployed | D removed (about half a second later). Audit `sync_fire`. | ☐ | ☐ |
| 32 | As B: toggle duty with the framework's duty point/command | Roster shows On duty / Off duty correctly. Test script below prints `dutyChanged`. | ☐ | ☐ |
| 33 | B disconnects while on duty | `dutyChanged false` fires for B | ☐ | ☐ |
| **Security** |||||
| 34 | As B: run `/cc callsign <C> none` 6+ times within 10 seconds | Later attempts: "Slow down" | ☐ | ☐ |
| 35 | From a client executor: `TriggerServerEvent('cmd_chain:memberUpdated', ...)` | Nothing happens on the server. *F8 can't run Lua; skip this if you have no executor (covered by the automated tests).* | ☐ | ☐ |
| 36 | Restart `cmd_chain` with players online | Roster and `/roster` still work. No duplicate audit rows. | ☐ | ☐ |
| **Qbox multi-job only** (`set qbx:max_jobs_per_player 2`) |||||
| 37 | Give C a second job (e.g. mechanic) as primary, then as B `/cc promote <C> 4` | C keeps mechanic as primary **and** is police 4. Nothing else removed. | n/a | ☐ |
| 38 | `exports.cmd_chain:GetMember(<C src>, 'lspd')` | Returns lspd member with `onDuty = false` (not primary job) | n/a | ☐ |

## API smoke test

Drop this in any server script (or a `test_cc` resource) to watch events and call the exports:

```lua
AddEventHandler('cmd_chain:memberUpdated', function(cid, member, dept)
    print('memberUpdated', cid, dept, member and member.rank or 'removed', member and member.callsign)
end)
AddEventHandler('cmd_chain:dutyChanged', function(cid, onDuty, dept)
    print('dutyChanged', cid, onDuty, dept)
end)

RegisterCommand('cctest', function(src)
    print(json.encode(exports.cmd_chain:GetMember(src)))
    print('reports.approve:', exports.cmd_chain:HasPermission(src, 'reports.approve'))
    print('roster size:', #(exports.cmd_chain:GetRoster('lspd') or {}))
    print(json.encode(exports.cmd_chain:GetAuditLog('lspd', 5)))
end, true)
```

| # | Step | Expected | QB | Qbox |
|---|---|---|---|---|
| 39 | `/cctest` as B | Member JSON with rank Captain. `reports.approve: true` (inherited from Sergeant). Roster size matches `/roster`. | ☐ | ☐ |
| 40 | `/cctest` as D (civilian) | `null`, `false` | ☐ | ☐ |
| 41 | Client F8: `print(exports.cmd_chain:HasPermission('roster.hire'))` as B / as C | `true` / `false` | ☐ | ☐ |

## v1.1: rank structure editor

Use the default config (`Config.Structure.editable = true`).

> ⚠️ **Don't put the owner ACE in server.cfg for these tests.** ACE permissions belong to your whole account, so with it on, every character you play is an owner and rows 45–50 and 56–59 would pass for the wrong reason. Turn it on only for rows 51–55 by typing these in the txAdmin Live Console:
> - before row 51: `add_ace group.admin cmd_chain.structure allow`
> - after row 55: `remove_ace group.admin cmd_chain.structure allow`
>
> **O** (owner) = character D (the civilian) while the ACE is on. Your account must be in `group.admin` (txAdmin recipes do this for the master account).

| # | Step | Expected | QB | Qbox |
|---|---|---|---|---|
| **First start** |||||
| 42 | Fresh database, start the server | Console: `rank structure seeded from config.lua (7 ranks)`. Table `cmd_chain_ranks` has 7 rows. No missing-grade warnings. | ☐ | ☐ |
| **Qbox: jobs file permission** (run before row 43, with the line absent from `server.cfg`, then add it) |||||
| 42a | Qbox, line **absent**: restart the server | A red block `CANNOT SAVE qbx_core/shared/jobs.lua (write_failed)` that prints the exact line to add, followed by `ready on qbx`. `jobs.lua` unchanged, no `.bak` files. | n/a | ☐ |
| 42b | Console, line absent: `cc hire <A> 6 lspd`, `cc hire <A> 5 lspd`, then `ccrank lspd 2 100 Senior` | The two hires into grades 5 and 6 are **refused** ("cmd_chain cannot save the jobs file…", error `jobs_file_unwritable`); so is the rank edit. Nothing changes in `player_groups` or `cmd_chain_ranks`. | n/a | ☐ |
| 42c | Console, line absent: `cc hire <C> 0 lspd` (grade 0 is already in `jobs.lua`) | Done. Then add the line to `server.cfg` and restart: no red block, `jobs.lua` has grades 0–6, `.bak` files exist (row 43). | n/a | ☐ |
| 43 | Qbox: open `qbx_core/shared/jobs.lua` | Police has grades 5 Captain / 6 Chief. `type = "leo"` is still on police (and on every other job that had a type). `jobs.lua.cmd_chain-original.bak` exists and matches your old file. | n/a | ☐ |
| 44 | QB: server console `cc hire <A> 6 lspd` works without editing `qb-core/shared/jobs.lua` | Done. `cmd_chain/structure.cache.json` exists. | ☐ | n/a |
| **Chief edits (structure.manage via roster.manage_all)** |||||
| 45 | As A (Chief): `/roster` | A "Rank structure" option shows | ☐ | ☐ |
| 46 | `/ranks` → Corporal → Rename "Senior Officer" | Saved. `/roster` shows the new name. Audit `rank_update` with target NULL. Qbox: jobs.lua updated. | ☐ | ☐ |
| 47 | `/ranks` → Officer → Set pay 90 | Next paycheck for an on-duty Officer is $90 | ☐ | ☐ |
| 48 | `/ranks` → Chief row | Greyed out (can't edit own rank) | ☐ | ☐ |
| 49 | `/ranks` → Add rank | With grades 0–5 all in use: "No free grade numbers below your rank." The Chief can't add a rank at or above their own. (The server also refuses grade 7 if called through the API, which the automated tests cover.) | ☐ | ☐ |
| 50 | `/ranks` → Corporal → Delete while someone holds grade 2 (online or offline) | Delete option disabled, shows member count | ☐ | ☐ |
| **Owner via ACE** |||||
| 51 | As O: `/ranks` (not in any department) | Department picker → LSPD editor. "Add rank" says "Owner: any free grade". | ☐ | ☐ |
| 52 | O: Add rank grade 7 "Commissioner", pay 300, caps `roster.manage_all` | Created. Framework has grade 7. Commissioner shows at the top of `/roster`. | ☐ | ☐ |
| 53 | O: Add rank grade 8 "Temp", then delete it | Created, then removed from the framework and DB (and jobs.lua on Qbox). Audit `rank_create` + `rank_remove`. | ☐ | ☐ |
| 54 | O: Edit capabilities on Sergeant, add custom `mdt.access` | Saved. `exports.cmd_chain:HasPermission(<Captain src>, 'mdt.access')` → true (inherited). | ☐ | ☐ |
| 55 | Console: `ccrank lspd 9 120 Deputy Chief` then `ccrank lspd 9 remove` | Both succeed | ☐ | ☐ |
| **Escalation guards** (O first gives Captain `structure.manage`) |||||
| 56 | As B (Captain): edit Sergeant caps and try to add `mdt.admin` (B doesn't have it) | The option isn't offered. Via export: `cannot_grant_capability`. | ☐ | ☐ |
| 57 | As B: remove `roster.hire` from Lieutenant | Refused: "would alter the permissions of your rank or ranks above it" | ☐ | ☐ |
| 58 | As B: give Corporal `reports.write` | Allowed | ☐ | ☐ |
| 59 | As C (Sergeant, no structure.manage): `/ranks` | "Your rank does not allow that." | ☐ | ☐ |
| **Persistence** |||||
| 60 | Restart the whole server | All edits from 46–58 are still there. Grade 7 still exists in the framework. | ☐ | ☐ |
| 61 | Hire someone into grade 7, restart, have them log in | They are still Commissioner (QB: not reset to unemployed) | ☐ | ☐ |
| 62 | First move everyone off grades that only the editor created (e.g. 7). Then set `Config.Structure.editable = false` and restart. | Ranks come from config.lua again. `/ranks` says editing is off. ⚠️ On QB, skipping the first step resets those players to unemployed at their next login. | ☐ | ☐ |
