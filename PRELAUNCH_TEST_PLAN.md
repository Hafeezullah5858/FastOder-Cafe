# FastOder Cafe v16 — Pakistan Pre-Launch Test Plan

This release is a QA gate, not a claim that production services are already configured.

## Required environments
- Flutter stable + Dart compatible with `pubspec.yaml`
- Firebase project (staging first, production second)
- Android physical devices (low/mid/high range)
- iOS physical device if iOS is a launch target
- Google Maps API key restricted to the package/bundle and required APIs
- Firebase App Check configured per platform
- Crashlytics enabled

## Critical end-to-end tests
1. Customer signup/login/logout/password reset.
2. Customer creates Home/Work address and selects a map pin.
3. Customer adds restaurant and Home Chef food to cart; validates single-vendor rules.
4. Coupon valid/invalid/expired/minimum-order/vendor-scoped cases.
5. COD order: placed → accepted → preparing → ready → picked_up → on_the_way → delivered.
6. Customer cancellation before vendor acceptance.
7. Paid-order refund request path in staging.
8. Vendor/Home Chef approval and product/image management.
9. Rider assignment, GPS permission, background/foreground location behavior.
10. Push notification received when app is foreground/background/terminated.
11. Review only after delivered order; duplicate review prevention.
12. Offline/poor-network retry without duplicate orders.
13. App restart preserves authenticated session and cart/address state.
14. Firestore/Storage rules tested with Firebase Emulator.
15. App Check monitor → verify legitimate traffic → enforce.
16. Crashlytics test event visible in Firebase console.

## Pakistan coverage
Test at minimum with addresses and phone numbers from:
Islamabad, Rawalpindi, Lahore, Karachi, Peshawar, Quetta, Multan, Faisalabad, Gujranwala, Hyderabad, Sialkot, Bahawalpur, Sukkur, Abbottabad, Gilgit and Muzaffarabad.

Also test Urdu and English UI, PKR formatting, +92 phone formats, and low-connectivity conditions.

## Launch gate
Do not enable production payments or App Check enforcement until critical tests pass and real Firebase/Maps/payment credentials are configured.
