# StatusArc Icon Specification

The menu-bar icon has three information zones.

## 1. Battery — top arc

The top half-arc represents battery percentage.

- The active track length equals the exact current battery percentage.
- Low battery means a displayed, rounded integer percentage of 25% or below, or an early/final warning from `IOPSGetBatteryWarningLevel()`.
- Low battery: system red active track and dim red remainder.
- Otherwise, Low Power Mode: system yellow active track and dim yellow remainder.
- Otherwise: normal menu-bar foreground and dim neutral remainder.
- Low-battery urgency takes precedence over Low Power Mode, including while charging.
- Charging does not recolor the arc.

A small accessory sits immediately to the right of the composite icon:

- Charging: `bolt.fill` in normal semantic foreground.
- Otherwise, low battery: `exclamationmark` in system red.
- Otherwise: empty.

The bolt takes precedence over the attention mark. Accessories do not animate.
Use semantic macOS colors and reduced alpha for dim colors. Language and
network indicators retain their normal semantic foreground independently of
battery state. Keep the rendered image non-template to preserve these colors.

## 2. Input source — center

Display a concise two-letter code for the active input source.

Examples: `EN`, `UA`, `DE`.

Ukrainian is intentionally displayed as `UA` for this project's UI convention.

The text should remain visually centered and readable at normal menu-bar size.

## 3. Network — bottom

Wi-Fi uses exactly three dots:

- `● ● ●` strong
- `● ● ○` medium
- `● ○ ○` weak
- `○ ○ ○` disconnected

Current RSSI thresholds:

- 3 dots: RSSI >= -60 dBm
- 2 dots: RSSI >= -72 dBm
- 1 dot: associated signal below -72 dBm
- 0 dots: Wi-Fi off or no usable association

Ethernet/LAN uses one centered solid horizontal line roughly matching the total
visual width of the three Wi-Fi dots.

Other active non-Wi-Fi primary interfaces currently use the same solid line.

## Layout intent

Use one fixed 40-point status item with a 38 × 22-point image. Preserve the
original 30 × 22-point composite region at the left. Permanently reserve the
rightmost 8 points for the accessory, even when empty. Center each symbol in
an 8 × 12-point box at (30, 5), preserving its aspect ratio.

The battery, language, and network geometry stays fixed. Changes between no
accessory, attention mark, and bolt must not resize the status item or move
neighboring menu-bar items.
