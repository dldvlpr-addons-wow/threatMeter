# 02. AbbreviateNumbers on a secret value

**Status:** to check in game. **Type:** check. **Priority:** low.

## Observation in other addons
Recount says that `AbbreviateNumbers` on a secret number cannot be done after rounding. That is why its
secret per-second value shows "5235" instead of "5.2K" (`Tracker_Midnight.lua:160-170`). Details calls
`AbbreviateNumbers` 52 times, without proof that any of them gets a secret.

## Analysis of ForeverMeter
- `SecretNumber` (`ForeverMeter.lua:196-202`) calls `pcall(AbbreviateNumbers, v)`. When the call
  fails, it falls back to `string.format("%.0f", v)`, which accepts a secret value.
- It is used only for the secret **total** (`FM.FormatRow`, l.208-209). The secret per-second value goes
  through `%.1f`, never through `AbbreviateNumbers`. Recount's case (secret per-second value) does not
  happen here.
- The 1.14.0 changelog announces "In combat, totals are abbreviated by the game (`12K`)". The code
  comment mentions an in-game check, but only for the value under 1000 (`0.818`).

## Real need
None if the abbreviated total has already been seen in combat. In the worst case, the total shows
unabbreviated (`12345`), with no error.

## In-game check
In combat against a mob, Damage mode, total over 1000: the bar shows `12K`, not `12345`.
- OK: close the ticket.
- KO: decide whether the unabbreviated total is acceptable, or whether 1.14.0 must be fixed
  (changelog and README announce the abbreviation).

**Files:** none unless KO (`ForeverMeter.lua`, `CHANGELOG.md`, `README.md`).
