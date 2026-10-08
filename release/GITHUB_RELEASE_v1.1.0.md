<!--
GitHub release draft. On GitHub: Releases → Draft a new release
  Tag:    v1.1.0  (create on publish, target: main)
  Title:  Chain of Command v1.1.0
  Attach: dist/cmd_chain-v1.1.0.zip
Paste everything below this comment into the description.
-->

**Chain of Command** is a free, MIT-licensed department core for FiveM. Define your departments, ranks, divisions, callsigns and permissions **once**, and every compatible police, EMS or DOJ script reads from it.

Works with **QBCore** and **Qbox** (auto-detected). Requires `ox_lib` and `oxmysql`.

## Download

Download **`cmd_chain-v1.1.0.zip`** below, put the `cmd_chain` folder in your `resources`, and follow the [5-minute install](https://github.com/Schlongburg-Studios/chain-of-command#5-minute-install).

> **Qbox servers:** add `add_filesystem_permission cmd_chain write qbx_core` to `server.cfg` after `ensure cmd_chain`, so Chain of Command can save your ranks to `qbx_core/shared/jobs.lua`. If it's missing, the console tells you exactly what to add.

## What's in it

- **Departments** (LSPD, BCSO, SAHP, EMS, DOJ or anything you name), each mapped to one framework job
- **Ranks with top-down permissions:** every rank inherits what the ranks below it can do
- **In-game rank editor** (`/ranks`): add ranks, rename them, set pay and choose permissions without touching a file. The framework's job grades are created for you.
- **Roster** (`/roster`): hire, fire, promote, demote, callsigns and divisions, for online and offline members
- **Safe by default:** every change is checked on the server for permission and rank, rate-limited, and written to an audit log. You can't promote anyone to your own rank or above.
- **Developer API:** exports and events for MDTs and other scripts, e.g. `exports.cmd_chain:HasPermission(src, 'reports.approve')`

## Tested on

- QBCore (txAdmin recipe) and Qbox (txAdmin recipe), on real servers
- 545 automated checks against both frameworks

See [CHANGELOG.md](https://github.com/Schlongburg-Studios/chain-of-command/blob/main/CHANGELOG.md) for the full list.

## Support

Ask in the Schlongburg Studios Discord `#free-support` channel. Include your framework, the Chain of Command version, and the error from your server console.
