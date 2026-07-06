#!/usr/bin/env bash
# build-all.sh — one-command build for Meridian (Android + iOS).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> Android (Gradle, JDK 21+ recommended)"
if [[ -z "${JAVA_HOME:-}" ]] && command -v /usr/libexec/java_home &>/dev/null; then
  if J21="$(/usr/libexec/java_home -v 21 2>/dev/null)"; then
    export JAVA_HOME="$J21"
    echo "    Using JAVA_HOME=$JAVA_HOME"
  fi
fi
./gradlew :app:assembleDebug :app:testDebugUnitTest

echo "==> iOS (XcodeGen + xcodebuild)"
cd ios
if ! command -v xcodegen &>/dev/null; then
  echo "xcodegen not found — install with: brew install xcodegen" >&2
  exit 1
fi
xcodegen generate
xcodebuild \
  -project Meridian.xcodeproj \
  -scheme Meridian \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet \
  build

echo "==> All builds succeeded."
