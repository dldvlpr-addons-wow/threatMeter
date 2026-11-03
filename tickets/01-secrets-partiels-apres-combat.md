# 01. Partial secrets right after combat

**Status:** to check in game. **Type:** robustness risk. **Priority:** medium.

## Observation in other addons
Details waits for the secrets to clear before reading the sessions. A 1 s ticker checks every field
(`parser_nocleu1.lua:794-823`) and scans the tables recursively (`issecrettable`, l.826-901).
Its comment says the client can still send secret values when the `Combat` restriction is already
back to 0 (`error("AddOnRestrictionType Combat is false but client is still reporting secret values.")`,
l.1213-1226).

## Analysis of ForeverMeter
- `secret` comes from the data, not from the combat state: `issecretvalue(list[1].totalAmount)`
  (`ForeverMeter.lua:975`). This avoids the "restriction 0 but secret" trap.
- Only the **first row** and only **`totalAmount`** are checked. When `secret` is false, the code calls
  the following without any guard:
  - `table.sort` on every `totalAmount` (`Sources`, l.546-553);
  - `amountPerSecond == 0` and `totalAmount / d` (`PerSecond`, l.502-510);
  - `sessionTotal > 0` and `total / sessionTotal` (`FM.FormatRow`, l.216-218);
  - the same pattern in `SortedSpells` (l.556-563), which tests only `spells[1]`.
- `Refresh()` (l.1065-1074) is not under `pcall`. With a snapshot where row 1 is readable but another
  field is secret, the error repeats on every refresh (0.2 s) until the data becomes consistent.

## Real need
Not observed so far: no error report of this kind. Nothing proves that a `C_DamageMeter` snapshot can
mix readable and secret values. Details' recursive scan protects an import, which proves nothing about
mixing. Check before writing any code.

## In-game check
1. `/console scriptErrors 1`, Damage mode, a window in **current fight** and another in **overall**.
2. Fight a mob in a group (other players' data). At the end of combat (`PLAYER_REGEN_ENABLED`),
   run `/fm debug` repeatedly for 2 to 3 s.
3. Watch for a Lua error `attempt to compare ... secret` or `attempt to perform arithmetic ... secret`
   in `Sources`, `PerSecond` or `FormatRow`.
4. Same in the per-spell breakdown, left open during combat.

## Fix if the error shows up
Build `secret` from every field the readable path uses: `list[1].totalAmount`,
`list[1].amountPerSecond`, `session.totalAmount`, `session.maxAmount`. One shared function, used by
`RenderMeter`, `Sources` and `SortedSpells`. No recursive scan unless the test shows a secret further
down the list. Add a case to `uicheck.lua`: a session with row 1 readable and `session.totalAmount` secret.

**Files:** `ForeverMeter.lua` (`Sources`, `SortedSpells`, `RenderMeter`), `uicheck.lua`.
