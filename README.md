# StatusArc

**StatusArc** is a native macOS menu-bar utility that combines battery, network,
and keyboard-input status into one compact icon.

```text
      ╭────────╮    battery level
         EN        current input source
        ● ● ●      active network
```

The goal is simple: keep the information that is useful at a glance while
replacing several separate menu-bar items with one.

## What the icon means

### Battery — top arc

The full battery arc is always visible. The active segment is the current
battery percentage and the rest is dimmed.

| State | Active arc | Remainder |
| --- | --- | --- |
| Displayed battery ≤25% or macOS early/final low-battery warning | system red | dim red |
| Low Power Mode, unless battery is low | system yellow | dim yellow |
| Normal | normal menu-bar foreground | dim neutral |

Low-battery urgency takes precedence over Low Power Mode. Charging does not
change the arc color: a small `bolt.fill` SF Symbol appears immediately to the
right of the composite icon. When the battery is low and not charging, a red
`exclamationmark` appears there instead. The accessory slot is always reserved,
including when empty, so state changes do not move neighboring menu-bar items.
Language and network indicators retain their normal semantic colors.

### Input source — center

The center shows a compact two-letter code for the current keyboard/input
source, such as `EN`, `UA`, or `DE`.

Ukrainian is intentionally shown as `UA` in the UI.

### Network — bottom indicator

| Active path | Indicator |
| --- | --- |
| Strong Wi-Fi | `● ● ●` |
| Medium Wi-Fi | `● ● ○` |
| Weak Wi-Fi | `● ○ ○` |
| Ethernet/LAN | solid line |
| No active network | `○ ○ ○` |

If Wi-Fi and Ethernet are both connected, StatusArc follows the primary network
interface reported by macOS instead of blindly preferring one.

## Features

Clicking the StatusArc icon opens a combined controls menu.

**Battery**
- Current battery percentage
- Charging / fully charged state
- Current power source
- Time remaining when macOS provides it
- Shortcut to Battery Settings

**Network**
- Wi-Fi on/off
- Disconnect from the current Wi-Fi network
- Scan nearby Wi-Fi networks
- Join open and personal Wi-Fi networks
- Use a saved Wi-Fi password from the macOS keychain when available
- Join another/unlisted network
- Connection details such as RSSI, noise, channel, transmit rate, and interface
- Open Wireless Diagnostics
- Open Network Settings
- Ethernet/LAN detection

**Input**
- List enabled input sources
- Switch input source directly
- Open Emoji & Symbols
- Open Keyboard Settings

**Updates**
- Show the installed StatusArc version in the menu
- Passively check for a newer release shortly after launch and about once per day
- Show `Update to <version>…` when a newer release is available
- Download, verify, install, and relaunch through Sparkle only after user action

## Requirements

- macOS 13 or later
- A recent version of Xcode
- A Mac with Apple Silicon or Intel

StatusArc is an AppKit menu-bar agent (`LSUIElement`) and therefore has no Dock
icon or normal application window.

## Build from source

1. Clone or download this repository.
2. Open `StatusArc.xcodeproj` in Xcode.
3. Select the **StatusArc** target.
4. Choose your Mac as the run destination.
5. Press **Run** (`⌘R`).

If Xcode asks for signing, choose your own development team under
**Target → Signing & Capabilities → Team**.

For a command-line unsigned development build:

```bash
./scripts/build.sh
```

The repository intentionally does not contain a developer-team identifier,
certificate, provisioning profile, or signing secret.

## Permissions and privacy

StatusArc is designed to work locally and does not include analytics,
telemetry, advertising, or a network service of its own.

For software updates, StatusArc uses Sparkle to fetch a public update feed and
release archive from GitHub. Sparkle system profiling is explicitly disabled.
Update downloads and installation only begin after the user chooses the update
item in the StatusArc menu.

**Location permission:** modern macOS restricts access to nearby Wi-Fi network
names. StatusArc requests Location access only when you ask it to scan nearby
Wi-Fi networks. The app does not request or use geographic coordinates.

**Keychain access:** when joining a secured Wi-Fi network, StatusArc may ask
CoreWLAN for the saved password for that SSID. The password is used only for the
association attempt and is not logged or stored by StatusArc.

See [PRIVACY.md](PRIVACY.md) for more detail.

## Known limitations

- Apple does not expose a supported public API for third-party apps to open
  Keyboard Viewer directly. StatusArc avoids private APIs and fragile
  Accessibility/UI scripting.
- Enterprise/802.1X Wi-Fi is handed off to macOS Wi-Fi Settings because
  identities, certificates, and managed credentials are better handled by the
  system.
- The project currently builds with App Sandbox disabled because of its
  system-level Wi-Fi integrations.
- Wi-Fi signal thresholds are deliberately simple and can be tuned.

## Project structure

```text
StatusArc/
├── StatusArc/
│   ├── AppDelegate.swift
│   ├── UpdateManager.swift
│   ├── SystemActions.swift
│   ├── SystemStatusMonitor.swift
│   ├── StatusIconRenderer.swift
│   ├── main.swift
│   └── Info.plist
├── StatusArc.xcodeproj/
├── docs/
├── scripts/
├── .github/
├── CHANGELOG.md
├── CONTRIBUTING.md
├── PRIVACY.md
├── SECURITY.md
└── LICENSE
```

The implementation uses Apple platform frameworks including AppKit, CoreWLAN,
CoreLocation, SystemConfiguration, Carbon, and IOKit. Sparkle is the one
third-party runtime dependency and is pinned to a specific production release.
The secured-network lock
glyph is an SF Symbol rendered by macOS; no Apple symbol artwork is bundled in
this repository.


## Install with Homebrew

The project includes a companion `homebrew-tap` repository and an automated
release pipeline.

Once the repositories are published, users can install StatusArc with:

```bash
brew install --cask dennich/tap/statusarc
```

> **Note:** Until Developer ID signing and notarization are configured, public
> releases are ad-hoc signed. macOS may require manual approval in **System
> Settings → Privacy & Security** on first launch.

After a Sparkle-enabled release is installed, routine application updates can
be started directly from the StatusArc menu. Homebrew remains a supported
installation and upgrade channel as well.

See [docs/HOMEBREW.md](docs/HOMEBREW.md) for release, signing, notarization,
update-signing, and tap setup.

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) and
the [icon specification](docs/ICON_SPEC.md) before changing status semantics or
adding new permissions.

A good default for this project is to prefer public macOS APIs, minimal
permissions, and a small menu-bar footprint.

## License

StatusArc is released under the [MIT License](LICENSE).

## Disclaimer

StatusArc is an independent open-source project and is not affiliated with,
endorsed by, or sponsored by Apple Inc. macOS, AppKit, CoreWLAN, and SF Symbols
are Apple technologies and trademarks or service marks of their respective
owners.
