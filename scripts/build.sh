#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

xcodebuild \
  -project StatusArc.xcodeproj \
  -target StatusArc \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
