#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

: "${API_URL:?API_URL is required (for example https://staging-api.kmstry.net)}"
: "${SITE_URL:?SITE_URL is required (for example https://staging.kmstry.net)}"
: "${BUILD_NAME:?BUILD_NAME is required (for example 1.0.1)}"
: "${BUILD_NUMBER:?BUILD_NUMBER is required (for example 43)}"

node --test tool/release-checks.test.cjs
node tool/secret-scan.cjs
node tool/release-preflight.cjs

flutter pub get --enforce-lockfile
node tool/release-config-compile-check.cjs
# Existing info/warning debt is intentionally non-blocking; analyzer errors are blocking.
flutter analyze --no-fatal-warnings --no-fatal-infos
flutter test

if [[ "${RELEASE_CHECKS_ONLY:-false}" == "true" ]]; then
  echo "Mobile checks passed; no signed release artifact was built."
  exit 0
fi

if [[ ! -f android/key.properties ]]; then
  echo "Android release signing configuration is missing (android/key.properties)." >&2
  exit 1
fi

flutter build appbundle --release \
  --build-name "${BUILD_NAME}" \
  --build-number "${BUILD_NUMBER}" \
  --dart-define="API_URL=${API_URL}" \
  --dart-define="SITE_URL=${SITE_URL}"

if [[ "${BUILD_IOS:-false}" == "true" ]]; then
  flutter build ipa --release \
    --build-name "${BUILD_NAME}" \
    --build-number "${BUILD_NUMBER}" \
    --dart-define="API_URL=${API_URL}" \
    --dart-define="SITE_URL=${SITE_URL}"
fi

echo "Mobile release gate passed."
