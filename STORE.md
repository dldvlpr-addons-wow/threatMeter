# ForeverMeter

**Threat, damage, healing and damage taken meter built for WoW Forever** (client 1.60, 12.x engine).

🌐 Website, changelog and FAQ: https://muscalab.com/addons/forever-meter

On WoW Forever the combat log is forbidden to addons, so classic meters break.
ForeverMeter reads Blizzard's own server-side meter (`C_DamageMeter`) and the game's threat API instead.
Pure Lua, no libraries required.

## New in 1.17.0
- **Report to any channel**: `/fm report 5 guild`, `say`, `party`, `raid`, `instance` or `whisper <name>`.
  In a dungeon finder group, the report goes to instance chat by default. Works for death recaps too.
- **Themes**: `classic`, `flat`, `glass` and `compact` set texture, font, bar height and opacity in one click.
- **Minimize a window** to its title bar with the button left of the gear. Click again to restore it.
- **Hide outside instances**: windows show again when you enter a dungeon, raid or battleground.
- **Threat first**: threat leads the Display menu and mode cycling.
- **New commands**: `/fm mode <mode> [N]`, `/fm theme`, `/fm rowheight`, `/fm bgalpha`, `/fm autohide`, `/fm instanceonly`, `/fm autoreset`.

## Features
- **10 modes**: threat, damage, healing, absorbs, damage taken, enemy damage taken, avoidable damage taken, interrupts, dispels, deaths.
- **Threat warning** (visual and sound) above an adjustable threshold. Against bosses, bars show your threat status (aggro, insecure aggro, above the tank).
- **Up to 4 windows**, each with its own mode, session, size, lock and bar colour. Windows snap to each other.
- **Sessions**: current fight, overall, or any fight kept by the game.
- **Per-spell breakdown** on click, top 5 spells on hover, spell-by-spell comparison of two players.
- **Death recap**: time of death and last hits taken; shift-click a death to send it to chat.
- **Your own bar always shown**, with your real rank, even below the visible rows.
- **Per-window display**: DPS, bar text, my bar only, no title bar, big number (a plain DPS counter).
- **Avoidable and deadly spells** marked in the damage taken modes.
- **Boss filter** for enemy damage taken: all enemies, elites and bosses, or bosses only.
- **Chat report** and **copy as text** for Discord.
- **Options panel**: themes, bar textures, six bundled fonts, LibSharedMedia support, text columns, bar height, background opacity, scale.
- **Settings export and import** (`/fm export`, `/fm import`) to copy your setup to another PC or player.
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
- Threat against some enemies (bosses especially) is secret in combat: the bars show the threat status
  without numbers. If the status is hidden too, the window says so instead of showing a wrong number.
- A report line with a name hidden by the game cannot be sent: the whole report then stays in your own chat window.
- The options panel cannot open during combat: it opens as soon as combat ends.

## Links
- Wiki: https://github.com/dldvlpr-addons-wow/threatMeter/tree/main/wiki
- Bug reports: https://github.com/dldvlpr-addons-wow/threatMeter/issues
- License: GPL-3.0-or-later. Bundled fonts: SIL Open Font License 1.1.
