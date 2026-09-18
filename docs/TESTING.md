# Manual Test Plan

StatusArc interacts with hardware and macOS system services, so the current test
plan is primarily manual.

## Native behavior parity

For every battery, Wi-Fi, or input-source change, compare StatusArc with the
corresponding macOS control on the same system. Verify clicks, toggles, menu
states, disabled states, transitions, feedback, timing, cancellation, errors,
and permission outcomes. Change the underlying state both inside and outside
StatusArc and confirm the UI follows macOS without stale or contradictory
states.

For every custom panel or dialog, record why a public system menu or action
cannot perform the task. Confirm the fallback uses standard SwiftUI/AppKit
control behavior, keyboard navigation, accessibility, and enabled states.

## Build and launch

- Build the `StatusArc` target.
- Launch it.
- Confirm there is no Dock icon.
- Confirm exactly one StatusArc item appears in the menu bar.
- Confirm clicking the item opens three compact component islands.

## Battery

- Confirm the arc roughly matches the current percentage.
- Confirm the split track leaves a clear top gap around every indicator.
- Confirm the unused arc is dimmed.
- Confirm the Battery island reports percentage and charging/fully charged
  state without a disclosure chevron.
- Confirm clicking the Battery island does not expand it or open a submenu.
- Inject synthetic snapshots in a development harness to validate the following matrix without changing system power settings:

| Percentage | Low Power Mode | macOS warning | Power state | Expected arc / top indicator |
| --- | --- | --- | --- | --- |
| 80% | off | none | battery | split normal / `80` |
| 26% | off | none | battery | split normal / `26` |
| 25% | off | none | battery | split normal / `25` |
| 10% | off | none | battery | split normal / `10` |
| 80% | on | none | battery | split yellow / `80` |
| 20% | on | none | battery | split yellow / `20` |
| 30% | off | early | battery | split red / `30` |
| 30% | off | final | battery | split red / `30` |
| 80% | off | none | charging | split normal / bolt |
| 20% | off | none | charging | split normal / bolt |
| 80% | on | none | charging | split yellow / bolt |
| 20% | on | none | charging | split yellow / bolt |
| 30% | off and on | early and final | charging | split red / bolt |
| 80% | off | none | socket, not charging | split normal / plug |
| 100% | off | none | fully charged | split normal / plug |

Confirm battery percentages use 7-point rounded regular type, zero letter spacing,
and fit at 100% without touching either arc cap. At 100%, confirm battery power
shows `100` while connected external power shows the plug.
External power with charging paused, charging complete, or the battery otherwise
not charging must show a compact plug and an accurate panel label rather than
claiming active charging.

- Check that percentage alone never triggers a warning: 25.49% displays 25%, 25.50% displays 26%, and neither is urgent without a system warning. Also check 0% and 10% with no warning.
- Confirm early/final macOS warnings show a red arc without a dot, including with Low Power Mode enabled.
- Confirm the unused arc is dim neutral, dim red, or dim yellow to match its state.
- Confirm language and network colors remain independent of battery colors.
- Check 0%, 100%, unavailable battery, and fully charged snapshots.
- Check both light and dark appearances at normal size and Retina scale.
- Switch repeatedly among battery, charging, and external-power states. The
  image and native item must remain 24 × 22 points, and neighboring menu-bar
  items must not move.
- Confirm the top number or bolt remains centered inside the split-arc gap and
  does not collide with the arc at 0%, 100%, or increased-contrast widths.
- Confirm the visible charging bolt matches the 2 × 4-point Figma mark; do
  not judge its size from the larger padded SF Symbol image bounds.
- Confirm the button never automatically scales or squeezes the artwork.
- Check transitions with the menu open and after wake; confirm the final icon matches the reported charging/warning state.
- Confirm this change adds no system-state polling or permission requests.

## Wi-Fi

- With Wi-Fi connected, confirm 1–3 dots are shown.
- Move between stronger/weaker signal conditions if practical.
- Turn Wi-Fi off from StatusArc and confirm the indicator becomes disconnected.
- Turn Wi-Fi back on.
- Scan nearby networks.
- If prompted, test both granting and denying Location access.
- Join an open network if one is safely available.
- Join a secured personal network.
- Confirm a secured-network join does not show a System keychain administrator prompt.
- If no user-keychain password is available, confirm StatusArc asks for the Wi-Fi password.
- Confirm no password is printed to the Xcode console.
- Confirm the hidden-network dialog labels Network Name, Security, and Password;
  disables Join until a name is entered; and supports Show Password.
- Confirm scans group the current, known, and other networks without truncating results.
- While scanning, connecting, disconnecting, and toggling power, confirm duplicate
  actions are disabled and the panel reports the transient state.
- Check Wi-Fi off, Wi-Fi on but disconnected, and a local connection without an
  Internet path; confirm the panel and accessibility value distinguish them.
- Option-open StatusArc and inspect Connection Details. Confirm IP address,
  router, band, protocol, security, radio values, and Wireless Diagnostics.

## Ethernet/LAN

- Connect Ethernet or a LAN adapter.
- Confirm macOS makes it the primary path when expected.
- Confirm the bottom dots switch to a solid line.
- Disconnect Ethernet and confirm StatusArc returns to the active Wi-Fi state.
- Make a VPN or tunnel interface primary and confirm StatusArc continues to
  identify the active physical connection carrying it in expanded text, while
  `VPN` replaces the dots or line in the compact icon. Confirm the panel, menu,
  tooltip, and accessibility value name the VPN, and disconnecting it restores
  the physical Wi-Fi or Ethernet indicator without changing item width.
- Repeat with a Network Extension packet tunnel whose primary route is `utun`,
  `ppp`, or `ipsec` but has no legacy VPN service record. Confirm the generic
  `VPN` state appears without exposing the interface name as VPN details.
- Confirm `VPN` uses lowered 6-point rounded regular type with clearly visible letter spacing
  and stays optically centered in the bottom gap.

## Input sources

- Configure at least two input sources in macOS.
- Switch them using StatusArc.
- Confirm the center label updates to match the current macOS input source.
- Confirm one- and two-letter labels both use 9.5-point rounded bold type, have matching
  optical vertical alignment, and remain readable at normal menu-bar size.
- Confirm ASCII sources use a compact system-name label and non-ASCII sources
  use the native language name rather than a fixed country-code mapping.
- Confirm each input-source row, the island header, tooltip, and accessibility
  value use the source's full localized system name.
- Switch using the macOS keyboard shortcut and confirm StatusArc follows.
- Open Emoji & Symbols.
- Confirm Keyboard Viewer opens when Text Input Source Services exposes it and
  appears disabled otherwise.
- Open the input-source-name and Keyboard Settings destinations.

## Expanded panel

- Confirm the collapsed panel shows exactly three islands: Battery,
  Connectivity, and Input Source.
- Open Connectivity and Input Source, then switch directly between them.
  Confirm the prior island contracts while the next expands without
  pointer-tracking delay. Battery must remain non-expandable.
- Compare content, controls, and enabled states with the corresponding macOS
  component panels.
- Confirm Connectivity contains a working system toggle, nearby and known
  networks, and Network and Wi-Fi Settings destinations.
- Confirm Battery shows its percentage and power state without Energy Mode
  controls, administrator prompts, or registering a new Login Items entry.
- Confirm Battery's passive icon has a dimmed backing and the Battery island
  does not react on hover. Connectivity and Input Source should show subtle
  hover feedback because they expand.
- In expanded islands, confirm collapsible headers, selectable networks and
  input sources, and available action rows highlight on hover. Current rows
  must remain visually still and use an accent-colored icon or badge on a
  white backing; unselected icons and badges use dimmed backings. Unavailable
  rows must remain visually still and use dimmed icon backings where present.
- On macOS 26 or later, confirm the islands use Liquid Glass and matched
  expansion transitions. On macOS 13–25, confirm they use semantic material
  with readable text and smooth state changes.
- Enable Reduce Motion and confirm islands change state without transition.
- Repeatedly expand, collapse, and switch islands; confirm the glass and content
  follow one continuous ease-out curve without window-edge jitter or clipping.
- Confirm clicking outside the panel, pressing Escape, or clicking the status
  item again dismisses it.
- Confirm Network Settings, Keyboard Settings, Emoji & Symbols, and Wireless
  Diagnostics invoke the available public system actions.
- Enable Launch at Login and confirm the item shows a checkmark and StatusArc is
  listed in System Settings → General → Login Items & Extensions. Sign out and
  back in, or restart the Mac, and confirm StatusArc starts automatically.
- Disable Launch at Login and confirm the checkmark and macOS Login Item are
  removed. If macOS requires approval, confirm the menu option opens the Login
  Items settings page.
- Confirm the panel uses only public SwiftUI/AppKit materials and controls.

## Settings shortcuts

Verify Network Settings and Keyboard Settings open without crashing StatusArc.

## Regression checks

After any visible rendering change, test both a light and dark menu-bar context
when possible.
- Enable Increase Contrast and confirm dim tracks remain legible.
- Enable Differentiate Without Color and confirm low battery and Low Power Mode
  remain distinguishable by arc weight and dash pattern.
