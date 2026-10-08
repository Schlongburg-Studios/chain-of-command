<!--
Cfx.re forum draft. Category: Releases (free).
Title (copy this):
  [FREE] [QBCore/Qbox] Chain of Command - departments, ranks, callsigns & permissions in one place

Before posting:
  - Replace [Discord invite link] with your server's invite.
  - Replace [Tebex link: add when the doc pack is live] once the doc pack is up, or delete that section.
  - Add 2-3 screenshots where marked (the /roster menu, the /ranks editor, the console "ready" line).
Paste everything below this comment.
-->

# Chain of Command

**Define your departments, ranks, divisions, callsigns and permissions once. Every police, EMS or DOJ script reads from it.**

No more editing job names and grade numbers across ten resources. Chain of Command is the shared source of truth: your MDT, dispatch or armory script asks it "can this player approve reports?" instead of hardcoding `job.name == 'police' and grade >= 3`.

[Screenshot: /roster menu]

## Features

- **Any departments:** LSPD, BCSO, SAHP, EMS, DOJ or custom, each mapped to one framework job
- **Top-down permissions:** each rank gets named capabilities and inherits everything below it
- **In-game rank editor** (`/ranks`): add as many ranks as you need, rename them, set pay and pick permissions. Changes are saved and the framework's job grades are created for you.
  - Server owners (ACE `cmd_chain.structure`) can edit every rank.
  - Chiefs can edit only the ranks below them, and can't hand out powers they don't have.
- **Roster** (`/roster` menu and `/cc` commands): hire, fire, promote, demote, callsigns with your own format, and divisions (Patrol, SWAT, K9, FTO...). Offline members included.
- **Secure:** every action is checked on the server for permission and rank and is rate-limited. Nobody can promote someone to their own rank or above. Everything goes to an audit log, including changes made with `/setjob`.
- **QBCore and Qbox**, auto-detected, including Qbox multi-job
- **Rank always comes from the framework job grade**, so there's nothing to sync and nothing to drift

[Screenshot: /ranks editor]

## For developers

```lua
-- server
if exports.cmd_chain:HasPermission(source, 'reports.approve') then
    local me = exports.cmd_chain:GetMember(source)
    print(me.rank, me.callsign, me.dept)
end

AddEventHandler('cmd_chain:dutyChanged', function(citizenid, onDuty, deptId) end)
```

Full API docs, with copy-paste examples, are in the [README](https://github.com/Schlongburg-Studios/chain-of-command#api-v1x). The API is versioned and won't break within 1.x.

## Install (5 minutes)

1. Download `cmd_chain-v1.1.0.zip` from the [latest release](https://github.com/Schlongburg-Studios/chain-of-command/releases/latest) and put `cmd_chain` in your `resources`.
2. In `server.cfg`, after your framework: `ensure cmd_chain`.
   - **Qbox only:** also add `add_filesystem_permission cmd_chain write qbx_core`.
3. Restart. The tables are created automatically.
4. Appoint your first Chief from the console: `cc hire <citizenid> 6 lspd`

[Screenshot: console showing "[cmd_chain] ready on qb/qbx"]

## Police Department Starter Docs ($9.99)

Want a ready-made SOP manual, penal code, training program, rank structure and Discord template for your department? [Tebex link: add when the doc pack is live]

|                       |                                         |
|-----------------------|-----------------------------------------|
| Code is accessible    | Yes (MIT, open source)                  |
| Subscription-based    | No                                      |
| Lines (approximately) | 2,700                                   |
| Requirements          | QBCore or Qbox, ox_lib, oxmysql         |
| Support               | Yes                                     |

**Download:** https://github.com/Schlongburg-Studios/chain-of-command/releases/latest
**Support:** [Discord invite link] (`#free-support`)
