# ForeverMeter

## Unreleased

### New
- **Auto show** (option): windows show in combat or in a group, and hide 10 s after a solo fight.
- **Bar text columns** (options panel): total, per second and percent can each be shown or hidden.
  In combat the percent is never shown, as the amounts are secret.
- **Chat report from the breakdown**: right-click the breakdown title to send that player's top 5 spells
  to raid, party or say. With a comparison open, the compared lines (`12.3k | 9.8k (+26%)`) are sent. Out of combat only.
- **Bar height** (options panel): slider from 10 to 40 px. Windows keep their number of rows.
- **Background opacity** (options panel): slider from 0 (transparent) to 1, for the meter windows and the breakdown.

### Fixed
- Chat report: a line holding a secret name (creature session in an instance) is shown locally instead of raising.

## 1.5.0

### New
- **Options panel**: Options → AddOns → ForeverMeter, `/fm options`, or **Options** in a window menu.
  Bar texture, font, font size, language, scale, refresh interval, threat warning threshold, warning sound,
  pets in threat view, window lock, and a reset button.
- **Bar textures**: `blizzard` (default), `flat`, `gradient`, `glass`, `striped`, `fade`. `/fm texture <name>`.
- **Bar fonts**: six fonts shipped with the addon (Oswald, PT Sans Narrow, PT Sans Narrow Bold, Fira Sans,
  Fira Sans Condensed, Fira Mono; SIL Open Font License, see `Media/Fonts/OFL.txt`) plus the game fonts.
  `/fm font <name> [size]`, `/fm font default` goes back to the game font.
- Textures and fonts registered by other addons through LibSharedMedia are listed too, when one of them loads it.
- **Compare two players**: with the breakdown open, Shift-click another bar of the same window to compare
  both sources spell by spell (`12.3k | 9.8k (+26%)`). Out of combat only: other players' data is secret in combat.
- **New modes**: enemy damage taken and avoidable damage taken, shown only when the client provides these meter types.
- **Resize grip in the bottom-left corner**, in addition to the bottom-right one.
- Bars fill with an animation.

### Changed
- **New window**: takes the size and lock state of the window it was created from, and attaches to the first free
  side (below, right, above, left) without going off screen or covering another window.
- **Breakdown panel**: now a separate panel drawn above the meter windows. Drag its title to move it; its position
  is kept. Until moved, it opens on a free side of its window.
- Current fight title no longer shows a timer out of combat (the client keeps counting after the fight ends).

### Fixed
- A new font now shows right away, without switching modes, and on its first use.

**Note:** new texture and font files are only picked up after restarting the game, not with `/reload`.
