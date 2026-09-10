# Manual Test Plan

StatusArc interacts with hardware and macOS system services, so the current test
plan is primarily manual.

## Build and launch

- Build the `StatusArc` target.
- Launch it.
- Confirm there is no Dock icon.
- Confirm exactly one StatusArc item appears in the menu bar.
- Confirm clicking the item opens the menu.

## Battery

- Confirm the arc roughly matches the current percentage.
- Confirm the unused arc is dimmed.
- Connect power and confirm the active arc becomes green.
- Confirm the menu reports battery percentage and power source.
- If macOS provides time remaining, confirm the menu value is plausible.

Low-battery yellow/red states can be tested naturally or by temporarily
injecting test values in development code.

## Wi-Fi

- With Wi-Fi connected, confirm 1–3 dots are shown.
- Move between stronger/weaker signal conditions if practical.
- Turn Wi-Fi off from StatusArc and confirm the indicator becomes disconnected.
- Turn Wi-Fi back on.
- Scan nearby networks.
- If prompted, test both granting and denying Location access.
- Join an open network if one is safely available.
- Join a secured personal network.
- Confirm no password is printed to the Xcode console.
- Open Connection Details and Wireless Diagnostics.

## Ethernet/LAN

- Connect Ethernet or a LAN adapter.
- Confirm macOS makes it the primary path when expected.
- Confirm the bottom dots switch to a solid line.
- Disconnect Ethernet and confirm StatusArc returns to the active Wi-Fi state.

## Input sources

- Configure at least two input sources in macOS.
- Switch them using StatusArc.
- Confirm the center code updates.
- Switch using the macOS keyboard shortcut and confirm StatusArc follows.
- Open Emoji & Symbols.
- Open Keyboard Settings.

## Settings shortcuts

Verify Battery Settings, Network Settings, and Keyboard Settings open without
crashing StatusArc.

## Regression checks

After any visible rendering change, test both a light and dark menu-bar context
when possible.
