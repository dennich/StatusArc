#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Parsing Swift source..."
swiftc -parse StatusArc/*.swift

echo "Checking for obvious accidental secrets..."
if grep -RInE \
  --exclude-dir=.git \
  --exclude='*.md' \
  '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|api[_-]?key[[:space:]]*=|password[[:space:]]*=[[:space:]]*"[^"]+")' \
  .; then
  echo "Potential secret-like text found. Review before publishing."
  exit 1
fi

echo "Source checks passed."
