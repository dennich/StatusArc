# GitHub Repository Setup

Suggested repository description:

> One compact macOS menu-bar status icon for battery, network, and input source.

Suggested topics:

`macos`, `menubar`, `swift`, `appkit`, `battery`, `wifi`, `ethernet`,
`keyboard-layout`, `corewlan`

## Initial publish

From this folder:

```bash
git init
git add .
git commit -m "Initial open-source release"
git branch -M main
git remote add origin git@github.com:YOUR-ACCOUNT/StatusArc.git
git push -u origin main
```

Or create the repository on GitHub first and use the HTTPS remote GitHub shows
you.

## Recommended repository settings

- Enable Issues.
- Enable Private Vulnerability Reporting if available.
- Add branch protection for `main` once there are multiple contributors.
- Require the build workflow to pass before merging when practical.
- Optionally enable Discussions for design ideas and feature proposals.

## Branding

Before treating `StatusArc` as a commercial brand, do your own repository,
domain, and trademark availability checks. This source package does not make a
trademark-clearance claim.


## Homebrew companion repository

Create a second public repository named:

```text
homebrew-tap
```

Push the contents of the supplied `homebrew-tap-statusarc` starter repository
there. The repository's updater workflow derives your GitHub owner name
automatically and tracks `dennich/StatusArc`.

After the first StatusArc GitHub Release exists, run:

**homebrew-tap → Actions → Update StatusArc Cask → Run workflow**

The workflow creates `Casks/statusarc.rb`.

Users can then install with:

```bash
brew install --cask dennich/tap/statusarc
```
