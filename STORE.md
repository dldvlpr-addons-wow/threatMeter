# ForeverMeter

**Damage, healing, damage taken and threat meter built for WoW Forever** (client 1.60, 12.x engine).

🌐 Website, changelog and FAQ: https://muscalab.com/addons/forever-meter

On WoW Forever the combat log is forbidden to addons, so classic meters break.
ForeverMeter reads Blizzard's own server-side meter (`C_DamageMeter`) and the game's threat API instead.
Pure Lua, no libraries required.

## Features
- **10 modes**: damage, healing, absorbs, damage taken, enemy damage taken, avoidable damage taken, interrupts, dispels, deaths, threat.
- **Up to 4 windows**, each with its own mode, session, size and lock. Windows snap to each other.
- **Sessions**: current fight, overall, or any fight kept by the game.
- **Per-spell breakdown** on click, top 5 spells on hover, spell-by-spell comparison of two players.
- **Death recap**: time of death and last hits taken.
- **Your own bar always shown**, with your real rank, even when you rank below the visible rows.
- **DPS display**, and per window: bar text, my bar only, no title bar, big number (a plain DPS counter).
- **Threat warning** (visual and sound) above an adjustable threshold.
- **Chat report** (`/fm report 5`) and **copy as text** for Discord.
- **Options panel**: bar textures, six bundled fonts, LibSharedMedia support, text columns, bar height, background opacity, scale.
- Auto show (only in combat or in a group), auto reset (new instance or new group), key bindings, addon compartment button, test mode.
- **11 languages**: enUS, frFR, deDE, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW.

## Getting started
1. Install, then **restart the game** the first time (new textures and fonts load only at startup).
2. A window opens on login. Click **Menu** or right-click the title to pick a mode and a session.
3. Click the gear in the title bar, or type `/fm options`, to change the look.

Type `/fm` in game for the full command list.

## Known limits of WoW Forever
- In combat, names and amounts are "secret values": the game lets addons display them, not compare or add them.
  Bars keep the game's order, and percentages, the breakdown and the comparison fill in once combat ends.
- Threat against some enemies (bosses especially) is secret in combat: the window says so instead of showing a wrong number.
- The options panel cannot open during combat: it opens as soon as combat ends.

## Links
- Wiki: https://github.com/dldvlpr-addons-wow/threatMeter/tree/main/wiki
- Bug reports: https://github.com/dldvlpr-addons-wow/threatMeter/issues
- License: GPL-3.0-or-later. Bundled fonts: SIL Open Font License 1.1.
