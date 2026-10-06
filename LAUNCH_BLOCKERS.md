# FastOder Cafe Release Gate

The source now contains the core production hardening: trusted order pricing, server-created notifications, FCM push handling, seller earnings, protected payment records, and role-based Firestore rules.

## External release requirements
1. Deploy Firestore rules/indexes and Cloud Functions.
2. Configure and verify Firebase App Check / Play Integrity, then enforce sensitive callables.
3. Configure a restricted `GOOGLE_MAPS_API_KEY` and verify Maps + Directions on a physical device.
4. Configure permanent Google Play App Signing / upload key.
5. Enable Crashlytics and verify a test crash.
6. Run Firebase Emulator security tests and real-device end-to-end tests.
7. Keep online card/JazzCash/Easypaisa payments disabled until provider credentials, server-side verification and webhooks are implemented.

The APK can compile without a Maps key, but map/route features require the restricted production key at runtime.
