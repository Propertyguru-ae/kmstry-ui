---
name: premium-feature
description: Add or gate a KMSTRY+ (paid membership) feature end-to-end across kmstry-back and kmstry_ui. Use whenever a capability should be limited to premium users, or a new KMSTRY+ feature (T42, T44, T47, T49, T50…) is built. Routes every feature through the shared entitlement backbone (premium-matrix + assertPremium on the backend; PremiumFeature + PremiumGate on the frontend) instead of scattered `if (isPremium)` checks. Triggers: "premium only", "KMSTRY+ feature", "gate behind premium", "paywall", "upsell", PREMIUM_REQUIRED.
---

# Adding / gating a KMSTRY+ premium feature

KMSTRY+ is the app's paid membership (binary today: free vs premium). Every
premium feature goes through ONE backbone so tiering later is a one-file change.
Never write ad-hoc `if (user.is_premium)` checks.

## Backend (kmstry-back)

1. **Register the feature** in `src/users/premium-matrix.ts`:
   - Add a value to the `PremiumFeature` enum (SCREAMING_SNAKE wire value, e.g.
     `EXCLUSIVE_OFFERS`).
   - Add its human label to `PREMIUM_FEATURE_LABEL`.
   - (Only add to `FREE_LIMITS` if the feature is *usable-but-capped* rather than
     fully locked.)

2. **Enforce it** where the feature is served — call the shared guard:
   ```ts
   await this.entitlements.assertPremium(userId, PremiumFeature.EXCLUSIVE_OFFERS);
   ```
   `UserEntitlementService.assertPremium` (`src/users/user-entitlement.service.ts`)
   checks effective premium (incl. `premium_until` expiry) and throws a
   `403 { error: 'PREMIUM_REQUIRED' }` the client routes to the paywall.
   - Inject `UserEntitlementService` in the service's constructor; make sure the
     module imports `UserModule` (it's exported there).
   - Gate the **action** (the thing only premium may do), not reads. If the
     feature is "hide X", gate the enable path only (see setReadReceipts /
     setAnonymous in `user.service.ts` — disabling/enabling the premium behavior
     is what's gated).

3. If the client needs to know the current state, add the field to `getMe`
   (`src/auth/auth.service.ts`: select + camelCase return) and to
   `GetMeResponse` in `src/auth/auth.types.ts`.

## Frontend (kmstry_ui)

4. **Mirror the enum** in `lib/core/user/premium_feature.dart`:
   add the value and — critically — its **wire string must exactly match the
   backend enum value** (e.g. `readReceiptsControl` → `'READ_RECEIPTS_CONTROL'`).
   Mismatch = the gate silently breaks.

5. **Gate the UI** with `PremiumGate` (`lib/core/user/premium_gate.dart`):
   ```dart
   final ok = await PremiumGate.ensure(
     context,
     PremiumFeature.exclusiveOffers,
     title: '…', message: '…', icon: Icons.…,
   );
   if (!ok) return; // not premium — upsell sheet already shown
   ```
   `ensure` loads `UserSession`, returns true if unlocked, else shows the KMSTRY+
   magenta upsell sheet and returns false. Use `ensureWithUpsell(onAllowed: …)`
   for the callback form.
   - Premium state is `UserSession.instance` (mirror of `VenueSession`). It's
     seeded app-wide; read it synchronously where possible to avoid a
     free→premium flicker.
   - Handle the backend `PREMIUM_REQUIRED` error too (e.g. account switch made the
     cached session stale) by showing the same upsell.

## Checklist
- [ ] `PremiumFeature` value added on BOTH sides with identical wire string
- [ ] `PREMIUM_FEATURE_LABEL` entry (backend)
- [ ] `assertPremium(...)` on the served action (backend)
- [ ] `UserEntitlementService` injected + `UserModule` imported
- [ ] `PremiumGate.ensure(...)` at the UI entry point (frontend)
- [ ] getMe field added if the client needs the state
- [ ] Free user sees upsell, premium user passes — verified

## Brand
KMSTRY+ accent is magenta `#E020D8` (used by the upsell sheet).

## Reference (already shipped this way)
Anonymous Mode (T40), Advanced Filters (T41), Priority Event Access (T46),
Read Receipts Control (T48). Grep `assertPremium(` and `PremiumGate.ensure(`.
