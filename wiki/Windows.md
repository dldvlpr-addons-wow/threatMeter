# Windows

## Several windows
You can open up to 4 windows. Each one keeps its own mode, session, position and size,
so you can show damage and healing side by side.

- Menu → **New window** / **Close this window**
- Or `/fm windows <1-4>`

## Snapping
- A new window attaches below the previous one.
- Drop a window against the edge of another one to snap it. It then follows that window's moves and size.
- Drag it away to detach it.

## Size
- Drag the grip in the bottom-right corner to change the width and the number of rows of that window.
- `/fm rows <n>` (1 to 40) and `/fm width <px>` (150 to 600) set a shared size for all windows and clear per-window sizes.
- `/fm scale <x>` (0.5 to 2) scales every window.

## Locking
- Click the padlock in the title bar to lock the position and size of that window only.
- `/fm lock` and `/fm unlock` apply to all windows.
