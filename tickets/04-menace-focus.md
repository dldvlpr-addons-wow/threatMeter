# 04. Threat on the focus

**Status:** waiting for a need. **Type:** feature.

## In other addons
- ForeverThreat: source `target` or `focus` as an option (`Threat.lua:82`).
- Details TinyThreat: `focus` when the option is on and a focus exists, `target` otherwise
  (`Details_TinyThreat.lua:282-294`).
- NKThreat: separate focus bar (`ThreatEngine.lua:913-921`).

## Analysis
- `ThreatTarget()` (`ForeverMeter.lua:591-596`) returns only `target`.
- Cost: small. A focus option, either as a per-window choice or as a fallback when the target is not
  hostile. Plus `PLAYER_FOCUS_CHANGED` for the refresh.
- Secrets: nothing proves that the values are readable against the focus when it is not the target.
  NKThreat says the values are readable only against the target or a non-boss unit. Check with
  `wow-api` and then in game.

## Real need
None observed. Typical use: a tank or a healer who watches a second mob.

## Trigger
A request from a tank or a healer, or a case where the target changes often and the threat window
empties.

**Files if done:** `ForeverMeter.lua` (`ThreatTarget`, window menu, events), `Locale/*.lua`, `uicheck.lua`.
