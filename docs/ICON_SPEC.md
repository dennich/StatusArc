# StatusArc Icon Specification

The menu-bar icon has three information zones.

## 1. Battery — top arc

The top half-arc represents battery percentage.

- The active track length equals the exact current battery percentage.
- Low battery means an early/final warning from `IOPSGetBatteryWarningLevel()`.
- No custom battery percentage threshold is applied.
- Low battery: system red active track and dim red remainder.
- Otherwise, Low Power Mode: system yellow active track and dim yellow remainder.
- Otherwise: normal menu-bar foreground and dim neutral remainder.
- Low-battery urgency takes precedence over Low Power Mode, including while charging.
- Charging does not recolor the arc.

A small accessory sits immediately to the right of the composite icon:

- Charging: `bolt.fill` in normal semantic foreground.
- Connected to external power but paused, not charging, or fully charged:
  `powerplug.fill` in normal semantic foreground.
- Running on battery: empty.

Low-battery warnings affect only the arc; no warning dot is drawn. Accessory changes use a
180 ms ease-in-out transition: the composite shifts to its new center while
the old accessory fades out and the new one fades in. Reduce Motion disables
the transition. Unchanged states do not animate, and accessories never pulse.
Use semantic macOS colors and reduced alpha for dim colors. Language and
network indicators retain their normal semantic foreground independently of
battery state. Keep the rendered image non-template to preserve these colors.
Increase Contrast strengthens dim tracks. With Differentiate Without Color,
low-battery warnings use a heavier arc and Low Power Mode uses a dashed arc so
the state never depends on red or yellow alone. The arc radius does not change.

## 2. Input source — center

Display exactly two letters for the active input source. The code represents
the specific source where possible, rather than only its language, so layouts
that share a language remain distinguishable.

Examples include `US`, `GB`, `DV`, `UA`, and `DE`. Prefer a region or a stable
layout abbreviation from the system input-source identity, then fall back to
the two-letter language code. The menu,
tooltip, and accessibility value use the complete localized system source name.

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

## Layout intent

Use one dynamically sized status item and a 22-point-high image. Preserve the
original 30 × 22-point composite geometry, 11.1-point arc radius, and existing
internal spacing. Trim the original transparent left inset and unused outer padding:

- No accessory: 24-point image and item width.
- Charging bolt or external-power plug: 34-point image and item width. Fit the symbol within its
  original 8 × 12-point bounds without stretching; preserve its gap to the arc.

The image and native item widths change together during the 180 ms transition.
The accessory fades at the expanding or contracting edge. Icon artwork is never
scaled; the status button uses no image scaling. Accessories remain vertically
centered, and the arc, language, and network keep their relative geometry.
Neighboring menu-bar items move when the item expands or contracts. Reduce Motion
applies the final image and width immediately.
