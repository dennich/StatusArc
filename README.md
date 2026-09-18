# StatusArc

StatusArc is an open-source native macOS menu-bar utility that combines battery,
network, and keyboard input-source status in one compact icon.

The icon shows battery level at the top, the current input source in the center,
and the active network at the bottom. Clicking it opens a compact panel with
related information and controls.

## Features

- Battery, charging, and Low Power Mode status
- Wi-Fi and Ethernet status, nearby networks, and common network actions
- Current keyboard input source and quick source switching
- Optional Launch at Login
- User-initiated updates through Sparkle
- Native AppKit and SwiftUI interface using public macOS APIs
- No analytics, advertising, or backend service

## Requirements

- macOS 13 or later
- Apple Silicon or Intel Mac

## Install with Homebrew

```bash
brew install --cask dennich/tap/statusarc
```

Public releases are currently ad-hoc signed because the project does not yet
use Apple Developer ID signing and notarization. macOS may require manual
approval in **System Settings → Privacy & Security** on first launch.

## Build from source

1. Clone or download this repository.
2. Open `StatusArc.xcodeproj` in Xcode.
3. Select the **StatusArc** target and your Mac as the run destination.
4. Press **Run** (`⌘R`).

For a command-line development build:

```bash
./scripts/build.sh
```

No Apple Developer Program membership is required for a personal ad-hoc build.

## Privacy

StatusArc works locally. It requests Location access only when scanning nearby
Wi-Fi networks, may use a saved Wi-Fi password from the user keychain when
joining a network, and connects to GitHub only for user-initiated software
updates. See [PRIVACY.md](PRIVACY.md) for details.

## Documentation

- [Changelog](CHANGELOG.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Icon specification](docs/ICON_SPEC.md)
- [Testing guide](docs/TESTING.md)
- [Distribution and releases](docs/HOMEBREW.md)

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before
submitting changes.

## License

StatusArc is released under the [MIT License](LICENSE).

StatusArc is an independent project and is not affiliated with or endorsed by
Apple Inc.
