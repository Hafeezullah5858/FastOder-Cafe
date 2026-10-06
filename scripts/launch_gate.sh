#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
failed=0

[ -f pubspec.yaml ] && echo 'PASS: pubspec.yaml' || { echo 'FAIL: pubspec.yaml'; failed=1; }
[ -f firestore.rules ] && echo 'PASS: firestore.rules' || { echo 'FAIL: firestore.rules'; failed=1; }
[ -f storage.rules ] && echo 'PASS: storage.rules' || { echo 'FAIL: storage.rules'; failed=1; }
[ -f android/app/src/main/AndroidManifest.xml ] && echo 'PASS: Android manifest' || { echo 'FAIL: Android manifest'; failed=1; }

for token in '<restricted-key-required>' CHANGE_ME YOUR_KEY; do
  if grep -RIl --exclude-dir=.git --exclude-dir=.dart_tool --exclude='*.zip' --exclude='*.md' --exclude='preflight.sh' --exclude='launch_gate.sh' "$token" android lib functions 2>/dev/null | head -1 | grep -q .; then
    echo "FAIL: placeholder remains in source: $token"; failed=1
  fi
done

if [ -n "${GOOGLE_MAPS_API_KEY:-}" ]; then echo 'PASS: Google Maps key supplied'; else echo 'FAIL: Google Maps key missing'; failed=1; fi
if [ -n "${FOODODER_KEYSTORE_PATH:-}" ] && [ -n "${FOODODER_KEYSTORE_PASSWORD:-}" ] && [ -n "${FOODODER_KEY_ALIAS:-}" ] && [ -n "${FOODODER_KEY_PASSWORD:-}" ]; then
  echo 'PASS: release signing variables supplied'
else
  echo 'FAIL: release signing variables missing'; failed=1
fi

if [ -d ios ]; then echo 'PASS: iOS project present'; else echo 'WARN: iOS project absent (required only if iOS is a launch target)'; fi
if command -v flutter >/dev/null 2>&1; then
  flutter pub get
  flutter analyze
  flutter test
  flutter build appbundle --release
else
  echo 'BLOCKED: Flutter SDK is not installed in this environment.'
  failed=1
fi

exit "$failed"
