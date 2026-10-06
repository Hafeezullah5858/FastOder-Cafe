#!/usr/bin/env bash
set -euo pipefail

if ! command -v firebase >/dev/null 2>&1; then
  echo 'Firebase CLI is required. Install it first with: npm install -g firebase-tools'
  exit 1
fi

firebase deploy --only firestore:rules,firestore:indexes,functions
