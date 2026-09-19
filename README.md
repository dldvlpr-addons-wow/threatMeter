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
- Jusqu'à 4 fenêtres, chacune avec son mode, sa session et sa position (dégâts et soins côte à côte, par exemple).
  Menu → **Nouvelle fenêtre** / **Fermer cette fenêtre**, ou `/fm windows 2`.
- Sessions : combat actuel, global, ou n'importe quel combat conservé par le client.
- Bouton **Menu** (ou clic droit sur le titre) : mode, session, verrou, fenêtres. Bouton **Reset** : remise à zéro.
- Survol d'une barre : top 5 des sorts de la source. Clic : détail par sort (icône, total, par seconde). Molette : défilement.
- Icône de spécialisation fournie par le client quand elle existe, sinon icône de classe.
- Dégâts subis : le détail par sort indique la créature qui l'a lancé.
- Morts : instant de la mort sur la barre, derniers coups reçus (recap de mort du client) au survol.
- Bouton dans le compartiment d'addons (à côté de la minimap) pour afficher ou masquer les fenêtres.
- Menace : alerte visuelle et sonore au-dessus d'un seuil réglable (`/fm warn 90`).
- Rapport en chat (`/fm report 5`) : raid, groupe ou say selon le contexte.
- 11 langues (`Locale/`) : enUS, frFR, deDE, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW.
  Par défaut, celle du client ; `/fm lang frFR` en impose une, `/fm lang auto` revient à celle du client.

## Commandes
```
/fm mode <damage|heal|absorbs|taken|interrupts|dispels|deaths|threat>
/fm report [N] | reset | lock | unlock | toggle
/fm windows <1-4> | scale <x> | rows <n> | width <px> | warn <%> | sound | pets | defaults
/fm lang [auto|enUS|frFR|deDE|esES|esMX|itIT|ptBR|ruRU|koKR|zhCN|zhTW]
/fm debug   (valeurs brutes de C_DamageMeter, pour diagnostiquer un affichage)
```
`mode`, `report` et `debug` agissent sur la première fenêtre ; les autres se règlent par leur menu.

## Vérification hors jeu
```
lua selfcheck.lua
lua uicheck.lua
```
`selfcheck.lua` teste la logique pure (formatage, tri de la menace, recap de mort, configuration des fenêtres).
`uicheck.lua` exécute la partie interface sur un faux client (chargement, migration des réglages, fenêtres,
menu, tooltip, détail, commandes, valeurs secrètes en combat).

## Licence
GPL-3.0-or-later (voir `LICENSE`).
