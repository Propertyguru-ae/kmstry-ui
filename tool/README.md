# Mobile release checks

Use Flutter 3.35.2 (pinned in `.flutter-version`) and Node 22 for the repository
check scripts. Keep `pubspec.lock`; dependency resolution uses `--enforce-lockfile`.

For local staging checks without creating a signed artifact:

```bash
BUILD_ENV=staging API_URL=https://api.kmstry.net SITE_URL=https://staging.kmstry.net \
BUILD_NAME=1.0.1 BUILD_NUMBER=43 RELEASE_CHECKS_ONLY=true \
bash tool/release_gate.sh
```

For pre-prod checks, use `BUILD_ENV=pre-prod`,
`API_URL=https://pre-prod-api.kmstry.net`, and
`SITE_URL=https://pre-prod.kmstry.net`. Release builds accept only the exact
API/site pair for their `BUILD_ENV`; production is intentionally blocked until
its final origins are configured. There is no implicit release environment.
Omit `RELEASE_CHECKS_ONLY` to build the Android
AAB using your existing `android/key.properties`. Set `BUILD_IOS=true` on the
configured macOS signing host to also build an IPA. No signing or Info.plist
settings are changed by this script.

The gate checks index/working-tree secrets, tool version, public HTTPS origins,
build metadata, release compile-time required defines, analyzer errors and all
tests. Existing analyzer warnings/infos remain nonblocking and visible.

GitHub pull requests run checks only; manual dispatch builds/signs Android.
Required repository variables: `RELEASE_API_URL`, `RELEASE_SITE_URL`,
`RELEASE_BUILD_ENV` (defaults to staging for existing PR checks),
`RELEASE_BUILD_NAME`, `RELEASE_BUILD_NUMBER`. Manual signing requires secrets
`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`,
`ANDROID_KEY_ALIAS`. They must be configured separately; never commit signing
files. Remote CI and signed builds are not proven by a local checks-only pass.

The lightweight secret scan does not scan Git history or ignored local `.env`
files and cannot detect every credential format. Previously exposed secrets
still require rotation as a separate task.
