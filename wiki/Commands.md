# Commands

[Home](README.md) · [Getting Started](Getting-Started.md) · [Windows](Windows.md) · [Modes and Sessions](Modes-and-Sessions.md) · [Commands](Commands.md) · [FAQ](FAQ.md)

`/fm` and `/forevermeter` both work. Type `/fm` alone to see the help in game.

| Command | Effect |
|---|---|
| `/fm mode <mode>` | Sets the mode of the first window: `damage`, `heal`, `absorbs`, `taken`, `enemytaken`, `avoidable`, `interrupts`, `dispels`, `deaths`, `threat` (`enemytaken` and `avoidable` only when the client provides them) |
| `/fm report [N]` | Sends the top N lines (5 by default) of the first window to raid, party or say |
| `/fm reset` | Clears the data |
| `/fm toggle` | Shows or hides the windows |
| `/fm lock` / `/fm unlock` | Locks or unlocks all windows |
| `/fm windows <1-4>` | Sets the number of windows |
| `/fm rows <n>` | Number of rows for all windows (1 to 40) |
| `/fm width <px>` | Width for all windows (150 to 600) |
| `/fm scale <x>` | Scale for all windows (0.5 to 2) |
| `/fm refresh <s>` | Refresh interval in seconds (0.05 to 2, default 0.2) |
| `/fm warn <%>` | Threat warning threshold (1 to 130, default 90) |
| `/fm sound` | Turns the threat warning sound on or off |
| `/fm pets` | Shows or hides pets in the threat list |
| `/fm lang [code]` | Forces a language (`enUS`, `frFR`, `deDE`, `esES`, `esMX`, `itIT`, `ptBR`, `ruRU`, `koKR`, `zhCN`, `zhTW`). `auto` goes back to the client language. No argument shows the current one. |
| `/fm options` | Opens the options panel (also `/fm config`) |
| `/fm texture [name]` | Bar texture: `blizzard`, `flat`, `gradient`, `glass`, `striped`, `fade`, plus LibSharedMedia textures. No argument lists them. |
| `/fm font [name] [size]` | Bar font and size (6 to 24). `/fm font 12` changes the size only, `/fm font default` goes back to the game font. No argument lists the fonts. |
| `/fm defaults` | Resets all settings to their default values |
| `/fm debug` | Prints raw `C_DamageMeter` values, to diagnose a display issue |

`mode`, `report` and `debug` apply to the first window. Set the other windows from their own menu.
