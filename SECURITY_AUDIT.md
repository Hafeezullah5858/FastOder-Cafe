# FastOder Cafe v14 Security Audit Notes

## Hardened in v14
1. Client-created arbitrary notification records are disabled; privileged notification creation must happen through trusted backend/admin code.
2. Payment records are tied to the authenticated customer's existing order and cannot exceed the order total.
3. Refund requests are tied to the customer's order and cannot exceed its total.
4. Review updates can only change rating/comment metadata and cannot reassign the review.
5. CI now runs `flutter analyze` and `flutter test` on pushes and pull requests.

## Still required before launch
- Configure Firebase App Check and monitor enforcement readiness.
- Use Cloud Functions/Cloud Run for payment webhooks and all privileged money calculations.
- Enable restricted Google Maps keys (Android package/SHA-1 and iOS bundle restrictions as applicable).
- Configure production Crashlytics/observability.
- Test Firestore and Storage rules with the Firebase Emulator Suite.
- Complete real-device tests for GPS, FCM, background behavior, weak connectivity, and payment callbacks.
