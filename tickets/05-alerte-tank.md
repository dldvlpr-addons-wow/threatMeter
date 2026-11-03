# 05. Tank alert (another player gets close to aggro)

**Status:** waiting for a need. **Type:** feature.

## In other addons
- ThreatClassic2: when the player has aggro, the alert goes off if the highest scaled % among the others
  reaches the threshold (`core.lua:838-868`).
- ForeverThreat: aggro loss alert (`Core.lua:79`).

## Analysis
- The data is already there: `CollectThreat` builds the full list with `tanking` and `pct`
  (`ForeverMeter.lua:601-640`).
- Cost: small. When the `player` row is `tanking`, compare the highest `pct` among the others with the
  existing threshold, reusing the current warning (visual and sound).
- Forever has no specializations: the tank role cannot be read from the spec. Deciding by
  "I am tanking" (`isTanking`) avoids this problem.
- Against a boss, the values are secret: no alert. Same limit as the current warning.

## Real need
None observed. The current warning only serves the player who is about to pull aggro.

## Trigger
A request from a tank, or a group that loses the tank's aggro without noticing.

**Files if done:** `ForeverMeter.lua` (threat warning), options panel, `Locale/*.lua`, `selfcheck.lua`.
