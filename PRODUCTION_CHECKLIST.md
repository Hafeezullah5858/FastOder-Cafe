# FastOder Cafe Production Checklist

## Backend implemented in the working source (still requires integration testing)
- Server-authoritative order creation/pricing and atomic stock reservation (`createOrderSecure`).
- COD and manual transfer payment records; customer receipt submission and admin verification.
- Server-created in-app notifications + FCM push (`processOrderUpdate`).
- Seller earning ledger on delivered orders.
- Customer/vendor/rider/admin Firestore access controls.
- App Check + Crashlytics client integration.

## Required external setup
1. Confirm the Firebase Android app is `com.foododer.app` and Email/Password Auth is enabled.
2. Deploy rules, indexes and Cloud Functions:
   - `firebase deploy --only firestore:rules,firestore:indexes,functions`
3. Create the first admin account from a trusted/admin environment; normal users cannot promote themselves.
4. Assign vendor/home-chef/rider roles from the trusted/admin environment.
5. Register the production Android app in Firebase App Check and verify Play Integrity. Enforce App Check on sensitive callable functions after testing.
6. Add a restricted `GOOGLE_MAPS_API_KEY` GitHub secret and enable Maps SDK for Android + Directions API.
7. Configure Google Play App Signing / controlled upload key for the public release.
8. Enable Crashlytics and verify a test crash reaches the Firebase Console.
9. Test the complete customer → vendor → rider → delivered flow on a physical Android device.

## Payments
Cash on Delivery is active. JazzCash, Easypaisa and Bank Transfer are manual offline transfers only: customer-submitted transaction reference and receipt, followed by admin verification. Online card charging and payment gateways are not included. Before production, configure the business account details in Admin > Payment Setup and verify the full proof/review flow in Firebase Emulator and on devices. Also verify refund review and ensure the merchant actually sends any approved refund before marking it completed.

## Final QA
- Sign up / login / logout / password reset.
- Customer sees only own orders.
- Vendor sees only own products/orders; stock decrement/restock and store open/close enforcement.
- Vendor flow: placed → accepted → preparing → ready.
- Rider flow: ready → picked_up → on_the_way → delivered, with customer OTP required for delivery completion.
- Customer cancellation only while placed.
- Rider GPS foreground-service tracking and customer map/ETA with a valid Maps key.
- Review after delivery.
- Admin role assignment, Home Chef application approval, order cancellation, payment/refund/payout review, support tickets, coupons and audit log.
- Duplicate checkout tap does not create duplicate orders.
- Offline/restart/location-denied scenarios.
