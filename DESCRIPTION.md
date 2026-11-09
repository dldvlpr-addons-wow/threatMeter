<h1 style="text-align: center;"><span style="color: #0cf;">Forever</span> <span style="color: #ffd100;">Meter</span></h1>

<h3 style="text-align: center;"><strong>Threat, damage, healing and damage taken meter that keeps working in combat on WoW Forever.</strong></h3>

<h3 style="text-align: center;"><a href="https://muscalab.com/addons/forever-meter"><strong>🌐 Website</strong></a> · <a href="https://github.com/dldvlpr-addons-wow/threatMeter/tree/main/wiki"><strong>📖 Wiki</strong></a> · <a href="https://github.com/dldvlpr-addons-wow/threatMeter/issues"><strong>🐞 Report a bug</strong></a></h3>

***

## <span style="color: #ff6b35;">📊 10 modes in one window</span>

<p style="text-align: center;"><strong><span style="color: #f44336;">Threat</span> · <span style="color: #ff9800;">Damage</span> · <span style="color: #4caf50;">Healing</span> · <span style="color: #ffffff;">Absorbs</span> · <span style="color: #ff6b35;">Damage taken</span> · <span style="color: #ffd100;">Enemy damage taken</span> · <span style="color: #f44336;">Avoidable damage taken</span> · <span style="color: #3FC7EB;">Interrupts</span> · <span style="color: #8788EE;">Dispels</span> · <span style="color: #aaaaaa;">Deaths</span></strong></p>

Click <span style="color: #ffd100;"><strong>Menu</strong></span> or right-click the title to pick a mode and a session: current fight, overall, or any fight kept by the game.

***

## <span style="color: #3c3;">🆕 New in 1.16 and 1.17</span>

### <span style="color: #0cf;">1.17</span>

- <span style="color: #ffd100;"><strong>Report to any channel:</strong></span> `/fm report 5 guild`, `say`, `party`, `raid`, `instance` or `whisper <name>`. In a dungeon finder group, the report goes to instance chat by default. Works for death recaps too.
- <span style="color: #ffd100;"><strong>Themes:</strong></span> `classic`, `flat`, `glass` and `compact` set texture, font, bar height and opacity in one click.
- <span style="color: #ffd100;"><strong>Minimize a window</strong></span> to its title bar with the button left of the gear. Click again to restore it.
- <span style="color: #ffd100;"><strong>Hide outside instances:</strong></span> windows show again when you enter a dungeon, raid or battleground.
- <span style="color: #ffd100;"><strong>Threat first:</strong></span> threat leads the Display menu and mode cycling.
- <span style="color: #ffd100;"><strong>New commands:</strong></span> `/fm mode <mode> [N]`, `/fm theme`, `/fm rowheight`, `/fm bgalpha`, `/fm autohide`, `/fm instanceonly`, `/fm autoreset`.

### <span style="color: #0cf;">1.16</span>

- <span style="color: #ffd100;"><strong>Avoidable and deadly spells</strong></span> marked in the damage taken breakdown, tooltip and report.
- <span style="color: #ffd100;"><strong>Death recap to chat:</strong></span> shift-click a death, or `/fm report death [N]`.
- <span style="color: #ffd100;"><strong>Settings export and import:</strong></span> `/fm export`, `/fm import`, or the options panel. An invalid string changes nothing.
- <span style="color: #ffd100;"><strong>Boss filter</strong></span> for enemy damage taken, and <span style="color: #ffd100;"><strong>bar colour</strong></span> per window.

Full list in the **Files** tab.

***

## <span style="color: #0cf;">🚀 Quick start</span>

1. **Install** ForeverMeter, then <span style="color: #ff9800;"><strong>restart the game</strong></span> the first time. New textures and fonts load only at startup, so `/reload` is not enough.
2. A window opens on login. Click <span style="color: #ffd100;"><strong>Menu</strong></span> or right-click the title to pick a mode and a session.
3. **Make it yours:** click the gear in the title bar, or type <span style="color: #ffd100;"><strong>/fm options</strong></span>. Type <span style="color: #ffd100;"><strong>/fm</strong></span> for the full command list.

***

## <span style="color: #0cf;">⚡ Why ForeverMeter?</span>

WoW Forever looks like Classic, but it runs on the **modern game engine**. That engine forbids the combat log to addons, so meters built on it stay empty. **ForeverMeter** reads Blizzard's own server-side meter (`C_DamageMeter`) and the game's threat API instead.

- <span style="color: #3c3;"><strong>✔ Bars update in combat,</strong></span> for every mode.
- <span style="color: #3c3;"><strong>✔ Threat against bosses:</strong></span> when the game hides the numbers, each bar shows your threat status (aggro, insecure aggro, above the tank).
- <span style="color: #3c3;"><strong>✔ Pure Lua,</strong></span> no libraries required.

***

## <span style="color: #0cf;">🧰 What you get</span>

- <span style="color: #ffd100;"><strong>Threat warning,</strong></span> visual and sound, above an adjustable threshold. No sound when MuscaUI already warns.
- <span style="color: #ffd100;"><strong>Up to 4 windows,</strong></span> each with its own mode, session, size, lock and bar colour. Windows snap to each other.
- <span style="color: #ffd100;"><strong>Per-spell breakdown</strong></span> on click, top 5 spells on hover, spell-by-spell comparison of two players.
- <span style="color: #ffd100;"><strong>Death recap:</strong></span> time of death and last hits taken.
- <span style="color: #ffd100;"><strong>Your own bar always shown,</strong></span> with your real rank, even below the visible rows.
- <span style="color: #ffd100;"><strong>Per-window display:</strong></span> DPS, bar text, my bar only, no title bar, big number (a plain DPS counter).
- <span style="color: #ffd100;"><strong>Chat report</strong></span> and <span style="color: #ffd100;"><strong>copy as text</strong></span> for Discord.
- <span style="color: #ffd100;"><strong>Options panel:</strong></span> themes, bar textures, six bundled fonts, LibSharedMedia support, text columns, bar height, background opacity, scale.
- <span style="color: #ffd100;"><strong>Automation:</strong></span> show only in combat or in a group, hide outside instances, reset on a new instance or group.
- Key bindings, addon compartment button, test mode (`/fm test`).
- <span style="color: #ffd100;"><strong>11 languages:</strong></span> enUS, frFR, deDE, esES, esMX, itIT, ptBR, ruRU, koKR, zhCN, zhTW.

***

## <span style="color: #0cf;">🎯 Limits</span>

### <span style="color: #ff9800;">⚠ Works, with limits</span>

- In combat, names and amounts are "secret values": the game lets addons show them, not compare or add them. Bars keep the game's order. Percentages, the breakdown and the comparison fill in once combat ends.
- Threat against some enemies (bosses especially) is secret in combat: bars show the threat status without numbers.
- A report line with a name hidden by the game cannot be sent: the whole report then stays in your own chat window.

### <span style="color: #f44336;">✖ Does not work</span>

- When the game hides the threat status too, the window says "unavailable" instead of showing a wrong number.
- The options panel cannot open during combat: it opens as soon as combat ends.

***

## <span style="color: #ff6b35;">🔄 Updating from an older version</span>

Install the latest version, then `/reload`. Your windows and settings are kept. If a texture or font looks missing, restart the game.

- <span style="color: #ffd100;"><strong>Skipped a version?</strong></span> Read the [changelog](https://github.com/dldvlpr-addons-wow/threatMeter/blob/main/CHANGELOG.md) of each version you skipped.
- <span style="color: #ffd100;"><strong>Lua errors, or a window no longer behaves as before?</strong></span> Install the previous version again from the **Files** tab, and report it on GitHub or CurseForge with the text of the error.

***

## <span style="color: #0cf;">⚖ License and credits</span>

- **ForeverMeter** © 2026 dldvlpr, released under the [GNU General Public License v3 or later](https://github.com/dldvlpr-addons-wow/threatMeter/blob/main/LICENSE). Full source: [github.com/dldvlpr-addons-wow/threatMeter](https://github.com/dldvlpr-addons-wow/threatMeter).
- **Bundled fonts** are under the SIL Open Font License 1.1.
- **No warranty.** This addon is provided as is, without warranty of any kind, as stated in the GPL v3.
- Not affiliated with or endorsed by Blizzard Entertainment. World of Warcraft and WoW Forever are trademarks of Blizzard Entertainment, Inc.
