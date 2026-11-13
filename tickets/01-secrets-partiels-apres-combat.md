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
  (`ForeverMeter.lua:1234`). This avoids the "restriction 0 but secret" trap.
- Only the **first row** and only **`totalAmount`** are checked. When `secret` is false, the code calls
  the following without any guard:
  - `table.sort` on every `totalAmount` (`Sources`, l.758-765);
  - `amountPerSecond == 0` and `totalAmount / d` (`PerSecond`, l.714-722);
  - `sessionTotal > 0` and `total / sessionTotal` (`FM.FormatRow`, l.253);
  - the same pattern in `SortedSpells` (l.775-782), which tests only `spells[1]`.
- Each window renders under `pcall` (`Guarded`, l.1346). With a snapshot where row 1 is readable but
  another field is secret, the broken window is emptied, its title shows (!), and the error is reported
  once; the other windows keep updating, and the window draws again as soon as the data is consistent.

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
