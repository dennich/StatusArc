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
a SwiftUI-hosted panel containing one island for each component. On macOS 26
and later the islands use public `GlassEffectContainer`, `glassEffect`, and
matched glass transitions. Earlier supported versions use semantic system
material and ordinary matched animation. Reduce Motion disables transitions.
One shared cubic timing curve drives island layout. AppKit grows the transparent
hosting panel before expansion and delays contraction until SwiftUI completes,
so two layout engines never animate the same edge at once.
Compact and expanded islands are separate conditional views with the same glass
identity, allowing the system matched-glass transition to morph their geometry.

AppKit continues to own `NSStatusItem`, system lifecycle, actions, and dialogs.
On macOS 27 and later the panel participates in the public
`NSStatusItemExpandedInterfaceDelegate` lifecycle. Earlier releases toggle the
same panel from the status-bar button. This custom surface is necessary because
the system component panels cannot be invoked or embedded through public APIs.

Nearby-network scans remain explicit user actions. Async results update the
open Connectivity island without entering nested menu-tracking sessions.

The compact network zone is required to remain exactly three dots for Wi-Fi.
When a Wi-Fi association has no usable Internet path, StatusArc therefore keeps
the signal dots and reports the warning in the expanded panel, tooltip, and
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

Owns the `NSStatusItem`, refresh timer, panel bridge, and user interaction. It
turns the current system snapshot into panel data and dispatches explicit
actions to `SystemActions`.

## `StatusControlCenterModel.swift` and `StatusControlCenterView.swift`

Model and render the three component islands. Battery is a passive compact
status card; Connectivity and Input Source expand for controls. The model
contains no CoreWLAN or Text Input Source objects; stable row identifiers route
actions back through `AppDelegate`.

## `StatusPanelController.swift`

Hosts SwiftUI in a transient AppKit panel, anchors it below the status item,
tracks dynamic height, and handles outside-click and Escape dismissal. Builds
made with the macOS 27 SDK also adopt the native status-item expanded-interface
session; earlier SDK builds use the existing status-button action path.

## `LaunchAtLoginController.swift`

Uses `SMAppService.mainApp` to register or unregister the main StatusArc app as
a per-user Login Item. It does not install a helper, launch agent, or daemon.

## `SystemStatusMonitor.swift`

Reads passive system state:

- battery and charging state through IOKit;
- primary network interface through SystemConfiguration, falling back to the
  first active physical service when a VPN or tunnel owns the default route;
- Wi-Fi RSSI through CoreWLAN;
- Internet-path availability through Network.framework;
- current keyboard input source through Text Input Source Services.

The input source snapshot includes its complete native localized name and a
compact label derived from the source's public name, language, and ASCII-capable
properties. Apple does not expose the compact badge used by its own Input menu;
StatusArc therefore does not consume the unrelated legacy IconRef artwork.

It returns a `StatusSnapshot` used by both the renderer and expanded panel.

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
- compact input-source label derived from native metadata;
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
