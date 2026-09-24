# Modes and Sessions

## Modes
| Mode | Shows |
|---|---|
| `damage` | Damage done |
| `heal` | Healing done |
| `absorbs` | Damage absorbed by shields |
| `taken` | Damage taken. The breakdown shows which creature cast each spell. |
| `interrupts` | Interrupts |
| `dispels` | Dispels |
| `deaths` | Deaths. The bar shows the time of death; hover it for the last hits taken. |
| `threat` | Group threat on your current hostile target. The tank's bar is red. |

Each bar shows the specialization icon when the client provides one, the class icon otherwise.
`/fm pets` shows or hides pets in the threat list.

## Sessions
- **Current**: the fight in progress, or the last one.
- **Overall**: everything since the last reset.
- Any past fight still kept by the client.

## Threat warning
When your threat goes above the threshold (90% by default), your bar glows and a sound plays.
- `/fm warn <%>` sets the threshold (1 to 130).
- `/fm sound` turns the sound on or off.
