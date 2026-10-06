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
Cash on Delivery is wired into the order flow. Online payments (JazzCash/Easypaisa/card, etc.) must be integrated through a supported provider with server-side verification. Never put merchant secret keys in Flutter source code.

## 6. Current implementation
- Firebase initialization
- Email/password signup and login
- Password reset
- User profile document in Firestore
- Customer order creation
- Customer real-time order list
- Order status field ready for vendor/rider updates
- GPS service ready for rider location writes

Vendor, rider, admin screens are still scaffolds and should be connected to role-based Firestore access before production deployment.

## Google Maps + Live Rider Tracking
1. In Google Cloud Console enable **Maps SDK for Android** for your Firebase/Google project.
2. Create an Android Maps API key and restrict it to your Android package/SHA-1 in production.
3. Supply `GOOGLE_MAPS_API_KEY` as an environment variable when building Android; the Gradle build injects it into the manifest.
4. Ensure Android location permissions are enabled. Rider location is written to `rider_locations/{riderId}`.
5. Customer orders store `deliveryLat` and `deliveryLng` when the order is placed. The customer can open **Track rider** from the Orders tab.
6. The current implementation shows the live rider marker and delivery marker. Turn-by-turn routing/ETA requires the Google Routes/Directions API and billing-enabled Google Cloud project.
