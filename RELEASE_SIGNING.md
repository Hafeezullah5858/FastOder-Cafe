# FastOder Cafe Release Signing

The GitHub CI workflow creates a temporary signing key only to verify that release APK/AAB
compilation works. **Do not use that CI key for a Play Store production release.**

For production, use Google Play App Signing and keep the upload key under controlled access.
If building locally with the production upload key, set:

- `FOODODER_KEYSTORE_PATH` — path to the production `.jks`/`.keystore`
- `FOODODER_KEYSTORE_PASSWORD` — keystore password
- `FOODODER_KEY_ALIAS` — release key alias
- `FOODODER_KEY_PASSWORD` — key password

Never commit the keystore, passwords, or signing files to Git.
