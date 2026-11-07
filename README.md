# ForeverMeter

Damage, healing, damage taken and threat meter for **WoW Forever** (client 1.60, 12.x engine).
Pure Lua, no libraries required: one main file, a settings mirror and 11 locale files.

> **First install: restart the game once.** The game only loads new texture and font files at startup,
> so `/reload` is not enough the first time. After an update, `/reload` is usually enough; restart if something looks missing.

## What's new in 1.17.0
- **Report channel**: `/fm report [N] guild`, `say`, `party`, `raid`, `instance` or `whisper <name>`; instance groups get the report in instance chat.
- **Mode of any window**: `/fm mode threat 2`.
- **New commands**: `/fm rowheight`, `/fm bgalpha`, `/fm autohide`, `/fm instanceonly`, `/fm autoreset`.
- **Minimize a window** to its title bar (button left of the gear), and **hide outside instances** (options panel).
- **Themes**: `classic`, `flat`, `glass`, `compact` (options panel or `/fm theme`).
- **Threat first** in the Display menu; clicking Menu again closes it.

### 1.16.0
- **Avoidable and deadly spells** marked in the damage taken breakdown and tooltip.
- **Death recap to chat**: shift-click a death, or `/fm report death [N]`.
- **Settings export and import**: `/fm export`, `/fm import`, or the options panel.
- **Boss filter** for enemy damage taken, **bar colour** per window, windows, rows and width in the options panel.

### 1.15.1
- **Threat warning with MuscaUI**: ForeverMeter no longer plays its sound when MuscaUI already warns.

### 1.15.0
- **Threat against a boss**: the game hides the numbers, so each bar shows the threat status instead
  (aggro, insecure aggro, above the tank). The warning goes off when you are above the tank.
- **Threat warning**: the sound plays again only after your threat has stayed below the threshold for 3 seconds.

Earlier versions: see [CHANGELOG.md](CHANGELOG.md).

## Why a dedicated meter
On this engine, `COMBAT_LOG_EVENT_UNFILTERED` is forbidden to addons (ADDON_ACTION_FORBIDDEN popup).
Data comes from `C_DamageMeter`, Blizzard's server-side meter. In combat, names, amounts and GUIDs
are "secret values": they can be displayed, but not compared or summed. The addon shows the bars
in the order returned by the API and fills in the rest (percentages, per-spell breakdown) out of combat.
Threat comes from `UnitDetailedThreatSituation`. Against a boss, where the values are secret, the bars
show the status from `UnitThreatSituation` (aggro, insecure aggro, above the tank) without numbers.

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
- Your own bar: when you rank below the visible rows, it takes the last row with your real rank (windows of 2 rows or more).
- Per window, from its menu: bar text (total, per second, percent), **My bar only**, **No title bar**, **Big number**, **Minimize**.
  Menu → Display → **DPS**: damage with the per second value only.
- Sessions: current fight, overall, or any fight kept by the client.
- **Menu** button (or right-click on the title): mode, session, lock, windows, copy as text. **Reset** button: clears data.
- Padlock in the title bar: locks position and size of that window only (`/fm lock` / `unlock`: all windows).
- Gear in the title bar: opens the options.
- Hover a bar: top 5 spells of that source. Click: per-spell breakdown (icon, total, per second). Mouse wheel: scroll; over the title: change mode.
  The breakdown is a separate panel above the meter windows; drag its title to move it, its position is kept.
- Shift-click a second bar while the breakdown is open: spell-by-spell comparison of both sources ("12.3k | 9.8k (+26%)"), out of combat only.
- Specialization icon when the client provides one, class icon otherwise.
- Damage taken: the per-spell breakdown shows the creature that cast it, and marks avoidable and deadly spells.
- Deaths: time of death on the bar, last hits taken (client death recap) on hover. Shift-click: send that recap to the group chat.
- Enemy damage taken: window menu filter, all enemies, elites and bosses, or bosses only.
- Bar colour per window: window menu, class colour (default) or a colour from the colour picker.
- Refresh every 0.2 s by default, on top of meter events (`/fm refresh 0.1` for snappier updates).
- Button in the addon compartment (next to the minimap) to show or hide the windows.
- Options panel (Options → AddOns → ForeverMeter, `/fm options`, **Options** in a window menu, or the gear in the title bar):
  theme, texture, font, font size, language, scale, refresh, threat warning, sound, pets, lock, auto show, reset,
  bar text columns (total, per second, percent), bar height, background opacity, number of windows,
  shared rows and width, settings export and import.
- Settings export and import (`/fm export`, `/fm import`): copy your settings as text to another PC or player.
- Bar textures (`blizzard`, `flat`, `gradient`, `glass`, `striped`, `fade`) and fonts (six bundled OFL fonts plus
  the game fonts). Textures and fonts from LibSharedMedia are listed too when another addon loads it.
- Animated bar fill.
- Test mode (`/fm test`): fake bars in the meter windows, to tune the look without a fight.
- Key bindings (Options → Key Bindings → ForeverMeter): show or hide the windows, reset, next mode of the first window.
- Auto show: windows only in combat or in a group, hidden 10 s after a solo fight (option).
- Auto reset: clear the data on entering an instance other than the last one, or on joining a group (option, off by default).
- Threat: visual and sound warning above an adjustable threshold (`/fm warn 90`).
- Chat report (`/fm report 5`): instance group, raid, party, or say in an instance; solo outside an instance, the lines are shown only to you. Add a channel to choose it: `/fm report 5 guild`, `/fm report 5 whisper Name`. Right-click the breakdown title
  to report that player's top 5 spells.
- 11 languages (`Locale/`): enUS, frFR, deDE, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW.
  Defaults to the client language; `/fm lang frFR` forces one, `/fm lang auto` goes back to the client language.

## Commands
```
/fm mode <threat|damage|heal|absorbs|taken|enemytaken|avoidable|interrupts|dispels|deaths> [window]
/fm report [N] [say|guild|party|raid|instance|whisper <name>] | report death [N] [channel]
/fm reset | lock | unlock | toggle | options
/fm theme [name] | texture [name] | font [name] [size] | font default
/fm windows <1-4> | refresh <s> | scale <x> | rows <n> | width <px> | warn <%> | sound | pets | test | defaults
/fm rowheight <n> | bgalpha <0-1> | autohide | instanceonly | autoreset
/fm export | import
/fm lang [auto|enUS|frFR|deDE|esES|esMX|itIT|ptBR|ruRU|koKR|zhCN|zhTW]
/fm debug   (raw C_DamageMeter values, to diagnose a display issue)
```
`report` and `debug` apply to the first window, `mode` too unless a window number follows; the others are set from their own menu.

## Offline checks
```
lua selfcheck.lua
lua uicheck.lua
```
`selfcheck.lua` tests pure logic (formatting, threat sorting, death recap, window configuration).
`uicheck.lua` runs the UI code against a fake client (loading, settings migration, windows,
menu, tooltip, breakdown, commands, secret values in combat, CVar settings mirror, auto show).
The release workflow runs both before publishing a tag.

WoW Forever 1.60 writes account SavedVariables but does not read them back. Settings are therefore duplicated
(`Mirror.lua`): the table is stored in `g_addonCategoriesCollapsed` (Blizzard_AddOnList save,
`WTF/SavedVariables/`, read back at startup) and copied into `ForeverMeterMirror1..8` CVars (which survive
`/reload`). If the saved data comes back empty, these copies replace it.
Website: https://muscalab.com/addons/forever-meter

## License
GPL-3.0-or-later (see [LICENSE](LICENSE)). Fonts in `Media/Fonts/` are under the SIL Open Font License 1.1
(see [Media/Fonts/OFL.txt](Media/Fonts/OFL.txt)).
