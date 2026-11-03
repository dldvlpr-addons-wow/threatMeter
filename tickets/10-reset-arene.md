# 10. Automatic reset on each arena match

**Status:** waiting for a need (weak evidence). **Type:** feature.

## Player demand
Blizzard forums EU, "Midnight Blizz Damage meter is useless" (`/t/midnight-blizz-damage-meter-is-useless/620014`,
May 2026): "Need to reset every time in 3v3, or it shows irrelevant data". One post only.

## Analysis
- `AutoReset` (`ForeverMeter.lua:1619`) resets on entering an instance other than the last one
  (`instanceID ~= lastInstanceID`). Two matches in a row in the same arena have the same `instanceID`:
  no reset between them.
- Needed: a match start signal. Candidates to check with `wow-api` before coding: `PVP_MATCH_ACTIVE`,
  `ARENA_PREP_OPPONENT_SPECIALIZATIONS`, `C_PvP.GetActiveMatchState`. Arenas and battlegrounds may not
  exist on WoW Forever: check that first.

## Trigger
A second request, or arenas confirmed on Forever.

**Files if done:** `ForeverMeter.lua` (`AutoReset`, events), `uicheck.lua`.
