# StatusArc Icon Specification

The menu-bar icon is one fixed 22 × 22-point component with three information
zones. Its geometry follows the approved Figma state matrix.

## 1. Battery — adaptive arc and power dot

The battery track follows a 20 × 20-point ellipse centered in the component.
While draining, one continuous 240-degree, 1.5-point rounded arc runs from 210°
through the top to −30°, leaving only the bottom network opening. While external
power is connected, the track separates into two 90-degree side arcs from 210°
to 120° and from 60° to −30°, leaving room for the top power dot. The stroke is
inset so its outer radius is 10 points. The active length across the applicable
track equals the exact battery percentage; the remainder uses the same state
color at reduced opacity.

- Low battery: `NSColor.systemRed` active track and tinted red remainder.
- Otherwise, Low Power Mode: `NSColor.systemYellow` active track and tinted
  yellow remainder.
- Otherwise: `NSColor.labelColor` active track and a dimmed remainder derived
  from the same foreground color.
- Low-battery urgency takes precedence over Low Power Mode.

Low battery means an early/final warning from
`IOPSGetBatteryWarningLevel()`. No custom percentage threshold is applied.

A centered 4 × 4-point dot occupies x = 9, y = 0 in Figma's top-down
coordinate space only while external power is connected:

- battery power, including warning states: no top dot and one connected upper
  arc;
- external power below 100%, whether charging or paused: `NSColor.systemOrange`
  (the public macOS semantic amber used to match Apple's charge-cord behavior);
- charged while connected to external power: `NSColor.systemGreen`.

Use semantic macOS colors rather than fixed RGB values. Low-battery warnings
affect the arc, not the power dot. Increase Contrast strengthens dim tracks.
With Differentiate Without Color, low-battery warnings use a heavier arc and
Low Power Mode uses a dashed arc.

## 2. Input source — center

Use a compact label derived from public Text Input Source metadata. ASCII input
sources use the first letter of their localized system name. Other sources use
up to two letters from the language's native name, so Ukrainian appears as `УК`.

The menu, tooltip, and accessibility value use the complete localized system
source name from `kTISPropertyLocalizedName`. Draw the compact label in
8.5-point bold system type and center its visible glyph outline on both axes.

## 3. Network — bottom

Wi-Fi uses three fixed 3 × 3-point dots with 1.5 points between adjacent dots.
Their centers are at x = 6.5, 11, and 15.5 and y = 19.5 in Figma's top-down
22-point coordinate space:

- `● ● ●` strong
- `● ● ○` medium
- `● ○ ○` weak
- `○ ○ ○` disconnected or off

Current RSSI thresholds:

- 3 dots: RSSI >= -60 dBm
- 2 dots: RSSI >= -72 dBm
- 1 dot: associated signal below -72 dBm
- 0 dots: Wi-Fi off or no usable association

During a user-requested connection or network refresh, the dots remain fixed
and a bright phase travels across them every 0.18 seconds. Connecting travels
left to right; refreshing travels right to left. The timer exists only while
the operation is active. With Reduce Motion, all three dots use a static
mid-level tint and the tooltip/accessibility value carries the transient state.

An associated Wi-Fi network without a usable Internet path retains its radio
strength dots. The menu and accessibility value report “No Internet
Connection.”

Ethernet/LAN uses one centered 11 × 2-point visible rounded line at the same
vertical center as the dots. Its centerline runs from x = 6.5 to x = 15.5; the
2-point round caps extend the visible bounds to x = 5.5…16.5. Other active
non-Wi-Fi primary interfaces use three dim dots so StatusArc does not
misidentify tunnel or virtual adapters as Ethernet.

When an active VPN service or packet-tunnel interface owns the default route,
`VPN` replaces the physical indicator. It uses the exact flattened Union shape
from Figma rather than rendered text. Its bounds are x = 4, y = 17, width = 14,
and height = 4 points. A connecting or refreshing Wi-Fi operation temporarily
takes priority so its progress remains visible.

## Appearance and layout

The renderer resolves `labelColor`, `systemRed`, `systemYellow`, `systemOrange`,
and `systemGreen` against the status button's effective appearance. This creates
the white-on-dark and black-on-light variants without maintaining separate
assets. The image remains non-template so state colors survive.

The status button uses no image scaling. Battery, input-source, network, VPN,
and transient activity states all remain inside the same 22 × 22-point frame,
so neighboring menu-bar items never move.

## Application icon

The macOS application icon is supplied through `Assets.xcassets/AppIcon` at
every required 16–1024 px rendition. It uses a centered rounded tile with a
transparent square canvas, a simple split-arc glyph, a semantic green power
dot, and three network dots. Small renditions reduce decorative effects and
increase stroke weight for legibility. The generator keeps the source geometry
reproducible in `scripts/generate-app-icon.swift`.
