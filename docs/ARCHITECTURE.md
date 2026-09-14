# Architecture

StatusArc is intentionally small and uses native macOS frameworks.

## Native behavior baseline

The corresponding macOS control defines the expected behavior for battery,
Wi-Fi, and keyboard input features. StatusArc mirrors its observable visuals,
interaction states, transitions, timing, feedback, edge cases, and response to
external system-state changes using public APIs. A custom interaction model is
used only when macOS has no established behavior for the feature.

## Menu integration policy

StatusArc invokes public system actions and destinations instead of recreating
them. Examples include the Character Palette, System Settings panes, and
Wireless Diagnostics.

macOS does not provide a public API for a third-party app to present, embed, or
combine Apple's Battery, Wi-Fi, and Input status menus. StatusArc therefore uses
the standard AppKit `NSMenu` and `NSMenuItem` implementation for its combined
menu. Its content must follow the corresponding system menus, and any bespoke
menu surface requires a documented reason that a native menu or action is
insufficient.

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
- optional retrieval of a saved Wi-Fi password from the user keychain through CoreWLAN;
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

StatusArc refreshes from public system notifications:

- IOKit power-source changes;
- CoreWLAN power, SSID, link, quality, and scan-cache changes;
- System Configuration primary-route changes;
- Text Input Source selection and enabled-source changes;
- wake and accessibility-display-option changes.

A 60-second fallback refresh recovers from any notification that a framework or
OS release fails to deliver. Opening the menu also reads a fresh snapshot.
