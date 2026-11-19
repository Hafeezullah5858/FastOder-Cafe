# FastOder Cafe — Working Progress (17 November 2026)

This is a work-in-progress source snapshot, not a production release. The original archive remains separately preserved. No Firebase deployment or live-data changes have been made.

## Implemented in the working source

### Customer
- Search food names/categories and filter menu categories.
- See vendor open/closed state; closed stores cannot receive new orders.
- Select COD, JazzCash manual, Easypaisa manual or Bank Transfer manual. Online card charging/gateways are not included.
- Manual account details are snapshotted onto the order at creation so later admin edits do not change payment instructions for existing orders.
- Submit a transaction reference and JPG/PNG/WEBP receipt image (under 5 MB) for manual review.
- Create support/complaint tickets and track admin replies.
- Submit a Home Chef application and track its review status.
- See payment state, track the rider and view a delivery OTP when the order is on the way.

### Vendor
- Customer-facing vendor application with pending/rejected/approved status; admin approval is required before vendor access is granted.
- Orders, menu management, menu categories, stock quantity, recorded seller earnings and manual payout requests.
- `stockQty = -1` means unlimited; finite stock is checked and decremented atomically during order creation.
- Stock reserved by a placed order is restored exactly once when that order is cancelled before acceptance.
- Store open/closed switch is enforced server-side; opening/closing times are currently informational and are not an automatic schedule.

### Rider
- Customer-facing rider application captures contact, delivery area, vehicle and experience; the account remains a customer until admin approval.
- Available, active and completed delivery lists.
- Atomic server-side rider self-claim plus admin assignment; assignment requires an approved rider, a ready unassigned order and verified payment for manual transfers.
- Live location visibility is synced to active assigned customers; foreground GPS tracking remains available.
- Delivery completion requires a six-digit customer-only OTP, expires after 24 hours and locks after five incorrect attempts.

### Admin
- Overview now includes pending vendor/rider application counts.
- Dedicated Vendor and Rider approval queues; decisions update the user role, approval flag and audit log through a trusted callable.
- Delivery Monitor lists active delivery orders, displays rider GPS updates and allows secure admin assignment to an approved rider.
- Order cancellation, manual payment verification, manual refund review, people suspension/downgrade, Home Chef application approval/suspension, coupon management, payment account setup, seller payout review, support ticket replies and audit log.
- Manual payment/refund, payout, role, Home Chef and support decisions are performed by trusted callable Cloud Functions and recorded in `admin_audit_logs`.

### Backend/security
- `createOrderSecure` supports only COD and the three manual transfer methods. It uses server-side product prices, validates account setup, and creates order/payment/OTP documents in a Firestore transaction.
- Manual proof submission verifies customer ownership and confirms the image object exists in Storage.
- Vendor/rider order progression is blocked for unpaid manual orders.
- Rider assignment and delivery completion are server-authoritative; delivery completion remains OTP-gated.
- Firestore rules now allow a customer to read only a rider location explicitly shared with that customer's active assigned order; suspended riders cannot publish location updates.
- Firestore/Storage rules and composite indexes were updated for the new workflows.

## Checks completed in this environment
- `node --check functions/index.js`: PASS.
- `node --check functions/payment_policy.js`: PASS.
- Root `npm test`: 15/15 PASS (pure backend policy and source-contract tests).
- JSON parsing for package manifests, Firebase config, indexes and Android Firebase config: 5/5 PASS.
- Dart delimiter/lexical balance scan: 23/23 Dart files PASS. This is not a Dart compiler or Flutter analyzer.
- Firestore emulator test script expanded for vendor/rider applications, role escalation prevention, rider GPS privacy and suspended rider checks; script syntax PASS, emulator execution still pending.

## Not yet verified / remaining
- Flutter/Dart SDK is not installed in this execution environment; `flutter pub get`, `dart format`, `flutter analyze`, `flutter test` and Android APK/AAB builds have NOT run.
- Firebase CLI/emulators are not installed; Firestore/Storage rules emulator tests and callable integration tests have NOT run.
- No physical Android device end-to-end run has been performed.
- Google Maps API key, production App Check/Crashlytics configuration, release signing key and Play signing remain release requirements.
- Rider earnings/payouts and full finance/report exports remain to be completed or explicitly scoped. Customer support/complaints and admin reply management are present in source.
- Store opening/closing times are informational; only the manual open/closed switch is enforced.

## Safety
- No Firebase deploy, data migration, or production configuration change was performed.
- Do not describe this snapshot as a completed or launch-certified app until the missing build, emulator and device tests pass.
