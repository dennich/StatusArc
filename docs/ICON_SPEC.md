# StatusArc Icon Specification

The menu-bar icon has three information zones.

## 1. Battery — top arc

The top arc represents battery percentage while leaving a centered gap for the
bottom network indicator.

- On battery power, show the rounded battery percentage without a percent sign.
  Use 8-point rounded bold type with zero letter spacing. A full battery that
  remains on battery power still shows `100`; external power state, rather than
  percentage alone, determines whether the plug appears.
- While actively charging, show a `bolt.fill` whose visible mark matches the
  2 × 4-point Figma vector.
- When connected to socket power but not charging, including when fully
  charged, show a compact vertical filled plug that stays clear of the input
  label.
- Keep a wide top gap around every indicator so rounded arc caps never overlap
  the number or symbol.
- Across the two 55-degree segments of the split arc, the combined active track
  length still equals the exact battery percentage.

- The active track length equals the exact current battery percentage.
- Low battery means an early/final warning from `IOPSGetBatteryWarningLevel()`.
- No custom battery percentage threshold is applied.
- Low battery: system red active track and dim red remainder.
- Otherwise, Low Power Mode: system yellow active track and dim yellow remainder.
- Otherwise: normal menu-bar foreground and dim neutral remainder.
- Low-battery urgency takes precedence over Low Power Mode, including while charging.
- Charging does not recolor the arc.

Low-battery warnings affect only the arc; no warning dot is drawn. Power-state
changes stay inside the fixed composite frame and do not move neighboring
menu-bar items.
Use semantic macOS colors and reduced alpha for dim colors. Language and
network indicators retain their normal semantic foreground independently of
battery state. Keep the rendered image non-template to preserve these colors.
Increase Contrast strengthens dim tracks. With Differentiate Without Color,
low-battery warnings use a heavier arc and Low Power Mode uses a dashed arc so
the state never depends on red or yellow alone. The arc radius does not change.

## 2. Input source — center

Use a compact label derived from public Text Input Source metadata. ASCII input
sources use the first letter of their localized system name. Other sources use
up to two letters from the language's native name, so Ukrainian appears as `УК`
rather than a custom country code. The label is variable-length and is not
governed by an exactly-two-letters rule.

The menu, tooltip, and accessibility value use the complete localized system
source name from `kTISPropertyLocalizedName`. Keep the compact label visually
centered and readable at normal menu-bar size. Both one- and two-letter labels
use 9.5-point rounded bold type. Center the visible glyph outlines on the
composite icon's vertical axis so the labels do not shift.

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

An associated Wi-Fi network without a usable Internet path retains its three
radio-strength dots because this compact zone is constrained to exactly three
dots. The standard menu and accessibility value explicitly report “No Internet
Connection.” This is the documented composite-icon exception to Apple's larger
Wi-Fi warning glyph.

Ethernet/LAN uses one centered solid horizontal line roughly matching the total
visual width of the three Wi-Fi dots.

Other active non-Wi-Fi primary interfaces use three dim dots so StatusArc does
not misidentify VPN, tunnel, or virtual adapters as Ethernet. Their exact
interface identity remains available in the menu and accessibility text.

When an active VPN service or packet-tunnel interface owns the default route,
`VPN` replaces the physical Wi-Fi dots or Ethernet line in the bottom zone. The
underlying physical connection remains available in the menu, panel, tooltip,
and accessibility value. Include the VPN service name when macOS provides one;
otherwise show only the generic VPN state. The lowered 6-point rounded bold label uses
0.5-point letter spacing and the normal semantic foreground. It is optically
centered in the bottom gap and does not change the status-item width.

## Layout intent

Use one fixed 24 × 22-point image and status item. Preserve the 30 × 22-point
composite coordinate space with a 10-point arc radius while trimming its
transparent left inset and unused outer padding. Keep the network dots and
Ethernet line low in the bottom gap. The status button uses no image scaling,
and all battery, input-source, and network states keep the same external frame.
