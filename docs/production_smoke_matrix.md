# Production Smoke Matrix

Bu dosya, mevcut calisan davranisi bozmadan degisiklik yapabilmek icin referans senaryolari sabitler.

## Senaryo 1 - Venue-only login

- **Given:** `homeRoute=VENUE_HOME`, `hasVenueMembership=true`, `hasPersonalProfile=false`
- **When:** Kullanici login olur
- **Then:** Venue home acilir
- **Beklenen log:** `server_route_venue_home`
- **Olmamasi gereken:** `NameDobOnboardingPage` acilmasi

## Senaryo 2 - Personal-only login

- **Given:** `homeRoute=PERSONAL_HOME`, `hasPersonalProfile=true`
- **When:** Kullanici login olur
- **Then:** Personal home acilir
- **Beklenen log:** `server_route_personal_home`

## Senaryo 3 - Venue mode, personal yok

- **Given:** Venue context acik, `hasPersonalProfile=false`
- **When:** Profile popup acilir
- **Then:** Satir metni `Create Personal Account` olur
- **When:** Satira tiklanir
- **Then:** `NameDob -> GenderInterest -> Permissions` sirasinda onboarding ilerler

## Senaryo 4 - Venue mode, personal var

- **Given:** Venue context acik, `hasPersonalProfile=true`, `fullName=Deniz Korukcu`
- **When:** Profile popup acilir
- **Then:** Satir metni `Switch to Deniz Korukcu` olur
- **When:** Satira tiklanir
- **Then:** Personal contexte gecilir (AuthGate uzerinden)

## Senaryo 5 - Mixed account drift kontrolu

- **Given:** Hem venue hem personal sinyali var
- **When:** Login olur
- **Then:** `lastActiveContext` ile uyumlu route secilir
- **Beklenen:** Venue seciliyse venue, personal seciliyse personal

## Senaryo 6 - Profile checkin data

- **Given:** Kullanicinin aktif check-in'i var
- **When:** Profile sayfasi acilir
- **Then:** Vibe ve moments gorunur
- **Olmamasi gereken:** Sessiz bos ekran (hata olursa retry/bildirim gorunmeli)

## Verification Checklist

- [ ] Tum senaryolar iOS ve Android'de tekrarlandi
- [ ] Route branch loglari beklenenlerle eslesti
- [ ] Venue login onboarding regression yok
- [ ] Create Personal Account akisi step step calisti
- [ ] Profile moments/vibe aktif check-in varken gorundu
