# Commands

[Home](README.md) · [Getting Started](Getting-Started.md) · [Windows](Windows.md) · [Modes and Sessions](Modes-and-Sessions.md) · [Commands](Commands.md) · [FAQ](FAQ.md)

`/fm` and `/forevermeter` both work. Type `/fm` alone to see the help in game.

| Command | Effect |
|---|---|
| `/fm mode <mode> [N]` | Sets the mode of window N (the first by default): `threat`, `damage`, `heal`, `absorbs`, `taken`, `enemytaken`, `avoidable`, `interrupts`, `dispels`, `deaths` (`enemytaken` and `avoidable` only when the client provides them) |
| `/fm report [N] [channel]` | Sends the top N lines (5 by default) of the first window. Channel: `say` (in an instance only), `guild`, `party`, `raid`, `instance` or `whisper <name>`. Without a channel: instance chat in an instance group, else raid, party, or say in an instance; solo outside an instance, the lines are shown only to you. Right-click the breakdown title to report one player's top 5 spells |
| `/fm report death [N] [channel]` | Sends the death recap on line N (1 by default) of the first deaths window, same channels. Shift-click a death bar does the same |
| `/fm reset` | Clears the data |
| `/fm toggle` | Shows or hides the windows |
| `/fm lock` / `/fm unlock` | Locks or unlocks all windows |
| `/fm windows <1-4>` | Sets the number of windows |
| `/fm rows <n>` | Number of rows for all windows (1 to 40) |
| `/fm width <px>` | Width for all windows (150 to 600) |
| `/fm scale <x>` | Scale for all windows (0.5 to 2) |
| `/fm rowheight <n>` | Bar height (10 to 40) |
| `/fm bgalpha <x>` | Window background opacity (0 to 1, in steps of 0.05) |
| `/fm autohide` | Turns on or off: windows only in combat or in a group |
| `/fm instanceonly` | Turns on or off: windows hidden outside instances |
| `/fm autoreset` | Turns on or off: clear the data on entering an instance or joining a group |
| `/fm refresh <s>` | Refresh interval in seconds (0.05 to 2, default 0.2) |
| `/fm warn <%>` | Threat warning threshold (1 to 130, default 90) |
| `/fm sound` | Turns the threat warning sound on or off |
| `/fm pets` | Shows or hides pets in the threat list |
| `/fm test` | Turns test mode on or off: fake bars in the meter windows, to tune the look without a fight. Off again after a reload |
| `/fm lang [code]` | Forces a language (`enUS`, `frFR`, `deDE`, `esES`, `esMX`, `itIT`, `ptBR`, `ruRU`, `koKR`, `zhCN`, `zhTW`). `auto` goes back to the client language. No argument shows the current one. |
| `/fm options` | Opens the options panel (also `/fm config`) |
| `/fm theme [name]` | Theme: `classic`, `flat`, `glass`, `compact`. Sets texture, font, font size, bar height and background opacity at once. On Korean and Chinese clients the font is kept. No argument shows the current theme and lists them. |
| `/fm texture [name]` | Bar texture: `blizzard`, `flat`, `gradient`, `glass`, `striped`, `fade`, plus LibSharedMedia textures. No argument lists them. |
| `/fm font [name] [size]` | Bar font and size (6 to 24). `/fm font 12` changes the size only, `/fm font default` goes back to the game font. No argument lists the fonts. |
| `/fm defaults` | Resets all settings to their default values |
| `/fm export` | Shows your settings as a text string to copy |
| `/fm import` | Opens a box to paste a settings string. The string is checked in full first; an invalid string changes nothing |
| `/fm debug` | Prints raw `C_DamageMeter` values, to diagnose a display issue |

Key bindings (Options → Key Bindings → ForeverMeter, no key by default): show or hide the windows, reset the data, next mode of the first window.

`report` and `debug` apply to the first window, `mode` too unless a window number follows. Set the other windows from their own menu.
