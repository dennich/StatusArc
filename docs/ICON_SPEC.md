# StatusArc Icon Specification

The menu-bar icon has three information zones.

## 1. Battery — top arc

The top half-arc represents battery percentage.

- The full track is always visible in a dimmed system color.
- The active track length equals the current battery percentage.
- Above 20% and not charging: normal menu-bar foreground.
- Charging: system green.
- Below 20% and above 10%: system yellow.
- 10% or below: system red.
- Charging takes precedence over the low/critical warning colors.

Examples:

- 100%: 100% active, 0% dim.
- 80%: 80% active, 20% dim.
- 80% while charging: 80% green, 20% dim.
- 19%: 19% yellow, 81% dim.
- 10%: 10% red, 90% dim.

Use semantic macOS colors so appearance remains appropriate across menu-bar
light/dark states.

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

The icon should not grow or shrink as state changes. The battery, language, and
network zones should stay in fixed positions so switching Wi-Fi/Ethernet or
input sources does not cause menu-bar jitter.
