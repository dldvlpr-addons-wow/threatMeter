# 06. Threat on nameplates and multiple targets

**Status:** waiting for a need. **Type:** feature.

## In other addons
- NKThreat: grid with several targets and an enemy list (`boss1-5`, target, `raidNtarget`). It adds a
  status (0 to 3) or lead overlay on the nameplates, compatible with Plater, ThreatPlates and others
  (`Nameplates.lua:104-130`, `ThreatEngine.lua:561-591`).
- ThreatMeter: highest threat over every nameplate and `boss1-8` (`legacy.lua:104-140`).

## Analysis
- Limit given by NKThreat (`Flavor.lua:342-352`): threat **values** are readable only against the
  target or a non-boss unit. On another nameplate, you get the status (0 to 3) without numbers.
  So a multi-target view would show statuses, not percentages.
- Cost: high. Enemy enumeration, a new display (grid or overlay), compatibility with nameplate addons,
  and protected nameplate regions (`GetCenter` raises an error).
- Not the role of a damage meter. Addons dedicated to this already exist on Forever (NKThreat).

## Real need
External evidence (2026-11-03): ThreatClassic2 issue #125 "[REQ] Allow multiple windows to be shown for
multiple targets", open, 7 comments (`github.com/dfherr/ThreatClassic2/issues`). No request from a
ForeverMeter user yet.

## Trigger
A repeated request from tanks in dungeons with several packs. Even then, check first whether NKThreat
already covers it.

**Files if done:** new display module, `ForeverMeter.toc`, `Locale/*.lua`.
