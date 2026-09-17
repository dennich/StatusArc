# StatusArc

**StatusArc** is a native macOS menu-bar utility that combines battery, network,
and keyboard-input status into one compact icon.

```text
      ╭────────╮    battery level
        [A]        current input source
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
| macOS early/final low-battery warning | system red | dim red |
| Low Power Mode, unless battery is low | system yellow | dim yellow |
| Normal | normal menu-bar foreground | dim neutral |

Low-battery urgency takes precedence over Low Power Mode. Charging does not
change the arc color: a small `bolt.fill` SF Symbol appears immediately to the
right of the composite icon. A slightly larger vertical
`powerplug.portrait.fill` appears when external power is connected but charging
is paused or complete. A low-battery
warning is represented by the red arc alone. No warning dot is shown. The item
width is 24 points without an accessory, 34 points with the bolt, and 36 points
with the larger plug. Neighboring menu-bar items move as it expands or contracts.
Accessory changes use a short shift-and-fade transition, disabled when Reduce
Motion is enabled. Input-source and network indicators retain their normal semantic colors.

### Input source — center

The center uses a compact label derived from the current Text Input Source's
public system metadata. It is not restricted to a fixed two-letter country-code
rule: for example, ABC – Extended appears as `A`, while Ukrainian appears as
`УК`. Menus, the tooltip, and accessibility use the complete native localized
source name.

### Network — bottom indicator

| Active path | Indicator |
| --- | --- |
| Strong Wi-Fi | `● ● ●` |
| Medium Wi-Fi | `● ● ○` |
| Weak Wi-Fi | `● ○ ○` |
| Ethernet/LAN | solid line |
| No active network | `○ ○ ○` |

The expanded panel and accessibility description distinguish Wi-Fi off, disconnected,
and connected without an Internet path. VPN, tunnel, and virtual interfaces use
the neutral dim-dot indicator instead of being presented as Ethernet.

If Wi-Fi and Ethernet are both connected, StatusArc follows the primary network
interface reported by macOS instead of blindly preferring one.

## Features

Clicking the StatusArc icon opens three component islands for Battery,
Connectivity, and Input Source. Battery remains an at-a-glance status card;
Connectivity and Input Source expand in place without submenu tracking.
The islands use public Liquid Glass and matched transitions on supported macOS
versions, with semantic system material and reduced-motion behavior on earlier
supported versions.

**Battery**
- Current battery percentage
- Charging / fully charged state
- Passive Low Power Mode indication in the menu-bar arc

**Network**
- Wi-Fi on/off through a native AppKit switch
- Disconnect from the current Wi-Fi network
- Scan nearby Wi-Fi networks
- Show nearby and known networks directly in the Connectivity island
- Join open and personal Wi-Fi networks
- Use a saved Wi-Fi password from the user keychain when available
- Join another/unlisted network
- Open Wireless Diagnostics
- Open Network Settings
- Ethernet/LAN detection

**Input**
- List enabled input sources
- Switch input source directly
- Open Emoji & Symbols
- Open Keyboard Viewer when macOS exposes it through Text Input Source Services
- Open the keyboard settings that control the system input-source-name item
- Open Keyboard Settings

**Updates**
- Show update availability in the expanded panel
- Passively check for a newer release shortly after launch and about once per day
- Show `Update to <version>…` when a newer release is available
- Download, verify, install, and relaunch through Sparkle only after user action

## Requirements

- macOS 13 or later
- A recent version of Xcode
- A Mac with Apple Silicon or Intel

StatusArc is a hybrid AppKit and SwiftUI menu-bar agent (`LSUIElement`) and
therefore has no Dock icon or normal application window. AppKit owns the status
item and system integration; SwiftUI renders the expandable islands.

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
action in the StatusArc panel.

**Location permission:** modern macOS restricts access to nearby Wi-Fi network
names. StatusArc requests Location access only when you ask it to scan nearby
Wi-Fi networks. The app does not request or use geographic coordinates.

**Keychain access:** when joining a secured Wi-Fi network, StatusArc may ask
CoreWLAN for the saved password for that SSID from the user keychain. It does
not query the System keychain or request administrator access. If no saved
password is available, StatusArc asks you to enter it. The password is used only
for the association attempt and is not logged or stored by StatusArc.

See [PRIVACY.md](PRIVACY.md) for more detail.

## Known limitations

- Keyboard Viewer is selectable through Text Input Source Services only on
  macOS versions that expose its palette source. StatusArc shows the standard
  item disabled when the current OS does not expose that public source.
- Apple does not expose a public API that presents or embeds its Battery, Wi-Fi,
  or Input status menus. StatusArc therefore presents three SwiftUI component
  islands backed by public system APIs. Hidden-network and password prompts use
  standard AppKit controls because CoreWLAN provides the action but no system
  join UI.
- Apple does not expose public third-party controls for Charge to Full Now,
  changing Energy Mode, enumerating significant-energy apps, or toggling Show
  Input Source Name. StatusArc passively reflects Low Power Mode in the menu-bar
  arc but leaves power-policy changes to macOS.
- Enterprise/802.1X Wi-Fi is handed off to macOS Wi-Fi Settings because
  identities, certificates, and managed credentials are better handled by the
  system.
- Public CoreWLAN scanning does not reliably identify Apple's Personal Hotspot
  section, so nearby hotspots appear with other networks; the dedicated system
  hotspot behavior remains available in Apple's Wi-Fi menu.
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
│   ├── InputSourceIdentity.swift
│   ├── StatusIconRenderer.swift
│   ├── WiFiDialogs.swift
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
CoreLocation, Network, SystemConfiguration, Carbon, and IOKit. Sparkle is the one
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
be started directly from the StatusArc panel. Homebrew remains a supported
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
