# 07. One-click taunt

**Status:** rejected. **Type:** feature.

## In other addons
ForeverThreat: clicking a row casts the taunt on the mob that attacks that player (SecureActionButton,
`TauntAssist.lua:173`). It also detects tank swaps through `UNIT_SPELLCAST_SUCCEEDED`.

## Why it is rejected
- Out of scope: ForeverMeter is a meter, not a casting interface.
- Secure frames: the button's target cannot change in combat (ForeverThreat, `Core.lua:872-876`), and
  that is exactly when it would be needed. The protected attributes would have to be set before the pull.
- The bars already use the click for the breakdown and Shift-click for the comparison. A secure button
  per bar changes the whole input model of the window and adds a taint risk.

## Reopen if
A strong demand from tanks, with a design that does not touch the meter bars (separate frame).
