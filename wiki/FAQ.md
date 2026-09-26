# FAQ

[Home](README.md) · [Getting Started](Getting-Started.md) · [Windows](Windows.md) · [Modes and Sessions](Modes-and-Sessions.md) · [Commands](Commands.md) · [FAQ](FAQ.md)

## Why not use the combat log?
On WoW Forever, `COMBAT_LOG_EVENT_UNFILTERED` is forbidden to addons (ADDON_ACTION_FORBIDDEN popup).
ForeverMeter reads `C_DamageMeter`, Blizzard's server-side meter, and `UnitDetailedThreatSituation` for threat.

## Why are percentages or the breakdown missing during combat?
In combat, names, amounts and GUIDs are "secret values": the game lets addons display them,
but not compare or add them. ForeverMeter shows the bars in the order given by the game
and fills in percentages and the per-spell breakdown once combat ends.

## My settings are lost after a restart
WoW Forever 1.60 writes account SavedVariables but does not read them back.
ForeverMeter keeps a copy of its settings in two other places and restores them automatically.
If settings still reset, report it with your client version.

## The window is gone
Type `/fm toggle`. If it is off screen, type `/fm defaults` to reset positions and settings.

## A value looks wrong
Type `/fm debug` and include the output when you report the issue.

## Where do I report a bug?
Open an issue on [GitHub](https://github.com/dldvlpr-addons-wow/threatMeter/issues).
