# Tickets 12 to 18: evolutions (2026-11-06)

Source: code reading of ForeverMeter 1.15.1 and of the WoW Forever 1.60.1.70790 API source
(`Blizzard_APIDocumentationGenerated`). Nothing checked in game yet.

| # | Ticket | Cost | Status |
|---|--------|------|--------|
| 12 | [Tests in the release CI](#12-tests-in-the-release-ci) | S | Done |
| 13 | [Avoidable and deadly spells in the breakdown](#13-avoidable-and-deadly-spells-in-the-damage-taken-breakdown) | S | Done, to check in game |
| 14 | [Death recap to chat](#14-death-recap-to-chat) | S | Done (shift-click; no slash form) |
| 15 | [Settings export and import](#15-settings-export-and-import) | M | Done |
| 16 | [Boss and elite filter](#16-boss-and-elite-filter-in-enemy-damage-taken) | M | Done, to check in game |
| 17 | [Bar colour per window](#17-bar-colour-per-window) | M | Done |
| 18 | [Window count, rows and width in the options panel](#18-window-count-rows-and-width-in-the-options-panel) | S | Done |

---

## 12. Tests in the release CI

**Type:** tooling. **Cost:** S. **Risk:** none (the runner needs a `lua` interpreter).

### Why
`selfcheck.lua` (pure logic, locale completeness) and `uicheck.lua` (542 lines, fake WoW client: combat,
secrets, threat, boss, menu, snapping, simulated /reload, Mirror, autoHide, autoReset) only run by hand.
`.github/workflows/release.yml` packages and publishes on every tag push without running them.

### Value
A tag with a broken `ForeverMeter.lua` or a missing locale key is not published to CurseForge and Wago.

### Work
- Add a step before the packager: install Lua, then `lua selfcheck.lua` and `lua uicheck.lua`.
- The job fails if either script raises an error (`uicheck.lua` ends with `print("uicheck OK")`).

### Files
`.github/workflows/release.yml`.

---

## 13. Avoidable and deadly spells in the damage taken breakdown

**Type:** feature. **Cost:** S. **Risk:** low.

### Why
`DamageMeterCombatSpell` has `isAvoidable: bool` and `isDeadly: bool`, with no secret flag
(`DamageMeterDocumentation.lua:214-229`). ForeverMeter reads neither (0 occurrence in `ForeverMeter.lua`).

### Value
A healer or raid lead sees at a glance which hits taken were avoidable, and which ones killed.

### Work
- Per-spell breakdown (`ForeverMeter.lua` 792-977) and hover tooltip (1116-1186), damage taken modes:
  a marker (icon or coloured text) on avoidable spells, another on deadly spells.
- Locale keys for the legend in the 11 files.

### To check in game
- The fields are filled for real hits (not always `false`).
- They are readable in combat, not only after.

### Files
`ForeverMeter.lua`, `Locale/*.lua`, `uicheck.lua`.

---

## 14. Death recap to chat

**Type:** feature. **Cost:** S. **Risk:** low.

### Why
`FM.RecapLines` (`ForeverMeter.lua:287`) already formats the last hits from `C_DeathRecap.GetRecapEvents`,
and `ChatSend` (1784) already handles the chat type (raid, party, say in an instance, local print solo).
The recap is only shown in the tooltip of a bar in deaths mode (`AddRecapLines`, 1119).

### Value
Explain a wipe to the group in one click instead of a screenshot.

### Work
- Deaths mode: right-click on a bar's menu entry, or shift-click, sends that death's recap lines.
- Reuse the `AddRecapLines` guards: `recapID` not secret, not `-1`, `HasRecapEvents` true.
- Optional slash form, for example `/fm report death`.

### Limits
- `DeathRecapEventInfo` has no documented field (`DeathRecapDocumentation.lua:80-85`); the fields used
  today by `RecapLines` are the reference.
- Secret names stay out of chat, as in the existing report (1262).

### Files
`ForeverMeter.lua` (AddRecapLines, menu, slash), `Locale/*.lua`, `uicheck.lua`.

---

## 15. Settings export and import

**Type:** feature. **Cost:** M. **Risk:** medium (untrusted input).

### Why
WoW Forever writes account SavedVariables but never reads them back (`Mirror.lua:3-5`). Settings survive
through the `g_addonCategoriesCollapsed` host table of Blizzard_AddOnList and a CVar mirror, a workaround
that a client change could break. `Mirror.Serialize` (79) and `Mirror.Deserialize` (86) already give a
text format (`MIR1`, no `loadstring`).

### Value
- Back up the settings outside the client.
- Move a 4-window layout to another PC, another account, or another player.

### Work
- Export: serialize `db` (without the `forbidden` log) into a copyable edit box, like the copy as text.
- Import: paste a string, `Deserialize`, then validate every key and type against `DEFAULTS`
  and the window config shape before applying; reject the whole string on any error.
- Apply through the same path as `/fm defaults`, then `Mirror:Flush`.

### Risk
The pasted string comes from anyone: no execution, bounded size, bounded values (same bounds as the sliders).

### Files
`Mirror.lua`, `ForeverMeter.lua` (menu, slash, options panel), `Locale/*.lua`, `uicheck.lua`.

---

## 16. Boss and elite filter in enemy damage taken

**Type:** feature. **Cost:** M. **Risk:** low.

### Why
`DamageMeterCombatSource.classification` is `NeverSecret` (`DamageMeterDocumentation.lua:194-213`).
Filtering rows on it works in combat without comparing a secret value, and keeps the game's order.
Different from ticket 08 (damage per target and per player): here the enemy sources themselves are filtered.

### Value
In a dungeon, see the damage done to the boss without the trash rows.

### Work
- Window menu option in the enemy damage taken mode: all, elites and bosses, bosses only.
- `RenderMeter` (992) skips filtered sources; the rank shown follows the visible rows.

### To check in game
- The real values of `classification` (expected: `worldboss`, `elite`, `rareelite`, `rare`, `normal`, ...).

### Files
`ForeverMeter.lua` (RenderMeter, menu), `Locale/*.lua`, `uicheck.lua`.

---

## 17. Bar colour per window

**Type:** feature. **Cost:** M. **Risk:** low.

### Why
Bars always use the class colour (`ClassColor`, `ForeverMeter.lua:678`); `DEFAULTS` has no colour.
`ColorPickerFrame:SetupColorPickerAndShow(info)` exists on Forever
(`Blizzard_ColorPickerFrame/Mainline/ColorPickerFrame.lua:158`; fields `r`, `g`, `b`, `swatchFunc`,
`cancelFunc`, `hasOpacity`, `opacity`; `GetColorRGB` at 96).

### Value
- Tell side-by-side windows apart (damage and healing) at a glance.
- Readability for colour-blind players.

### Work
- Window menu: bar colour, class (default) or a single colour chosen in the colour picker.
- Rendering at 1029 (meter) and 1092 (threat). Threat keeps its red for the tank.
- `cancelFunc` restores the previous colour.

### Files
`ForeverMeter.lua` (DEFAULTS or window config, rendering, menu), `Locale/*.lua`, `uicheck.lua`.

---

## 18. Window count, rows and width in the options panel

**Type:** feature. **Cost:** S. **Risk:** low.

### Why
The number of windows, the shared rows and the shared width are set only by `/fm windows`, `/fm rows` and
`/fm width`. The bounds are duplicated between the slash handler (`ForeverMeter.lua:2045-2068`) and the
existing sliders (1981-1992).

### Value
A player who does not know the slash commands finds these settings.

### Work
- Three sliders in the options panel (1877-2033), calling the same code as the slash commands
  (`/fm rows` and `/fm width` clear per-window sizes: same behaviour).
- One bounds table shared by the slash handler and the sliders.

### Files
`ForeverMeter.lua` (options panel, slash), `Locale/*.lua`.
