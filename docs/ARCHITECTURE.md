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
standard AppKit `NSMenu` and `NSMenuItem` submenus for Battery, Connectivity,
and Input Source. Their content must follow the corresponding system menus. Any
bespoke menu surface requires a documented reason that a native menu or action
is insufficient.

The public menu API also does not expose Apple's embedded Wi-Fi toggle row or
the trailing details button from the system status menu. On macOS 13, StatusArc
uses standard command items (`Turn Wi-Fi On` / `Turn Wi-Fi Off`) and exposes
connection details when the combined menu is opened with Option held. This
keeps standard menu keyboard and accessibility behavior without a custom-drawn
menu row.

The compact network zone is required to remain exactly three dots for Wi-Fi.
When a Wi-Fi association has no usable Internet path, StatusArc therefore keeps
the signal dots and reports the warning in the standard menu, tooltip, and
accessibility value instead of replacing the zone with Apple's larger Wi-Fi
warning symbol.

CoreWLAN exposes scanning and association APIs but no public system-owned join
dialog. StatusArc uses `NSAlert`, labeled AppKit fields, a system pop-up button,
and a system checkbox for hidden-network and password entry. Enterprise/802.1X
networks are sent to Wi-Fi Settings because the system UI owns their identities,
certificates, and managed credential flow.

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
- Internet-path availability through Network.framework;
- current keyboard input source through Text Input Source Services.

The input source snapshot includes its complete native localized name and the
public identity artwork supplied by Text Input Source Services. Some built-in
layouts expose only the documented legacy IconRef, so the renderer supports
that compatibility fallback as well as the preferred image URL.

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
- native input-source identity artwork;
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

Appearance changes are observed through the status button's public effective
appearance so semantic colors redraw immediately.

A 60-second fallback refresh recovers from any notification that a framework or
OS release fails to deliver. Opening the menu also reads a fresh snapshot.
