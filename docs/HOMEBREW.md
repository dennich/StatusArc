# Homebrew Distribution

StatusArc is a native macOS `.app`, so Homebrew distribution uses a **cask**.

The recommended project-owned setup uses two GitHub repositories:

1. `StatusArc` — source code and signed release ZIPs.
2. `homebrew-tap` — the Homebrew cask users install from.

Homebrew officially recommends a repository whose name starts with `homebrew-`
for a third-party tap. A repository called `homebrew-tap` gives users the short
tap name `dennich/tap`.

## User install command

After the release and tap are published:

```bash
brew install --cask dennich/tap/statusarc
```

Homebrew automatically taps the repository when a fully qualified cask is
installed.

Alternatively:

```bash
brew tap dennich/tap
brew install --cask statusarc
```

## Release flow

The `Release` GitHub Actions workflow runs when a tag matching `v*` is pushed.

For example:

```bash
git tag -a v1.0.0 -m "StatusArc 1.0.0"
git push origin v1.0.0
```

The workflow:

1. Builds a universal `arm64 + x86_64` Release app.
2. Developer-ID signs and notarizes it when signing secrets are configured.
3. Otherwise applies an ad-hoc signature and emits a Gatekeeper warning.
4. Packages `StatusArc.app` as `StatusArc-<version>.zip`.
5. Publishes the ZIP and SHA-256 checksum as a GitHub Release.

The companion `homebrew-tap` repository has an updater workflow that reads the
latest StatusArc GitHub release, computes its SHA-256, and writes:

```text
Casks/statusarc.rb
```

It runs on a schedule and can also be started manually from GitHub Actions.

## Signing and notarization

For a smooth downloaded-app/Homebrew experience, configure Developer ID
signing and Apple notarization.

Create these GitHub Actions secrets in the **StatusArc** repository:

- `APPLE_DEVELOPER_ID_P12_BASE64`
- `APPLE_DEVELOPER_ID_P12_PASSWORD`
- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

`APPLE_DEVELOPER_ID_P12_BASE64` is a base64-encoded `.p12` containing the
**Developer ID Application** certificate and private key.

Example on macOS:

```bash
base64 -i DeveloperIDApplication.p12 | pbcopy
```

Paste that value into the GitHub secret.

Use an Apple app-specific password for `APPLE_APP_SPECIFIC_PASSWORD`, not your
normal Apple Account password.

Never commit any signing certificate, private key, password, or notarization
credential.

### If signing secrets are not configured

The release workflow still creates an ad-hoc signed build for development and
third-party tap testing. Because it is not Developer-ID signed/notarized,
Gatekeeper may require the user to approve the app manually in macOS Privacy &
Security.

Do not submit such a build to the official `homebrew/cask` repository.

## Official Homebrew Cask later

A project-owned tap can be used immediately. Submission to the official
`homebrew/cask` repository is a separate step with stricter requirements,
including Gatekeeper-compatible distributed artifacts and Homebrew's package
acceptance/notability rules.

The project-owned tap is therefore the intended distribution path for the
initial releases.
