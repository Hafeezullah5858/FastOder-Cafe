# FastOder Cafe — Release blockers

This list applies to the working source, not to the untouched original archive. The three core source workflows (Admin management, Vendor/Rider approvals, and secure assignment/customer tracking) have now been implemented in source, but still require runtime verification before they can be called complete in production.

1. Run `flutter pub get`, `dart format`, `flutter analyze`, `flutter test`, Android release APK and AAB builds in a Flutter-enabled environment.
2. Run `npm run test:rules` with Firebase CLI and the Firestore emulator; add Storage emulator tests for payment proof uploads.
3. Exercise all four roles on a physical Android device: customer checkout/proof upload, vendor order/menu/stock/payout, rider assignment/OTP/location, and admin payment/refund/role/support/payout controls.
4. Configure and verify the Google Maps key and production App Check/Crashlytics settings.
5. Supply and protect the real Android release signing key before publishing; the temporary CI key is not a Play Store signing key.
6. Decide and implement the rider earning/payout policy. Seller payouts are implemented as manual requests; rider payouts are not yet implemented.
7. Complete finance/report exports and any required support SLAs/notification preferences.
8. Review Firestore and Storage rules against the real project data, take a fresh backup, and obtain explicit owner approval before any Firebase deploy or live-data change.

No Firebase deployment, migration, live account update, or production payment activation has been performed by this working-source pass.
