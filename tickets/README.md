# Tickets: comparison with other meters (2026-11-03)

Source: code reading of Details (Camelot toc), Recount 1.21.0, ThreatClassic2 2.75, ForeverThreat 1.7.1,
NKThreat 2.18.0 and ThreatMeter 0.7.4. Their facts are their authors' claims, not checked in game.

| # | Ticket | Status | Real need |
|---|--------|--------|-----------|
| 01 | [Partial secrets after combat](01-secrets-partiels-apres-combat.md) | To check in game | Possible: Lua error on every refresh |
| 02 | [AbbreviateNumbers on a secret](02-abbreviatenumbers-secret.md) | To check in game | Low: fallback already in place |
| 03 | [Pull aggro bar](03-barre-pull-aggro.md) | Waiting for a need | Not observed |
| 04 | [Threat on the focus](04-menace-focus.md) | Waiting for a need | Not observed |
| 05 | [Tank alert](05-alerte-tank.md) | Waiting for a need | Not observed |
| 06 | [Threat on nameplates and multiple targets](06-menace-nameplates.md) | Waiting for a need | ThreatClassic2 #125, 7 comments |
| 07 | [One-click taunt](07-taunt-un-clic.md) | Rejected | Out of scope for a meter |
| 08 | [Damage per target](08-degats-par-cible.md) | To check in game | Blizzard forums, 32/11/6 likes |
| 09 | [Overkill in the breakdown](09-overkill.md) | Waiting for a need | One forum post |
| 10 | [Reset on each arena match](10-reset-arene.md) | Waiting for a need | One forum post |
| 11 | [Threat warning variants](11-variantes-alerte-menace.md) | Waiting for a need | ThreatClassic2 #131, #127 |
| 12-18 | [Evolutions (CI tests, avoidable spells, death recap to chat, export/import, boss filter, bar colour, size options)](12-18-evolutions.md) | Done, 13 and 16 to check in game | Code and API reading, 2026-11-06 |

Tickets 08 to 11: player requests found on the Blizzard forums and ThreatClassic2 issues (2026-11-03).
Reddit could not be read. Not possible under 12.x, so no ticket: hits, casts, min/average/max per spell
(not in `C_DamageMeter`), aura uptime (secret auras), live comparison of players in combat (secret amounts).

## No ticket

- **`UnregisterEvent` on an event never registered** (would trigger `ADDON_ACTION_FORBIDDEN` on Forever,
  according to NKThreat `ThreatEngine.lua:1456`): no `.lua` file in the repo calls `UnregisterEvent`
  or `UnregisterAllEvents`. Nothing to fix. A pitfall to keep in mind, stored in memory.
- **`targettarget` returns secret threat values** (ThreatClassic2, NKThreat): `ThreatTarget()`
  (`ForeverMeter.lua:591`) uses only `target`. Already consistent.
