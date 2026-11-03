# 03. "Pull aggro" bar (110 % melee, 130 % ranged)

**Status:** waiting for a need. **Type:** feature.

## In other addons
- ThreatClassic2 shows a bar at the threat needed to pull aggro: x1.1 in melee, x1.3 at range, plus a
  time before aggro (`core.lua:490-545`).
- ThreatMeter computes the threshold as `raw * 100 / scaled` (`core.lua:297-311`).
- NKThreat detects melee range with `UnitInMeleeRange`, then `IsItemInRange`, then
  `CheckInteractDistance` (`ThreatEngine.lua:482-529`).

## Analysis
- ForeverMeter already shows `rawPct` (percent of the tank's threat, `ForeverMeter.lua:627`). It also
  has a warning above an adjustable threshold (`/fm warn 90`).
- The pull bar would show the same thing differently: where 110 % or 130 % sits on the scale.
- Choosing between melee and ranged needs a range test on a hostile unit in combat. Whether these API
  are readable or protected on Forever is not verified (`wow-api`). Without that test, the threshold
  is wrong for one of the two cases.
- Against a boss, the values are secret: the bar would not work where it would matter most.

## Real need
None observed. The threshold warning covers "I am about to pull aggro".

## Trigger
A player asks to see their margin before aggro, or a report says the warning comes too early or too
late for ranged classes.

**Files if done:** `ForeverMeter.lua` (`AddThreatRow`, `RenderThreat`), `Locale/*.lua`, `uicheck.lua`.
