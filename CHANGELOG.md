# Changelog

All notable user-visible changes to StatusArc are documented here.

## [Unreleased]

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
