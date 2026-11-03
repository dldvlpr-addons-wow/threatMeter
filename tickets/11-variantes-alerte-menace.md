# 11. Threat warning variants (visual, group announcement)

**Status:** waiting for a need (weak evidence). **Type:** feature.

## Player demand
ThreatClassic2 issues (`github.com/dfherr/ThreatClassic2/issues`):
- #131 "other type of aggro warning": open, 1 comment.
- #127 announcement to the raid: open, 0 comment.
- #38 colour of the bar by threat status: closed.

## Analysis
- Today the warning is a sound only (`WARN_SOUND`, re-armed after 3 s below the threshold).
- Visual variant: a flash or a red border on the threat window. Cheap, no secret involved: the
  decision comes from `FM.ShouldWarn`, which already handles status-only rows.
- Group announcement: `C_ChatInfo.SendChatMessage` in combat. Not checked: whether it is allowed during
  an encounter on Forever (`wow-api`), and the spam risk (re-arm delay to raise for chat). Against a
  boss only the status is known, not the percentage.
- Bar colour by status: rows already have a status against a boss; a colour per status is possible.

## Trigger
A request from a ForeverMeter user, or more votes on the ThreatClassic2 issues.

**Files if done:** `ForeverMeter.lua` (`RenderThreat`, options), `Locale/*.lua`, `uicheck.lua`.
