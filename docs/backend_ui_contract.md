# Backend-UI Contract (Production)

Bu kontrat, UI tarafinin production'da deterministic calismasi icin backendin saglamasi gereken minimum alan ve davranislari listeler.

## 1) GET `/auth/me`

### Root-level context (zorunlu)

- `homeRoute` (`VENUE_HOME|PERSONAL_HOME|CONTEXT_CHOICE|VENUE_ONBOARDING|PERSONAL_ONBOARDING`)
- `nextAction` (`GO_TO_VENUE_HOME|GO_TO_PERSONAL_HOME|SHOW_CONTEXT_CHOICE|START_VENUE_ONBOARDING|START_PERSONAL_ONBOARDING`)
- `lastActiveContext` (`VENUE|PERSONAL|null`)
- `hasPersonalProfile` (bool)
- `hasVenueMembership` (bool)
- `activeVenueId` (string|null)
- `memberVenues` (array)

### Personal fields (zorunlu, root-level)

- `fullName` (string|null)
- `birthdate` (ISO string|null)
- `gender` (string|null)
- `interestedIn` (string|null)
- `onboardingStep` (`NAME_DOB|GENDER_INTEREST|PERMISSIONS|COMPLETED`)

### Active checkin

- `activeCheckin` (object|null)
  - `id` (string)
  - `venueId` veya `venue_id` (string)
  - `expiresAt` veya `expires_at` (ISO string)
  - `what_brings_to_kmstry` veya `whatBringsToKmstry` (string[])

Not: `context` nested objesi gelebilir, ancak UI root-level alanlari esas alir. Root alanlarin varligi zorunludur.

## 2) POST `/users/me/personal-profile`

- Adim adim parsiyel upsert desteklenmeli:
  - Step 1 payload: `fullName`, `birthdate`
  - Step 2 payload: `gender`, `interestedIn`
- Basarili upsert sonrasi `/auth/me` root alanlarina aninda yansima garanti edilmeli:
  - `hasPersonalProfile=true`
  - `fullName/birthdate/gender/interestedIn`

## 3) PATCH `/users/me/context`

- Request:
  - `lastActiveContext` (`PERSONAL|VENUE`)
  - `activeVenueId` (opsiyonel, venue secimi icin)
- Beklenti:
  - Sonraki `/auth/me` cagrisinda context alanlari tutarli olmalı.

## 4) GET `/checkins/{id}/profile`

### Minimum stabil response

- `user` object
  - `id`, `full_name|fullName`, `birthdate`, `gender`, `is_verified|isVerified`, `is_premium|isPremium`
- `checkin` object
  - `id`, `vibe` (nullable), `expires_at|expiresAt`
- `media` array (null degil, bos olabilir)
  - item: `id`, `url`, `media_type|mediaType`, `is_featured|isFeatured`, `thumbnail_url|thumbnailUrl`, `duration_seconds|durationSeconds`
- `is_matched` (bool)
- Opsiyonel:
  - `chat_id`
  - `relationship.myActionAtThisVenue`
  - `relationship.theirActionAtThisVenue`
  - `relationship.myActionCreatedAt`
  - `relationship.theirActionCreatedAt`

## 5) Error semantics (onemli)

- `404` sadece gercekten kaynak yok durumlari icin donmeli.
- Gecici backend/network hatalari `5xx` ile donmeli (UI `no data` ile karistirmasin).
- Alan tipi drift olmamali (string/int/null karisimi parser kiriyor).

## 6) Release readiness checklist

- [ ] `/auth/me` root context + personal alanlari stabil
- [ ] `/users/me/personal-profile` upsert sonrasi `/auth/me` aninda tutarli
- [ ] `activeCheckin` shape production'da sabit
- [ ] `/checkins/{id}/profile` media/user/checkin alanlari tip tutarli
- [ ] 404 ve 5xx semantigi ayrik
