#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

xcodebuild \
  -project StatusArc.xcodeproj \
  -target StatusArc \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGN_IDENTITY=- \
  build
