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

## A new texture or font does not show
New media files are only picked up after restarting the game. `/reload` is not enough.

## Why can't I compare players during combat?
Other players' data is secret during combat. The comparison comes back once combat ends.

## Threat shows "unavailable in combat on this client"
Against some enemies (bosses especially), threat values are secret in combat: the game does not let addons read them.
ForeverMeter shows this message in the title instead of a wrong number.

## Some lines are missing from a copy, or a report line is shown only to me
In an instance, some names (creatures, restricted players) are secret. The game refuses them in chat
and in the copy box: **Copy as text** leaves those lines out, and `/fm report` shows them only to you.

## The options do not open during combat
The game blocks the options panel in combat. ForeverMeter opens it as soon as combat ends.

## `/fm report` sends nothing
Alone and outside an instance, the game forbids addons to use say. The report is shown only to you.
In a group it goes to party or raid, and in an instance to say.

## A value looks wrong
Type `/fm debug` and include the output when you report the issue.

## Where do I report a bug?
Open an issue on [GitHub](https://github.com/dldvlpr-addons-wow/threatMeter/issues).
