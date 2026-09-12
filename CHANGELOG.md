# Changelog

All notable user-visible changes to StatusArc are documented here.

## [Unreleased]

## [1.2.0] - 2026-09-12

### Changed
- macOS early/final low-battery warnings now show a red arc with a dim red remainder without a separate warning dot; no custom percentage threshold is applied.
- Low Power Mode uses a yellow arc with a dim yellow remainder unless low-battery urgency takes precedence.
- Charging uses a small bolt to the right of the composite icon without changing the arc color; the low-battery warning remains in the arc.
- The menu-bar item expands from 24 points without an accessory to 34 points while charging. The warning dot is removed. Original icon sizes and spacing are preserved; neighboring items move with the changing width.
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
