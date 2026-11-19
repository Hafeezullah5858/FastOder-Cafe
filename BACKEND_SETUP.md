# FastOder Cafe — Backend Setup

This build now includes real Firebase Authentication and Firestore order creation/reading.

## 1. Firebase
1. Open the Firebase project configured by `android/app/google-services.json` or create your own project.
2. Make sure the Android package name exactly matches the Firebase Android app (`Com.Foododer.App` in the supplied JSON). For production, use a conventional lowercase package such as `com.foododer.app` and download a new `google-services.json` after registering it.
3. Enable **Authentication → Email/Password**.
4. Create Firestore Database.
5. Create these collections as needed: `users`, `vendors`, `products`, `orders`, `riders`, `rider_locations`, `notifications`.

## 2. Firestore security
Do not leave Firestore in test mode. At minimum, customers should only read their own orders and authenticated users should only modify records permitted by their role. Production role management should use trusted server/admin tooling or custom claims rather than a client-editable role field.

## 3. Run
From the project directory:

```bash
flutter create .
flutter pub get
flutter run
```

The generated Android/iOS platform folders must use the same Firebase app identifiers.

## 4. Maps / GPS
`geolocator` is included and `LocationService` requests device location permission. Add the Android/iOS location permission configuration and a restricted Maps SDK/API key when a map UI is added.

## 5. Payments
Cash on Delivery remains available. Manual offline transfers are supported through admin-configured JazzCash, Easypaisa and Bank Transfer account details. Customers submit a transaction reference and receipt image; a trusted Cloud Function keeps the order blocked until an admin verifies it. No online gateway, card charging or merchant secret is used.

## 6. Current implementation
- Firebase initialization
- Email/password signup and login
- Password reset
- User profile document in Firestore
- Customer order creation
- Customer real-time order list
- Order status field ready for vendor/rider updates
- GPS service ready for rider location writes

Vendor, rider and admin workflows have been expanded in the working source. Admin includes overview, orders, manual payments, refunds, role management, home-chef approval, coupons, payment setup and audit log. Vendor includes order workflow, menu categories, finite stock, sales and store open/close settings. Rider includes available, active and completed deliveries, live location and OTP completion. These screens still require Flutter analysis/build and Firebase Emulator/device end-to-end verification before production.

## Google Maps + Live Rider Tracking
1. In Google Cloud Console enable **Maps SDK for Android** for your Firebase/Google project.
2. Create an Android Maps API key and restrict it to your Android package/SHA-1 in production.
3. Supply `GOOGLE_MAPS_API_KEY` as an environment variable when building Android; the Gradle build injects it into the manifest.
4. Ensure Android location permissions are enabled. Rider location is written to `rider_locations/{riderId}`.
5. Customer orders store `deliveryLat` and `deliveryLng` when the order is placed. The customer can open **Track rider** from the Orders tab.
6. The current implementation shows the live rider marker and delivery marker. Turn-by-turn routing/ETA requires the Google Routes/Directions API and billing-enabled Google Cloud project.
