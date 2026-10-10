# FastOder Cafe — Food + Grocery Delivery

Updated cross-platform Flutter starter for Android and iOS.

## Added in this version
- Customer Login / Sign Up / Profile
- Food + Grocery
- Search, categories, cart and checkout UI
- Orders, favorites and notifications
- Vendor Panel
- Rider Panel
- Admin Panel
- Business panel navigation from Profile

## Vendor
Store, Products, New Orders, Sales, Offers, Settings.

## Rider
Online/offline status, available orders, pickup/delivery, earnings.

## Admin
Users, Vendors, Riders, Orders, Payments, Reports, Promotions, Settings.

## Important
These panels are UI/scaffold screens. Real accounts, database, permissions, payments,
maps/GPS, live tracking, order dispatch and push notifications still require backend integration.

## Run
flutter create .
flutter pub get
flutter run

iOS requires macOS + Xcode.


## Backend-ready architecture added
- Auth service interface
- Firestore order service interface
- Rider location service interface
- Payment service interface
- Secure app configuration pattern
- BACKEND_SETUP.md deployment checklist


## Ratings + notifications + live route setup (v5)
1. Run `flutter pub get`.
2. Create/restrict a Google Maps API key with Maps SDK for Android and the Directions API enabled.
3. Run with `GOOGLE_MAPS_API_KEY=<restricted-key>`.
4. The Rider Panel's location toggle now streams location updates to Firestore.
5. Customer tracking draws a driving route and shows ETA/distance when the Directions API is available.
6. For production, prefer a server-side route proxy or Google Routes API so the web-service key is not exposed in the client.


### v5 additions
- Customer star ratings and reviews after delivery
- In-app Firestore notifications for order status/rider assignment
- Notification read/unread state
- Rider assignment uses a shared OrderService method
- Online gateway credentials are still intentionally not hard-coded; COD remains the working payment method

## Home Made Food marketplace

- Home Made is a regular food category in the customer marketplace.
- Vendors can manage their food items, prices, and photos through the Seller Panel.
- Home Made items use `foodCategory: home_made`.
- Existing `home_chef` accounts remain supported for backward compatibility.
- Seller photo uploads remain subject to Firebase Storage security rules.

## v7 Marketplace billing
- Checkout now shows subtotal, delivery fee, and total.
- Default marketplace commission is 10% of food subtotal.
- Default delivery fee is Rs. 80 + Rs. 20/km, with free delivery at Rs. 2500+.
- Seller payout = subtotal - marketplace commission; delivery fee is not included in seller payout.
- COD remains the active payment method until a supported gateway is configured with server-side verification.
- A Firebase Cloud Function creates a seller earnings ledger when an order becomes delivered.
- Deploy the function from `functions/` with `firebase deploy --only functions`.
- For production, pricing should be calculated/enforced in trusted server code rather than relying on client calculations.


## v8 Marketplace safeguards
- Coupon codes are stored in `coupons/{CODE}` and validated for active status, expiry, minimum subtotal, vendor scope, and discount cap.
- Orders persist the applied coupon code and discount.
- Admins manage coupons; customers can read active coupon documents.
- For production, coupon validation and final payable amount should also be enforced server-side before charging an online payment.


## v9 Payment / Cancellation / Refund
- Cash on Delivery is active.
- Payment records are stored in `payments`.
- Customer can cancel only while an order is still `placed`.
- Non-COD cancellations create a `refund_requests` review record. No refund is marked successful until the real payment gateway confirms it.
- JazzCash, Easypaisa and card gateways require merchant credentials and server-side webhook/signature verification before activation.

## v10 Customer reliability improvements
- Cart is persisted locally with SharedPreferences, so closing/reopening the app does not lose the cart.
- Cart quantity changes are persisted immediately.
- Cart is cleared after a successful order and the app refreshes the cart badge.
- The existing Firebase order/payment/security architecture is unchanged.

Before release, run:
```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```


## v12 Map Address Picker
- Checkout now has a map button to select the exact delivery location.
- Tap the map or drag the pin; latitude/longitude are returned to checkout and stored with the order.
- Uses the existing Google Maps API key configuration.

## v13 Pakistan Production Hardening
- Added Firebase Cloud Messaging registration for real push-notification tokens.
- Added Android notification permission and internet permission declarations.
- Fixed a critical Firestore privilege-escalation risk: a normal user can no longer change protected role/seller approval fields on their own user document.
- Added Pakistan configuration for PKR and common +92/03 mobile-number validation.
- Push notifications remain dependent on Firebase project configuration and real device permission.
- Do not ship with `<restricted-key-required>`; inject a restricted key at build time and enable only the APIs required by the app.
- Online payment remains disabled until a real Pakistan payment gateway is integrated with server-side signature/webhook verification.

## Release gate
This build is hardened but is **not claimed to be launch-certified** until it passes on a real Android/iOS device:
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --release`
5. Firebase Emulator/Rules tests for customer/vendor/home-chef/rider/admin roles
6. GPS + notification tests on physical devices
7. COD end-to-end order test
8. Sandbox payment/webhook test before enabling any online gateway


## v15 reliability hardening
- Firebase App Check is enabled at startup (Play Integrity on Android; App Attest with DeviceCheck fallback on Apple platforms). Register the app in Firebase App Check before release.
- Firebase Crashlytics captures uncaught Flutter errors and platform errors. Enable Crashlytics in the Firebase project and verify a test crash in a non-production build before rollout.
- Do not use the Play Integrity/App Attest providers in an unregistered development build; use the documented debug provider only for local development and never ship debug tokens.
- Before launch, test App Check enforcement in monitor mode first, then enforce after legitimate traffic is verified.

## v16 QA gate
Run `./scripts/preflight.sh`, then on a Flutter-enabled machine run `flutter pub get`, `flutter analyze`, and `flutter test`. Complete `PRELAUNCH_TEST_PLAN.md` and `docs/SECURITY_TEST_MATRIX.md` before production release.


## v17 Launch Gate
Run `./scripts/launch_gate.sh` on a machine with Flutter installed. Review `LAUNCH_BLOCKERS.md` and do not release until all blockers are resolved.

## v20 Build Gate
- The Android project includes the required Flutter launch theme, launcher resource, Gradle launcher, and Firebase/Google services configuration.
- `OrderModel` contains all pricing fields used by Firestore deserialization and serialization.
- GitHub Actions runs formatting, analysis, tests, and both release APK/AAB builds.
- CI creates an ephemeral signing key only for build verification; use Google Play App Signing for production.
- `GOOGLE_MAPS_API_KEY` is optional for compilation but required for working Google Maps/Directions features.


## v21 Stability Fixes
- Development App Check now uses the Firebase debug provider; production keeps Play Integrity/App Attest.
- Checkout address, phone and coupon fields now use persistent controllers instead of creating a new controller on every rebuild.
- Version bumped to 1.5.0+7.
- This source package still requires the owner's Firebase project, restricted Maps key, production App Check registration, Play signing, and real-device QA before public release.
