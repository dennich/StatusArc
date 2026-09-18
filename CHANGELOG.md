# Changelog

All notable user-visible changes to StatusArc are documented here.

## [Unreleased]

## [1.3.1] - 2026-09-18

### Added
- Active VPN connections now replace the compact dots or line with a clear `VPN` label and include the VPN service name in connectivity text when macOS provides one.

### Fixed
- When a VPN owns the default route, StatusArc now resolves the active physical Wi-Fi or Ethernet connection carrying it instead of treating the tunnel as a disconnected network.

## [1.3.0] - 2026-09-17

### Changed
- Selected networks and input sources use accent-colored icons on white backing surfaces; unselected, passive, and unavailable icons use dimmed backings. Hover feedback is limited to expandable islands, collapsible headers, selectable rows, and available actions.
- The compact panel now includes a Launch at Login option backed by macOS Login Items. It registers only the main StatusArc app and does not install a helper. Local command-line builds are ad-hoc signed so the option works without Apple Developer Program membership.
- Battery is now a passive at-a-glance island. The Energy Mode switcher and privileged helper have been removed, so StatusArc no longer requests Login Items approval for power-policy changes.
- Wi-Fi joins now check only the user keychain for saved passwords. If none is available, StatusArc asks for the password without requesting administrator access to the System keychain.
- Battery, network, and input-source changes now refresh from macOS events, with a low-frequency recovery refresh, instead of waiting for one-second polling.
- External power that is paused, complete, or not actively charging now uses a larger vertical plug accessory in a 36-point item, with visual weight comparable to the charging bolt and an accurate battery menu label.
- The center input indicator now uses a compact label derived from native Text Input Source metadata instead of a fixed two-letter country-code rule; menus and accessibility use the full localized source name.
- Battery, Connectivity, and Input Source now appear as three directly switchable islands in a SwiftUI-hosted AppKit panel. This removes nested submenu tracking while preserving the existing public system actions.
- Islands use matched Liquid Glass transitions on supported macOS versions and semantic system material on earlier versions. Reduce Motion is respected, and outside click or Escape dismisses the panel.
- Connectivity uses a system toggle and inline network list, and Input Source shows complete native names with compact source badges.
- The battery track now uses a 10-point radius and a 220-degree arc; the network dots and Ethernet line sit lower in the resulting bottom gap.
- Island morphs now run inside a pre-sized SwiftUI glass canvas. The transparent AppKit panel changes size outside the rendered transition, avoiding competing window and glass animations. The bolt/plug accessories sit 2 points farther right.
- Compact islands use a full-width AppKit first-click target above the morphing glass surface, so a single click opens them even when the nonactivating panel has just appeared; the Wi-Fi switch remains an independent native control.
- One- and two-letter input-source labels use the same 9.5-point size and remain optically centered.
- Wi-Fi controls now expose scanning, connecting, disconnecting, and power-transition states and prevent duplicate actions while an operation is in progress.
- Nearby Wi-Fi networks are grouped into known and other networks without an arbitrary result limit; the current network is pinned and checked.
- Hidden-network and password prompts now use labeled AppKit controls, native validation, security selection, and Show Password behavior.
- Wi-Fi status now distinguishes off, disconnected, and local-only/no-Internet states. Option-opening the menu exposes IP, router, band, protocol, security, and radio details.
- Non-Wi-Fi tunnel and virtual interfaces no longer claim to be Ethernet in the compact icon.
- The icon responds to Increase Contrast and Differentiate Without Color, and its accessibility value follows every system-state change.

## [1.2.0] - 2026-09-12

### Changed
- macOS early/final low-battery warnings now show a red arc with a dim red remainder without a separate warning dot; no custom percentage threshold is applied.
- Low Power Mode uses a yellow arc with a dim yellow remainder unless low-battery urgency takes precedence.
- Charging uses a small bolt to the right of the composite icon without changing the arc color; the low-battery warning remains in the arc.
- The menu-bar item expands from 24 points without an accessory to 34 points while a charging or power-plug accessory is visible. The warning dot is removed. Original icon sizes and spacing are preserved; neighboring items move with the changing width.
- Accessory changes use a short shift-and-fade animation that respects Reduce Motion.
- Wi-Fi joins now run without blocking the menu, cancelling a password prompt no longer attempts a connection, and IPv6-only primary interfaces are detected.

## [1.1.0] - 2026-09-10

### Added
- The current StatusArc version is shown in the menu.
- Sparkle-powered update discovery and user-triggered installation from the menu.

### Changed
- StatusArc probes for updates shortly after launch and about once every 24 hours while running, without automatically downloading or installing them.

## [1.0.1] - 2026-09-10

### Changed
- Battery arc colors now follow macOS power states: green while charging, yellow in Low Power Mode, red when macOS reports a low-battery warning, and the normal menu-bar foreground otherwise.
- Battery percentage progress remains represented by the active arc length, with the unused portion dimmed.

## [1.0.0] - 2026-09-10

### Added
- Single composite macOS menu-bar status icon.
- Battery percentage arc with dimmed remainder.
- Green charging state, yellow low-battery state, and red critical state.
- Two-letter current keyboard/input-source indicator.
- Three-dot Wi-Fi strength indicator.
- Solid-line Ethernet/LAN indicator.
- Primary-interface detection when multiple network interfaces are connected.
- Combined Battery, Network, and Input controls menu.
- Wi-Fi on/off, disconnect, nearby scan, network joining, and diagnostics.
- Input-source switching and Emoji & Symbols shortcut.
- Battery power-source and time-remaining details when available.
- MIT open-source license and contributor documentation.
- Homebrew Cask distribution kit and automated GitHub release packaging.
