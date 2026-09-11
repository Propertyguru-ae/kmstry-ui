# Google API key separation

KMSTRY uses three distinct Google API key scopes. Never reuse one key across
mobile platforms or the backend.

The current Google Maps Platform project is `banded-plateau-490410-m4`
(`My First Project`). The Firebase project remains separate.

## Android Maps key

- Application restriction: Android apps
- Package name: `com.brightminds.kmstry`
- API restriction: Maps SDK for Android only
- Add the SHA-1 certificate used by each allowed build:
  - Local debug builds: the debug signing certificate
  - Directly installed release builds: the upload/release certificate
- Google Play builds: the **App signing certificate** SHA-1 from Play Console
    (`Setup > App integrity`), which may differ from the upload certificate

Store the key locally in `android/secrets.properties`:

```properties
GOOGLE_MAPS_API_KEY=replace_with_android_restricted_key
```

For automated builds, set `ANDROID_GOOGLE_MAPS_API_KEY` or pass the Gradle
property `-PGOOGLE_MAPS_API_KEY=...`. Do not commit the real key.

## iOS Maps key

- Application restriction: iOS apps
- Bundle ID: `com.brightminds.kmstry`
- API restriction: Maps SDK for iOS only

Store the key locally in `ios/Flutter/GoogleMaps.xcconfig`:

```xcconfig
GOOGLE_MAPS_API_KEY = replace_with_ios_restricted_key
```

This file is read by Debug, Profile and Release builds and must not be
committed.

## Backend Places key

- Create a different key for each environment: staging, pre-production and
  production
- Application restriction: each server environment's public egress IP only
- API restrictions: Places API and Places API (New)
- Store only as the server environment variable `GOOGLE_PLACES_API_KEY`
- Never include this key in a mobile build or repository file

Confirm the actual outbound IP from each server before applying the IP
restriction. A server's DNS or inbound address must not be assumed to be its
egress IP.

## Rotation order

1. Create the three new restricted keys without disabling the existing key.
2. Replace the Android and iOS local secret values and the staging backend
   environment value.
3. Build and test maps on Android and iOS; test venue search/details through
   the backend.
4. Verify Google Cloud metrics show traffic on the intended key/API pairs.
5. Remove or disable the old shared key only after all three smoke tests pass.
6. Repeat the backend-key step separately for pre-production and production.
