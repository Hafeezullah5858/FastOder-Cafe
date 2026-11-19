# FastOder Cafe — Engineering Status (17 November 2026)

This is an actively updated working source snapshot, **not a production release or launch certification**. The original uploaded archive remains separately preserved. No Firebase deployment, migration, production account update, or live payment activation has been performed by this work pass.

## Implemented in source
- Customer, Vendor, Rider and Super Admin app flows.
- Server-authoritative order creation, pricing, coupons, stock reservation and cancellation restock.
- COD plus manual JazzCash, Easypaisa and Bank Transfer proof/review; no online card charging.
- Vendor and Rider application forms, pending status, trusted Admin approval/rejection and account suspension/downgrade.
- Admin dashboard queues for Vendor/Rider applications, active delivery monitor, secure rider assignment, payments, refunds, people, coupons, payment setup, support, payouts and audit log.
- Rider self-claim and Admin assignment are transaction-protected; only ready, unassigned orders can be assigned and manual payments must be verified.
- Rider delivery completion is protected by a six-digit customer OTP, server-side hash, expiry and attempt lock.
- Customer live tracking subscribes to the current order and rider location; Firestore location reads are restricted to the assigned customer's active delivery.
- Rider foreground location stream, server notifications and FCM integration are present in source.
- Firestore/Storage rules and composite indexes include the new onboarding and tracking flows.

## Verification completed in this environment
- `node --check functions/index.js`: PASS.
- `node --check functions/payment_policy.js`: PASS.
- `node --check scripts/test-firestore-rules.cjs`: PASS.
- Root `npm test`: 15/15 PASS (Node policy/source-contract tests).
- JSON parsing and Dart lexical/delimiter checks are recorded in `WORK_PROGRESS_2026-11-17.md` when rerun.

## Still required before production
1. Run `flutter pub get`, `dart format`, `flutter analyze`, `flutter test`, and Android APK/AAB builds in a Flutter-enabled environment.
2. Run Firestore and Storage emulator tests with Firebase CLI; the updated Firestore test script has not yet run in an emulator.
3. Perform physical Android end-to-end tests for all four roles, including background GPS, push notifications, payment proof, approvals and OTP delivery.
4. Configure and verify Google Maps API, production App Check/Crashlytics, and permanent Android release signing.
5. Decide rider earnings/payout policy and complete finance/report exports.
6. Back up and review the actual Firebase project's data/rules, then obtain explicit owner approval before any deployment or live-data change.

## Safety boundary
No Firebase deploy, live data mutation, migration, production payment activation, or Play Store publishing has been performed. Do not describe this source snapshot as production-ready until the Flutter build, emulator tests and device tests pass.
