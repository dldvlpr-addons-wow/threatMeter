# Windows

[Home](README.md) · [Getting Started](Getting-Started.md) · [Windows](Windows.md) · [Modes and Sessions](Modes-and-Sessions.md) · [Commands](Commands.md) · [FAQ](FAQ.md)

## Several windows
You can open up to 4 windows. Each one keeps its own mode, session, position and size,
so you can show damage and healing side by side.

- Menu → **New window** / **Close this window**
- Or `/fm windows <1-4>`

A new window takes the size and lock state of the window it comes from. It attaches to the first free side
of that window (below, right, above, left), without going off screen or covering another window.
When there is no room, it opens near the center of the screen.

## DPS display and display options
- Menu → Display → **DPS**: damage with the per second value only. Choosing another display gives the window back the shared bar text.
- Bar text: the **Bar text** entries of a window menu (total, per second, percent) apply to that window only.
  The options panel sets the shared value, used by windows without their own (the DPS display sets its own).
- **My bar only**: one row, your own bar with your rank. The bottom grips then change the width only.
- **No title bar**: the window has no title. Right-click the window or a bar to open its menu.
  To move the window, turn the title bar back on first.
- **Big number**: your own value in large text, without bars (threat mode: your threat percent).
  Combine it with **DPS** and **No title bar** for a plain DPS counter.
- In combat, totals are abbreviated by the game (`12K`).

## Snapping
- Drop a window against the edge of another one to snap it. It then follows that window's moves and size.
- Drag it away to detach it.

## Size
- Drag the grip in the bottom-right or bottom-left corner to change the width and the number of rows of that window.
  With the left grip, the right edge stays in place.
- `/fm rows <n>` (1 to 40) and `/fm width <px>` (150 to 600) set a shared size for all windows and clear per-window sizes.
- `/fm scale <x>` (0.5 to 2) scales every window.
- When you rank below the visible rows, your bar takes the last row with your real rank. Not on a 1-row window.

## Breakdown panel
- Click a bar to open the per-spell breakdown of that player. It is a separate panel, drawn above the meter windows.
- Drag its title to move it. Its position is kept for the next time.
- Until you move it, it opens on a free side of its window.
- Shift-click another bar of the same window to compare both players spell by spell
  (`12.3k | 9.8k (+26%)`). Shift-click it again to stop. Out of combat only.
- Right-click its title to send that player's top 5 spells to raid, party or say (the compared lines when a comparison is open). Out of combat only.

## Locking
- Click the padlock in the title bar to lock the position and size of that window only.
- `/fm lock` and `/fm unlock` apply to all windows.
