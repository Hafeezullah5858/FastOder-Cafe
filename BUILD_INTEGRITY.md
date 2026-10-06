# FastOder Cafe v18 — Build Integrity

This release candidate fixes two concrete Android configuration blockers found in v17:

1. Firebase Android package name is consistently `com.foododer.app`.
2. The Maps placeholder is no longer embedded directly in the manifest; it is a resource value that must be populated with a restricted production Maps key. Release signing also no longer falls back to the Android debug keystore; production credentials must be supplied through environment variables.
3. A standard Flutter Android Gradle project structure has been restored (`settings.gradle`, root/app Gradle files, `gradle.properties`).

## Before release

- Put a restricted Google Maps Android key in `android/app/src/main/res/values/strings.xml`.
- Replace debug signing with a real Play App Signing/release configuration.
- Run `flutter clean && flutter pub get`.
- Run `flutter analyze` and `flutter test`.
- Run `flutter build appbundle --release`.
- Test the AAB on a physical Android device.
- Deploy Firebase rules/functions and verify App Check.

The project still does **not** claim iOS support; an iOS runner must be generated/configured separately if iOS is a launch target.
