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

### Native behavior is the specification

For battery, Wi-Fi, and keyboard input controls, use the observable behavior of
the corresponding macOS control as the product specification. Match the full
interaction model where public APIs allow it, including clicks, toggles, menu
structure, enabled and disabled states, transitions, feedback, timing, edge
cases, and updates caused outside StatusArc.

Do not introduce a custom interaction when macOS already establishes the
behavior. Use system-reported state and semantic AppKit behavior so StatusArc
stays synchronized with macOS. If a public API cannot reproduce part of the
native behavior, document the limitation and keep the closest supported
behavior consistent across the app.

### Use system menus and actions first

Before adding a menu or interaction, check whether macOS or a public framework
already provides the menu, action, or destination. Invoke that system-provided
behavior when it can complete the task. Prefer standard AppKit components such
as `NSMenu` and `NSMenuItem` when StatusArc must provide its own menu content;
do not draw a custom menu surface that duplicates their behavior.

Create custom menu content only when no public API can present or embed the
corresponding system menu, or when the system menu cannot support StatusArc's
combined status workflow. Document that reason with the implementation and use
native controls, enabled states, keyboard behavior, accessibility, and timing
inside the fallback.

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
- Battery, Wi-Fi, and input interactions have been compared with their macOS equivalents.

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
