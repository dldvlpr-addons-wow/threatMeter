# ForeverMeter

<<<<<<< HEAD
Compteur de dégâts, soins, dégâts subis et menace pour **WoW Forever** (client 1.60, moteur 12.x).
Un seul fichier Lua, aucune dépendance (ni Details, ni Ace, ni LibStub). Alternative légère à Details.

## Pourquoi un compteur dédié
Sur ce moteur, `COMBAT_LOG_EVENT_UNFILTERED` est interdit aux addons (popup ADDON_ACTION_FORBIDDEN).
Les données viennent de `C_DamageMeter`, le compteur serveur de Blizzard. En combat, noms, montants et
GUID sont des « valeurs secrètes » : affichables, mais ni comparables ni additionnables. L'addon affiche
les barres dans l'ordre fourni par l'API et complète (pourcentages, détail par sort) hors combat.
La menace vient de `UnitDetailedThreatSituation`.

## Installation
Copier le dossier dans `World of Warcraft/_classic_beta_/Interface/AddOns/ForeverMeter/`
(le dossier doit s'appeler `ForeverMeter`, comme le fichier `.toc`).

## Fonctions
- Modes : dégâts, soins, absorptions, dégâts subis, interruptions, dissipations, morts, menace.
- Sessions : combat actuel, global, ou n'importe quel combat conservé par le client.
- Bouton **Menu** (ou clic droit sur le titre) : choix du mode et de la session. Bouton **Reset** : remise à zéro.
- Clic sur une barre : détail par sort (icône, total, par seconde). Molette : défilement.
- Menace : alerte visuelle et sonore au-dessus d'un seuil réglable (`/fm warn 90`).
- Rapport en chat (`/fm report 5`) : raid, groupe ou say selon le contexte.
- 11 langues (`Locale/`) : enUS, frFR, deDE, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW.

## Commandes
```
/fm mode <damage|heal|absorbs|taken|interrupts|dispels|deaths|threat>
/fm report [N] | reset | lock | unlock | toggle
/fm scale <x> | rows <n> | width <px> | warn <%> | sound | pets | defaults
```

## Vérification hors jeu
```
lua selfcheck.lua
```
Teste la logique pure (formatage, tri de la menace, seuil d'alerte).

## Licence
GPL-3.0-or-later (voir `LICENSE`).
=======
Damage, healing, damage taken and threat meter for **WoW Forever** (client 1.60, 12.x engine).
Single Lua file, no dependencies (no Details, no Ace, no LibStub). A lightweight alternative to Details.

## Why a dedicated meter
On this engine, `COMBAT_LOG_EVENT_UNFILTERED` is forbidden to addons (ADDON_ACTION_FORBIDDEN popup).
Data comes from `C_DamageMeter`, Blizzard's server-side meter. In combat, names, amounts and GUIDs
are "secret values": they can be displayed, but not compared or summed. The addon shows the bars
in the order returned by the API and fills in the rest (percentages, per-spell breakdown) out of combat.
Threat comes from `UnitDetailedThreatSituation`.

## Installation
Install from CurseForge or Wago, or copy the folder into
`World of Warcraft/_classic_beta_/Interface/AddOns/ForeverMeter/`
(the folder must be named `ForeverMeter`, like the `.toc` file).

## Features
- Modes: damage, healing, absorbs, damage taken, interrupts, dispels, deaths, threat.
- Up to 4 windows, each with its own mode, session and position (damage and healing side by side, for example).
  Menu → **New window** / **Close this window**, or `/fm windows 2`.
- Snapping: a new window attaches below the previous one. Dropping a window against the edge of another
  snaps it (it then follows that window's moves and size); dragging it away detaches it.
- Size: grip in the bottom-right corner of each window (width and number of rows, per window).
  `/fm rows` and `/fm width` set a shared size and clear per-window sizes.
- Sessions: current fight, overall, or any fight kept by the client.
- **Menu** button (or right-click on the title): mode, session, lock, windows. **Reset** button: clears data.
- Padlock in the title bar: locks position and size of that window only (`/fm lock` / `unlock`: all windows).
- Hover a bar: top 5 spells of that source. Click: per-spell breakdown (icon, total, per second). Mouse wheel: scroll.
- Specialization icon when the client provides one, class icon otherwise.
- Damage taken: the per-spell breakdown shows the creature that cast it.
- Deaths: time of death on the bar, last hits taken (client death recap) on hover.
- Refresh every 0.2 s by default, on top of meter events (`/fm refresh 0.1` for snappier updates).
- Button in the addon compartment (next to the minimap) to show or hide the windows.
- Threat: visual and sound warning above an adjustable threshold (`/fm warn 90`).
- Chat report (`/fm report 5`): raid, party or say depending on context.
- 11 languages (`Locale/`): enUS, frFR, deDE, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW.
  Defaults to the client language; `/fm lang frFR` forces one, `/fm lang auto` goes back to the client language.

## Commands
```
/fm mode <damage|heal|absorbs|taken|interrupts|dispels|deaths|threat>
/fm report [N] | reset | lock | unlock | toggle
/fm windows <1-4> | refresh <s> | scale <x> | rows <n> | width <px> | warn <%> | sound | pets | defaults
/fm lang [auto|enUS|frFR|deDE|esES|esMX|itIT|ptBR|ruRU|koKR|zhCN|zhTW]
/fm debug   (raw C_DamageMeter values, to diagnose a display issue)
```
`mode`, `report` and `debug` apply to the first window; the others are set from their own menu.

## Offline checks
```
lua selfcheck.lua
lua uicheck.lua
```
`selfcheck.lua` tests pure logic (formatting, threat sorting, death recap, window configuration).
`uicheck.lua` runs the UI code against a fake client (loading, settings migration, windows,
menu, tooltip, breakdown, commands, secret values in combat, CVar settings mirror).

WoW Forever 1.60 writes account SavedVariables but does not read them back. Settings are therefore duplicated
(`Mirror.lua`): the table is stored in `g_addonCategoriesCollapsed` (Blizzard_AddOnList save,
`WTF/SavedVariables/`, read back at startup) and copied into `ForeverMeterMirror1..8` CVars (which survive
`/reload`). If the saved data comes back empty, these copies replace it.

## License
GPL-3.0-or-later (see [LICENSE](LICENSE)).
>>>>>>> f337a50ad558bfa5aafa94eaf623bb784d887ead
