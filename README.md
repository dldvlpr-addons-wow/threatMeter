# ForeverMeter

Damage, healing, damage taken and threat meter for **WoW Forever** (client 1.60, 12.x engine).
Single Lua file, no dependencies.

## Why a dedicated meter
On this engine, `COMBAT_LOG_EVENT_UNFILTERED` is forbidden to addons (ADDON_ACTION_FORBIDDEN popup).
Data comes from `C_DamageMeter`, Blizzard's server-side meter. In combat, names, amounts and GUIDs
are "secret values": they can be displayed, but not compared or summed. The addon shows the bars
in the order returned by the API and fills in the rest (percentages, per-spell breakdown) out of combat.
Threat comes from `UnitDetailedThreatSituation`.

## Installation
Install from CurseForge or Wago, or copy the folder into
`World of Warcraft/_classic_beta_/Interface/AddOns/ForeverMeter/`
(the folder must be named `ForeverMeter`, like the `.toc` file).

## Features
- Modes: damage, healing, absorbs, damage taken, enemy damage taken, avoidable damage taken, interrupts, dispels, deaths, threat.
  Enemy and avoidable damage taken appear only when the client knows these meter types.
- Up to 4 windows, each with its own mode, session and position (damage and healing side by side, for example).
  Menu → **New window** / **Close this window**, or `/fm windows 2`.
- New window: same size and lock state as the window it comes from, attached to the first free side
  (below, right, above, left) without going off screen or covering another window.
- Snapping: dropping a window against the edge of another snaps it (it then follows that window's moves
  and size); dragging it away detaches it.
- Size: grips in the bottom-right and bottom-left corners of each window (width and number of rows, per window).
  `/fm rows` and `/fm width` set a shared size and clear per-window sizes.
- Sessions: current fight, overall, or any fight kept by the client.
- **Menu** button (or right-click on the title): mode, session, lock, windows. **Reset** button: clears data.
- Padlock in the title bar: locks position and size of that window only (`/fm lock` / `unlock`: all windows).
- Hover a bar: top 5 spells of that source. Click: per-spell breakdown (icon, total, per second). Mouse wheel: scroll.
  The breakdown is a separate panel above the meter windows; drag its title to move it, its position is kept.
- Shift-click a second bar while the breakdown is open: spell-by-spell comparison of both sources ("12.3k | 9.8k (+26%)"), out of combat only.
- Specialization icon when the client provides one, class icon otherwise.
- Damage taken: the per-spell breakdown shows the creature that cast it.
- Deaths: time of death on the bar, last hits taken (client death recap) on hover.
- Refresh every 0.2 s by default, on top of meter events (`/fm refresh 0.1` for snappier updates).
- Button in the addon compartment (next to the minimap) to show or hide the windows.
- Options panel (Options → AddOns → ForeverMeter, `/fm options`, or **Options** in a window menu):
  texture, font, font size, language, scale, refresh, threat warning, sound, pets, lock, reset.
- Bar textures (`blizzard`, `flat`, `gradient`, `glass`, `striped`, `fade`) and fonts (six bundled OFL fonts plus
  the game fonts). Textures and fonts from LibSharedMedia are listed too when another addon loads it.
- Animated bar fill.
- Threat: visual and sound warning above an adjustable threshold (`/fm warn 90`).
- Chat report (`/fm report 5`): raid, party or say depending on context.
- 11 languages (`Locale/`): enUS, frFR, deDE, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW.
  Defaults to the client language; `/fm lang frFR` forces one, `/fm lang auto` goes back to the client language.

## Commands
```
/fm mode <damage|heal|absorbs|taken|enemytaken|avoidable|interrupts|dispels|deaths|threat>
/fm report [N] | reset | lock | unlock | toggle | options
/fm texture [name] | font [name] [size] | font default
/fm windows <1-4> | refresh <s> | scale <x> | rows <n> | width <px> | warn <%> | sound | pets | defaults
/fm lang [auto|enUS|frFR|deDE|esES|esMX|itIT|ptBR|ruRU|koKR|zhCN|zhTW]
/fm debug   (raw C_DamageMeter values, to diagnose a display issue)
```
`mode`, `report` and `debug` apply to the first window; the others are set from their own menu.

## Offline checks
```
lua selfcheck.lua
lua uicheck.lua
```
`selfcheck.lua` tests pure logic (formatting, threat sorting, death recap, window configuration).
`uicheck.lua` runs the UI code against a fake client (loading, settings migration, windows,
menu, tooltip, breakdown, commands, secret values in combat, CVar settings mirror).

WoW Forever 1.60 writes account SavedVariables but does not read them back. Settings are therefore duplicated
(`Mirror.lua`): the table is stored in `g_addonCategoriesCollapsed` (Blizzard_AddOnList save,
`WTF/SavedVariables/`, read back at startup) and copied into `ForeverMeterMirror1..8` CVars (which survive
`/reload`). If the saved data comes back empty, these copies replace it.

## License
GPL-3.0-or-later (see [LICENSE](LICENSE)). Fonts in `Media/Fonts/` are under the SIL Open Font License 1.1
(see [Media/Fonts/OFL.txt](Media/Fonts/OFL.txt)).
