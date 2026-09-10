# Architecture

StatusArc is intentionally small and uses native macOS frameworks.

## `main.swift`

Starts `NSApplication`, installs `AppDelegate`, and runs as an accessory app.

## `AppDelegate.swift`

Owns the `NSStatusItem`, menu hierarchy, refresh timer, and user interaction.
It turns the current system snapshot into menu text and dispatches explicit
actions to `SystemActions`.

## `SystemStatusMonitor.swift`

Reads passive system state:

- battery and charging state through IOKit;
- primary network interface through SystemConfiguration;
- Wi-Fi RSSI through CoreWLAN;
- current keyboard input source through Text Input Source Services.

It returns a `StatusSnapshot` used by both the renderer and menu.

## `SystemActions.swift`

Contains user-triggered actions:

- Wi-Fi power, scan, disconnect, and association;
- optional retrieval of a saved Wi-Fi password through CoreWLAN keychain APIs;
- input-source enumeration and selection;
- local connection details.

Keeping these actions separate from passive monitoring helps make permission and
privacy impact easier to review.

## `StatusIconRenderer.swift`

Draws the fixed-size menu-bar image using AppKit/Core Graphics:

- battery arc;
- input-source label;
- Wi-Fi dots or Ethernet line.

The image is not marked as a template image because the battery arc needs
semantic green/yellow/red colors.

## Refresh model

StatusArc currently refreshes once per second. This favors implementation
simplicity and immediate input-source/network feedback. Future work could
replace some polling with system notifications if it reduces overhead without
making the code fragile.
