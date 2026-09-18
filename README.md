# ForeverMeter

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
