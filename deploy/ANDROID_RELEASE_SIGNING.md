# Android release signing

The current APK can be tested, but the release build still uses the debug
signing config. Before distributing the app broadly or uploading an AAB/APK to
stores, create a private release keystore and keep it outside git.

## Create a keystore

```bash
keytool -genkey -v \
  -keystore "$HOME/.android/good-badminton-release.jks" \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias good-badminton
```

## Local-only properties

Create `frontend_flutter/android/key.properties`:

```properties
storePassword=CHANGE_ME
keyPassword=CHANGE_ME
keyAlias=good-badminton
storeFile=/home/john/.android/good-badminton-release.jks
```

Never commit `key.properties` or the `.jks` file.

## Next code change

Update `frontend_flutter/android/app/build.gradle.kts` to load
`key.properties` and use that signing config for `release`.
