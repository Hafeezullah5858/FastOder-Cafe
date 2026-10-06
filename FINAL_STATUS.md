# FastOder Cafe — Final Engineering Status

This build hardens the core production flow without changing the user-facing ordering design.

## Completed in source
- FastOder Cafe branding/assets.
- Email/password authentication and password reset.
- Server-authoritative order creation through `createOrderSecure`.
- Server-side product price, coupon, delivery fee, commission, payout and total calculation.
- Idempotent order creation using a client request ID.
- COD payment record creation on the trusted backend.
- Client-side order creation and payment-record writes removed.
- Vendor/rider order status writes remain protected by Firestore rules.
- Notification writes removed from vendor/rider clients.
- Server-side order notifications and FCM push sending via `processOrderUpdate`.
- Seller earning ledger on delivered orders.
- Android rider location stream configured with Geolocator foreground-service notification and Android 14 location-service permissions.
- Refund-review record for future online-payment cancellations.
- Invalid/stale FCM token cleanup.
- Cloud Functions deployed in `asia-south1` for Pakistan-region latency.
- Firebase App Check integration in the app and Crashlytics integration.
- Customer/vendor/rider/admin Firestore access controls.

## External production actions still required
These cannot be safely hard-coded into a source ZIP:
1. Deploy Firestore rules/indexes and Cloud Functions to the Firebase project.
2. Register/verify Firebase App Check Play Integrity for `com.foododer.app` and then enforce App Check on sensitive callable functions.
3. Add a restricted Google Maps API key as the GitHub `GOOGLE_MAPS_API_KEY` secret and enable Maps SDK + Directions API.
4. Configure a permanent Google Play upload key/App Signing for the release.
5. Test FCM, Maps, background rider location, permissions and the complete customer → vendor → rider flow on a physical Android phone. Android background-location policy/permission must also be reviewed before Play Store release.
6. Online card/JazzCash/Easypaisa payments remain intentionally disabled until a real provider, server-side verification and webhook/signature validation are configured.

## Important pricing note
The app now treats the backend as the source of truth. The current trusted delivery rule is Rs. 80, with free delivery at subtotal >= Rs. 2500; distance pricing is intentionally not guessed on the server until a trusted route-distance service is configured.
