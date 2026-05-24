# atmrob — ATM Robbery for Qbox

A complete ATM robbery script for FiveM servers running the Qbox framework.

## Features
- **Hack method** — progress bar + skillcheck minigame, single cash pile reward
- **Drill + Rope** — two step combined method, physics-based ATM extraction
- **Server-side security** — proximity checks, exploit detection, clean logging
- **Single server event per robbery** — no log spam
- **Fully configurable** — rewards, cooldowns, police requirements, minigame difficulty

## Dependencies
- [qbx_core](https://github.com/Qbox-project/qbx_core)
- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_inventory](https://github.com/overextended/ox_inventory)
- [sleepless_interact](https://github.com/Sleepless-Development/sleepless_interact)

## Installation
1. Download the latest release
2. Extract to `resources/[your-folder]/atmrob`
3. Add to `server.cfg`: esnure atmrob

4. Add items to `ox_inventory/data/items.lua` (see `/install/`)
5. Configure `shared/config.lua`

## Configuration
All tunable values are in `shared/config.lua`.

Framework touch points (money, notifications, police count) are 
isolated in helper functions at the top of `server/main.lua` — 
swap these out for your server's specific exports.

## Notes
- Drill + Rope method is included but `Config.EnableDrillRope` 
  defaults to `true` — disable if not ready for your server
- No shop included — item acquisition left to the server owner

## Licence
MIT — free to use, modify and distribute with attribution.