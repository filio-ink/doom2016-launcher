#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 -B -m unittest discover -s tests -p 'test_*.py' -v
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
swiftc -o "$TEMP/security-tests" macos/SecurityPolicy.swift tests/main.swift
"$TEMP/security-tests"
for script in build_app.sh release.sh scripts/make-test-update.sh; do
    bash -n "$script"
done
