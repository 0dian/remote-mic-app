#!/usr/bin/env bash
set -euo pipefail

ROOT="${REPOSITORY_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
WORKFLOW="$ROOT/.github/workflows/mac-ci.yml"

[[ -r "$WORKFLOW" ]] || {
  echo "public CI workflow is unreadable: $WORKFLOW" >&2
  exit 1
}

for forbidden in \
  'GetSayAll/' \
  'sayall-ai' \
  'sayall-macro-platform' \
  'sayall-mac-remote' \
  'resolve-release-dependencies.sh' \
  '.private-dependencies' \
  'DEPLOY_KEY' \
  'secrets.' \
  'swift test' \
  'swift build' \
  'swift package'; do
  if grep -Fq -- "$forbidden" "$WORKFLOW"; then
    echo "public macOS CI must not reference private or SwiftPM entry: $forbidden" >&2
    exit 1
  fi
done

grep -Fq -- './scripts/test-macos-release-flow.sh' "$WORKFLOW"
grep -Fq -- 'SKIP_SWIFT_PACKAGE_BUILD=1 ./scripts/test.sh' "$WORKFLOW"
grep -Fq -- './scripts/verify-public-ci-isolation.sh' "$WORKFLOW"

echo "PUBLIC CI ISOLATION PASS"
