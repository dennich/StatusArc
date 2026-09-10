#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

SPARKLE_VERSION="2.9.6"
SPARKLE_TARBALL_SHA256="52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192"
SPARKLE_ACCOUNT="statusarc"
REPOSITORY="dennich/StatusArc"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <version>"
  echo "Example: $0 1.1.0"
  exit 1
fi

VERSION="${1#v}"
TAG="v${VERSION}"

for cmd in gh curl shasum tar python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Required command not found: $cmd"
    exit 1
  fi
done

gh auth status --hostname github.com >/dev/null

IS_DRAFT="$(
  gh release view "$TAG" \
    --repo "$REPOSITORY" \
    --json isDraft \
    --jq '.isDraft'
)"

if [[ "$IS_DRAFT" != "true" ]]; then
  echo "Release $TAG is not a draft."
  echo "Refusing to modify a published release automatically."
  exit 1
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/statusarc-appcast.XXXXXX")"
cleanup() {{
  rm -rf "$TMP"
}
trap cleanup EXIT

RELEASE_DIR="$TMP/release"
APPCAST_DIR="$TMP/appcast"
SPARKLE_DIR="$TMP/sparkle"

mkdir -p "$RELEASE_DIR" "$APPCAST_DIR" "$SPARKLE_DIR"

echo "Downloading the CI-built release..."
gh release download "$TAG" \
  --repo "$REPOSITORY" \
  --pattern "StatusArc-${VERSION}.zip*" \
  --dir "$RELEASE_DIR"

ZIP_PATH="$RELEASE_DIR/StatusArc-${VERSION}.zip"
CHECKSUM_PATH="$RELEASE_DIR/StatusArc-${VERSION}.zip.sha256"

test -f "$ZIP_PATH"
test -f "$CHECKSUM_PATH"

EXPECTED_SHA="$(tr -d '[:space:]' < "$CHECKSUM_PATH")"
ACTUAL_SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{{print $1}')"

if [[ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]]; then
  echo "Release ZIP checksum mismatch."
  exit 1
fi

echo "Downloading pinned Sparkle tools..."
SPARKLE_ARCHIVE="$TMP/Sparkle-${SPARKLE_VERSION}.tar.xz"

curl -fL \
  "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz" \
  -o "$SPARKLE_ARCHIVE"

printf '%s  %s\n' "$SPARKLE_TARBALL_SHA256" "$SPARKLE_ARCHIVE" \
  | shasum -a 256 -c -

tar -xf "$SPARKLE_ARCHIVE" -C "$SPARKLE_DIR"

GENERATE_APPCAST="$(find "$SPARKLE_DIR" -type f -path '*/bin/generate_appcast' -print -quit)"
GENERATE_KEYS="$(find "$SPARKLE_DIR" -type f -path '*/bin/generate_keys' -print -quit)"

test -x "$GENERATE_APPCAST"
test -x "$GENERATE_KEYS"

EXPECTED_PUBLIC_KEY="$(
  /usr/libexec/PlistBuddy \
    -c "Print :SUPublicEDKey" \
    StatusArc/Info.plist
)"

LOCAL_PUBLIC_KEY="$("$GENERATE_KEYS" --account "$SPARKLE_ACCOUNT" -p)"

if [[ "$EXPECTED_PUBLIC_KEY" != "$LOCAL_PUBLIC_KEY" ]]; then
  echo "The Sparkle key in your Keychain does not match StatusArc's embedded public key."
  exit 1
fi

cp "$ZIP_PATH" "$APPCAST_DIR/"

python3 - "$VERSION" "$APPCAST_DIR/StatusArc-${VERSION}.md" <<'PY'
from pathlib import Path
import re
import sys

version, destination = sys.argv[1:3]
text = Path("CHANGELOG.md").read_text()

pattern = re.compile(
    rf"^## \[{re.escape(version)}\][^\n]*\n(?P<body>.*?)(?=^## \[|\Z)",
    re.MULTILINE | re.DOTALL,
)
match = pattern.search(text)

if match is None:
    raise SystemExit(f"CHANGELOG.md has no section for {version}")

Path(destination).write_text(match.group("body").strip() + "\n")
PY

echo "Generating signed Sparkle appcast with the private key in your macOS Keychain..."
"$GENERATE_APPCAST" \
  --account "$SPARKLE_ACCOUNT" \
  --download-url-prefix "https://github.com/dennich/StatusArc/releases/download/${TAG}/" \
  --link "https://github.com/dennich/StatusArc/releases/tag/${TAG}" \
  --embed-release-notes \
  --maximum-deltas 0 \
  --maximum-versions 1 \
  --output-path "$APPCAST_DIR/appcast.xml" \
  "$APPCAST_DIR"

APPCAST_PATH="$APPCAST_DIR/appcast.xml"
test -f "$APPCAST_PATH"

python3 - "$APPCAST_PATH" "$VERSION" <<'PY'
from pathlib import Path
import sys
import xml.etree.ElementTree as ET

path, version = sys.argv[1:3]
text = Path(path).read_text()
ET.parse(path)

if "sparkle:edSignature=" not in text:
    raise SystemExit("Generated appcast has no Ed25519 update signature")

if f"StatusArc-{version}.zip" not in text:
    raise SystemExit("Generated appcast does not reference the expected release ZIP")
PY

echo "Uploading appcast.xml to the draft release..."
gh release upload "$TAG" "$APPCAST_PATH" \
  --repo "$REPOSITORY" \
  --clobber

ASSET_NAMES="$(
  gh release view "$TAG" \
    --repo "$REPOSITORY" \
    --json assets \
    --jq '.assets[].name'
)"

for required_asset in \
  "StatusArc-${VERSION}.zip" \
  "StatusArc-${VERSION}.zip.sha256" \
  "appcast.xml"
do
  if ! grep -Fxq "$required_asset" <<< "$ASSET_NAMES"; then
    echo "Draft release is missing required asset: $required_asset"
    exit 1
  fi
done

echo "Publishing completed draft release..."
gh release edit "$TAG" \
  --repo "$REPOSITORY" \
  --draft=false

echo
echo "StatusArc $VERSION is published with a signed Sparkle appcast."
