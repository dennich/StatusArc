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

For every custom menu or dialog, record why a public system menu or action
cannot perform the task. Confirm the fallback uses standard AppKit menu and
control behavior, keyboard navigation, accessibility, and enabled states.

## Build and launch

- Build the `StatusArc` target.
- Launch it.
- Confirm there is no Dock icon.
- Confirm exactly one StatusArc item appears in the menu bar.
- Confirm clicking the item opens the menu.

## Battery

- Confirm the arc roughly matches the current percentage.
- Confirm the unused arc is dimmed.
- Confirm the menu reports battery percentage, charging/fully charged state, power source, and time remaining as before.
- Inject synthetic snapshots in a development harness to validate the following matrix without changing system power settings:

| Percentage | Low Power Mode | macOS warning | Charging | Expected arc / accessory |
| --- | --- | --- | --- | --- |
| 80% | off | none | no | normal / none |
| 26% | off | none | no | normal / none |
| 25% | off | none | no | normal / none |
| 10% | off | none | no | normal / none |
| 80% | on | none | no | yellow / none |
| 20% | on | none | no | yellow / none |
| 30% | off | early | no | red / none |
| 30% | off | final | no | red / none |
| 80% | off | none | yes | normal / bolt |
| 20% | off | none | yes | normal / bolt |
| 80% | on | none | yes | yellow / bolt |
| 20% | on | none | yes | yellow / bolt |
| 30% | off and on | early and final | yes | red / bolt |

Also confirm that external power with charging paused, charging complete, or
the battery otherwise not charging shows the plug accessory and an accurate
menu label rather than claiming active charging.

- Confirm the plug is vertical, slightly larger than before, and has comparable
  visual weight to the bolt without changing the arc radius or accessory gap.

- Check that percentage alone never triggers a warning: 25.49% displays 25%, 25.50% displays 26%, and neither is urgent without a system warning. Also check 0% and 10% with no warning.
- Confirm early/final macOS warnings show a red arc without a dot, including with Low Power Mode enabled.
- Confirm the unused arc is dim neutral, dim red, or dim yellow to match its state.
- Confirm language and network colors remain independent of battery colors.
- Check 0%, 100%, unavailable battery, and fully charged snapshots.
- Check both light and dark appearances at normal size and Retina scale.
- Switch repeatedly between no accessory and bolt: image and item widths must match at 24 and 34 points respectively, with a constant 22-point image height. A low-battery warning alone must not add a dot or widen the item. Neighboring items should move with expansion/contraction.
- Confirm icon sizes and internal spacing remain unchanged in every settled state and throughout resizing; check that no automatic image scaling squeezes the artwork.
- Confirm accessories stay outside the arc, remain vertically centered, and never pulse.
- Confirm bolt appearance and disappearance use one short, smooth shift/fade; unchanged state must not restart the animation.
- Enable Reduce Motion and confirm the image and item width reach their final state immediately without animated resizing or fading.
- Check transitions with the menu open and after wake; confirm the final icon matches the reported charging/warning state.
- Confirm this change adds no system-state polling or permission requests; animation frames run only during transitions.

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
  actions are disabled and the menu reports the transient state.
- Check Wi-Fi off, Wi-Fi on but disconnected, and a local connection without an
  Internet path; confirm the menu and accessibility value distinguish them.
- Option-open StatusArc and inspect Connection Details. Confirm IP address,
  router, band, protocol, security, radio values, and Wireless Diagnostics.

## Ethernet/LAN

- Connect Ethernet or a LAN adapter.
- Confirm macOS makes it the primary path when expected.
- Confirm the bottom dots switch to a solid line.
- Disconnect Ethernet and confirm StatusArc returns to the active Wi-Fi state.
- Make a VPN or tunnel interface primary and confirm StatusArc does not show the
  Ethernet line for it.

## Input sources

- Configure at least two input sources in macOS.
- Switch them using StatusArc.
- Confirm the center identity artwork updates to match the current macOS input source.
- Confirm StatusArc does not substitute a custom two-letter language or country code.
- Configure two sources for the same language and confirm their native artwork remains distinguishable when macOS supplies distinct artwork.
- Confirm each submenu item, the parent item, tooltip, and accessibility value use the source's full localized system name.
- Switch using the macOS keyboard shortcut and confirm StatusArc follows.
- Open Emoji & Symbols.
- Open Keyboard Settings.

## Menu structure

- Confirm the root menu exposes Battery, Connectivity, and Input Source as three
  standard keyboard-navigable submenus.
- Compare the content and enabled states with the corresponding macOS menus.
- Confirm Battery Settings, Network Settings, Keyboard Settings, Emoji &
  Symbols, and Wireless Diagnostics invoke the available public system actions.
- Confirm no custom view attempts to reproduce a Control Center panel.

## Settings shortcuts

Verify Battery Settings, Network Settings, and Keyboard Settings open without
crashing StatusArc.

## Regression checks

After any visible rendering change, test both a light and dark menu-bar context
when possible.
- Enable Increase Contrast and confirm dim tracks remain legible.
- Enable Differentiate Without Color and confirm low battery and Low Power Mode
  remain distinguishable by arc weight and dash pattern.
