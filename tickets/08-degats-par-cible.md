# 08. Damage per target (boss vs adds)

**Status:** to check in game first. **Type:** feature.

## Player demand
- Blizzard forums US, "Midnight damage meter + CD manager" (`/t/midnight-damage-meter-cd-manager/2224165`):
  opening post 32 likes. Replies: the meter does not split boss and adds (11 likes); it does not show
  "what targets the person dealing damage was attacking" (6 likes); "who isn't attacking adds during a
  phase" (5 likes).
- Since 12.0, Details and Skada cannot build this view: the combat log is forbidden to addons. The
  Blizzard meter does not show it.

## API (source `forever`, `DamageMeterDocumentation.lua:215-240`)
- Each `DamageMeterCombatSpell` has `combatSpellDetails`, type `DamageMeterCombatSpellUnitDetails`:
  "Amount for a single target for all casts of the same spellID by a single source".
- Fields: `unitName`, `unitClassFilename` (NeverSecret), `classification` (NeverSecret), `isPet`, amount.
- Declared as one structure, not a list. Unknown: one target per spell entry (several entries for the
  same spell), or only the main target.
- `unitName` and the amount are not NeverSecret: assume secret in combat, readable after combat.

## Proposal
In the breakdown (`RenderDetail`), out of combat: group the source's damage by target, then by spell.
`classification` (`worldboss`, `elite`, `normal`…) splits boss and adds without reading the name.

## Check in game first
After a fight with a boss and adds, out of combat:
```
/dump C_DamageMeter.GetCombatSessionSourceFromType(1, Enum.DamageMeterType.DamageDone, UnitGUID("player")).combatSpells[1]
```
(`1` = current session, as `FM.SESSION_CURRENT` in `ForeverMeter.lua:43`.)
Look at `combatSpellDetails`: one target or several, and whether the same `spellID` appears once per
target. If only one target per spell, the view cannot be built: close the ticket.

**Files if done:** `ForeverMeter.lua` (`SortedSpells`, `RenderDetail`), `Locale/*.lua`, `uicheck.lua`.
