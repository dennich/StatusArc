# Homebrew Distribution

StatusArc is a native macOS `.app`, so Homebrew distribution uses a **cask**.

The project uses two GitHub repositories:

1. `StatusArc` — source code and versioned release ZIPs.
2. `homebrew-tap` — the Homebrew cask users install from.

## User install command

```bash
brew install --cask dennich/tap/statusarc
```

After the Sparkle updater ships, StatusArc can update itself from its menu.
Homebrew remains a supported update channel too, so the generated cask stays a
normal versioned cask rather than opting out of `brew upgrade`.

The tap tracks every published release so new installations and Homebrew
upgrades receive the current version.

## Release flow

Normal releases are initiated locally from a clean `main` checkout:

```bash
./scripts/release.sh patch
./scripts/release.sh minor
./scripts/release.sh major
```

The release script:

1. Verifies the working tree, Git identity, GitHub CLI authentication, and source.
2. Calculates the next semantic version and increments the bundle build number.
3. Moves the `Unreleased` changelog entries into the new version.
4. Builds locally before publishing any Git changes.
5. Pushes a temporary release branch and waits for its Build workflow to pass.
6. Fast-forwards `main`, creates the annotated version tag, and pushes the tag.
7. Waits for the GitHub `Release` workflow to build the universal release.
8. Downloads the exact CI-produced ZIP and checksum from the draft release.
9. Uses Sparkle's pinned `generate_appcast` tool and the private key in the
   maintainer's macOS Keychain to sign the update archive metadata.
10. Uploads `appcast.xml` and only then publishes the GitHub release.
11. Dispatches the `homebrew-tap` updater using the maintainer's existing local
    GitHub CLI session, waits for it, and verifies the cask version.

The draft-release step is intentional: if appcast signing fails, the incomplete
release remains unpublished and is invisible to normal users, Sparkle, and the
Homebrew updater.

## Sparkle update signing

StatusArc pins Sparkle 2.9.6.

The public Ed25519 key is embedded in the application as `SUPublicEDKey`. The
private key is **not** committed to either repository and is **not** stored as a
GitHub Actions secret. It remains in the maintainer's macOS login Keychain under
the Sparkle account name `statusarc`.

`./scripts/publish-appcast.sh <version>` can safely resume the appcast publishing
step for an existing draft release. It verifies that the local Keychain public
key matches the public key embedded in StatusArc before signing anything.

The private update key is security-critical. Back it up in a secure encrypted
location before publishing the first Sparkle-enabled release. Never paste it into
issues, pull requests, source files, CI logs, or chat.

## GitHub release workflow

The `Release` GitHub Actions workflow runs for tags matching `v*`.

It:

1. Builds a universal `arm64 + x86_64` Release app.
2. Verifies the bundle version matches the tag.
3. Developer-ID signs and notarizes when the existing Apple signing secrets are
   configured.
4. Otherwise applies an ad-hoc signature and clearly labels that limitation.
5. Packages `StatusArc.app` as `StatusArc-<version>.zip`.
6. Produces `StatusArc-<version>.zip.sha256`.
7. Creates a **draft** GitHub Release containing those artifacts.

The local release script adds the signed Sparkle appcast and publishes the draft.

## Homebrew tap updater

The companion `homebrew-tap` repository checks the latest **published** StatusArc
release, downloads its versioned ZIP, computes SHA-256, and regenerates:

```text
Casks/statusarc.rb
```

It runs only when explicitly dispatched. Normal releases dispatch it
automatically from `scripts/release.sh` using the maintainer's existing local
GitHub CLI authentication. No cross-repository PAT, GitHub App key, shared secret,
or persistent credential is stored in either repository for this handoff.

The tap workflow itself uses its repository-scoped `GITHUB_TOKEN` only to commit
the regenerated cask back to `homebrew-tap`.

If a published release needs the tap step retried, run:

```bash
gh workflow run update-statusarc.yml --repo dennich/homebrew-tap --ref main
```

The cask remains versioned and checksummed even though StatusArc can self-update.

## Signing and notarization

For a smooth Gatekeeper experience, Developer ID signing and Apple notarization
should eventually be configured.

The current GitHub release workflow supports the existing optional secrets:

- `APPLE_DEVELOPER_ID_P12_BASE64`
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

Until those are configured, releases remain ad-hoc signed. Do not describe an
ad-hoc release as Developer ID signed or notarized.

Never commit a signing certificate, private key, password, update-signing key, or
notarization credential.
