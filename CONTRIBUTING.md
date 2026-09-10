# Contributing to StatusArc

Thanks for helping improve StatusArc.

## Development setup

You need a Mac running macOS 13 or later and a recent version of Xcode.

1. Fork or clone the repository.
2. Open `StatusArc.xcodeproj`.
3. Select the `StatusArc` target and your Mac as the destination.
4. Build with `⌘B`.
5. Run with `⌘R`.

You can also run:

```bash
./scripts/build.sh
```

## Project principles

StatusArc is intentionally small. Please prefer changes that preserve these
principles:

- Use public macOS APIs whenever possible.
- Avoid private frameworks and private selectors.
- Avoid Accessibility/UI scripting as a substitute for a public API.
- Request the minimum permissions needed for a feature.
- Do not add analytics, telemetry, tracking, or advertising.
- Never log passwords, Wi-Fi credentials, or other secrets.
- Keep the menu-bar icon readable at normal macOS menu-bar size.
- Preserve light/dark menu-bar compatibility.

## Code style

- Use clear Swift and small focused methods.
- Prefer system semantic colors over hard-coded colors.
- Keep network and system state collection in `SystemStatusMonitor.swift`.
- Keep user-triggered system actions in `SystemActions.swift`.
- Keep icon drawing in `StatusIconRenderer.swift`.
- Keep menu construction and interaction in `AppDelegate.swift`.

No third-party formatter or linter is required at the moment. Please keep
formatting consistent with the existing source.

## Icon semantics

Changes to battery thresholds, colors, network dots/line, or language-code
behavior should also update `docs/ICON_SPEC.md`.

## Testing

Before opening a pull request, work through the relevant checks in
`docs/TESTING.md`.

At minimum:

- The project builds without errors.
- The menu-bar icon appears.
- The menu still opens.
- Input-source switching still works.
- Network changes do not crash the app.
- Any new permission is documented in `PRIVACY.md` and `README.md`.

## Pull requests

Keep pull requests focused. Describe:

- What changed.
- Why it is useful.
- Which macOS version and hardware you tested.
- Any new permission, entitlement, framework, or privacy impact.
- Screenshots for visible UI changes when practical.

Please update `CHANGELOG.md` for user-visible changes.

## Issues

For bugs, include the macOS version, Mac model/architecture, Xcode version if
building from source, and clear reproduction steps.

For security-sensitive issues, follow `SECURITY.md` instead of posting exploit
details publicly.
