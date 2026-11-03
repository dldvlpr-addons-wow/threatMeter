# 09. Overkill in the breakdown

**Status:** waiting for a need (weak evidence). **Type:** feature.

## Player demand
- Blizzard forums, beta thread "Feedback: Damager Meter" (link now 404, seen through search results):
  "Does not count overkill damage".
- Only one source, no vote count visible.

## API
`DamageMeterCombatSpell.overkillAmount` (source `forever`, `DamageMeterDocumentation.lua:224`).
ForeverMeter does not read it (0 occurrence in `ForeverMeter.lua`). The death recap already shows the
overkill of the killing blow (`RecapLines`).

## Proposal
In the breakdown, out of combat: overkill next to the spell total, for example `12.3k (+1.2k overkill)`.
In combat the value is probably secret: show it only out of combat, like the comparison.

## Trigger
A second request, or a player who asks why their total differs from Warcraft Logs.

**Files if done:** `ForeverMeter.lua` (`RenderDetail`), `Locale/*.lua`, `uicheck.lua`.
