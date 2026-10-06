#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

for token in '<restricted-key-required>' 'CHANGE_ME' 'YOUR_KEY'; do
  if grep -RIl --exclude-dir=.git --exclude-dir=.dart_tool --exclude='*.zip' --exclude='*.md' --exclude='preflight.sh' --exclude='launch_gate.sh' "$token" android lib functions 2>/dev/null | head -1 | grep -q .; then
    echo "ERROR: placeholder found in source: $token"
    fail=1
  fi
done

if [ -f pubspec.yaml ]; then echo "OK: pubspec.yaml found"; else echo "ERROR: pubspec.yaml missing"; fail=1; fi
if [ -f firestore.rules ]; then echo "OK: firestore.rules found"; else echo "ERROR: firestore.rules missing"; fail=1; fi
if [ -f storage.rules ]; then echo "OK: storage.rules found"; else echo "ERROR: storage.rules missing"; fail=1; fi
if [ -n "${GOOGLE_MAPS_API_KEY:-}" ]; then echo "OK: GOOGLE_MAPS_API_KEY supplied"; else echo "BLOCKED: GOOGLE_MAPS_API_KEY not supplied"; fail=1; fi

echo "Preflight static check complete. Run flutter pub get, flutter analyze and flutter test on a machine with Flutter installed."
exit "$fail"
