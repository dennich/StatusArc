#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

REPOSITORY="dennich/StatusArc"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 patch|minor|major"
  exit 1
fi

BUMP="$1"
case "$BUMP" in
  patch|minor|major) ;;
  *)
    echo "Release type must be patch, minor, or major."
    exit 1
    ;;
esac

for cmd in git gh python3 xcodebuild plutil; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd"
    if [[ "$cmd" == "gh" ]]; then
      echo "Install GitHub CLI with: brew install gh"
    fi
    exit 1
  fi
done

gh auth status --hostname github.com >/dev/null

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree must be clean before a release."
  exit 1
fi

if [[ "$(git branch --show-current)" != "main" ]]; then
  echo "Run releases from the main branch."
  exit 1
fi

git config user.name "Den Nich"
git config user.email "dennich@users.noreply.github.com"

git fetch origin main --tags

if [[ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]]; then
  echo "Local main must exactly match origin/main before a release."
  exit 1
fi

LATEST_TAG="$(
  git tag --list 'v[0-9]*.[0-9]*.[0-9]*' --sort=-v:refname \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | head -n 1
)"

if [[ -z "$LATEST_TAG" ]]; then
  echo "No semantic release tag found."
  exit 1
fi

CURRENT_VERSION="${LATEST_TAG#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"

case "$BUMP" in
  patch)
    PATCH=$((PATCH + 1))
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
esac

VERSION="${MAJOR}.${MINOR}.${PATCH}"
TAG="v${VERSION}"
RELEASE_BRANCH="release/${VERSION}"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists."
  exit 1
fi

CURRENT_BUILD="$(
  python3 - <<'PY'
from pathlib import Path
import re

text = Path("StatusArc.xcodeproj/project.pbxproj").read_text()
values = re.findall(r"CURRENT_PROJECT_VERSION = ([0-9]+);", text)

if not values or len(set(values)) != 1:
    raise SystemExit("Unable to determine one consistent CURRENT_PROJECT_VERSION")

print(values[0])
PY
)"

NEXT_BUILD=$((CURRENT_BUILD + 1))
TODAY="$(date +%Y-%m-%d)"

echo "Preparing StatusArc $VERSION (build $NEXT_BUILD)..."
git switch -c "$RELEASE_BRANCH"

python3 - "$VERSION" "$NEXT_BUILD" "$TODAY" <<'PY'
from pathlib import Path
import re
import sys

version, build, date = sys.argv[1:4]

project_path = Path("StatusArc.xcodeproj/project.pbxproj")
project = project_path.read_text()

project, marketing_count = re.subn(
    r"MARKETING_VERSION = [^;]+;",
    f"MARKETING_VERSION = {version};",
    project,
)
project, build_count = re.subn(
    r"CURRENT_PROJECT_VERSION = [0-9]+;",
    f"CURRENT_PROJECT_VERSION = {build};",
    project,
)

if marketing_count != 2:
    raise SystemExit(f"Expected 2 MARKETING_VERSION values, changed {marketing_count}")
if build_count != 2:
    raise SystemExit(f"Expected 2 CURRENT_PROJECT_VERSION values, changed {build_count}")

project_path.write_text(project)

changelog_path = Path("CHANGELOG.md")
changelog = changelog_path.read_text()

marker = "## [Unreleased]\n"
start = changelog.find(marker)
if start < 0:
    raise SystemExit("CHANGELOG.md has no [Unreleased] section")

body_start = start + len(marker)
next_heading = changelog.find("\n## [", body_start)
if next_heading < 0:
    next_heading = len(changelog)

body = changelog[body_start:next_heading].strip()

if not body or "- " not in body:
    raise SystemExit("CHANGELOG.md [Unreleased] has no release notes")

replacement = (
    "## [Unreleased]\n\n"
    f"## [{version}] - {date}\n\n"
    f"{body}\n"
)

changelog = changelog[:start] + replacement + changelog[next_heading:]
changelog_path.write_text(changelog)
PY

plutil -lint StatusArc/Info.plist
./scripts/check-source.sh
git diff --check
./scripts/build.sh

git add StatusArc.xcodeproj/project.pbxproj CHANGELOG.md
git diff --cached --check
git commit -m "Prepare StatusArc $VERSION"

RELEASE_COMMIT="$(git rev-parse HEAD)"

echo "Pushing release branch for CI..."
git push -u origin "$RELEASE_BRANCH"

wait_for_workflow() {
  local workflow="$1"
  local commit="$2"
  local run_id=""

  for _ in $(seq 1 30); do
    run_id="$(
      gh run list \
        --repo "$REPOSITORY" \
        --workflow "$workflow" \
        --commit "$commit" \
        --limit 10 \
        --json databaseId \
        --jq '.[0].databaseId // empty'
    )"

    if [[ -n "$run_id" ]]; then
      break
    fi

    sleep 2
  done

  if [[ -z "$run_id" ]]; then
    echo "Could not find GitHub Actions run for $workflow."
    exit 1
  fi

  gh run watch "$run_id" --repo "$REPOSITORY" --exit-status
}

echo "Waiting for branch Build CI..."
wait_for_workflow "build.yml" "$RELEASE_COMMIT"

echo "Fast-forwarding main with the CI-green release commit..."
git push origin "$RELEASE_COMMIT:refs/heads/main"

git switch main
git merge --ff-only "$RELEASE_BRANCH"

git tag -a "$TAG" -m "StatusArc $VERSION"
git push origin "$TAG"

echo "Waiting for Release workflow to create the draft release..."
wait_for_workflow "release.yml" "$RELEASE_COMMIT"

./scripts/publish-appcast.sh "$VERSION"

echo
echo "Release complete."
echo "The Homebrew tap checks the new published release within about 15 minutes."
