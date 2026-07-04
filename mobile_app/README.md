# Good-Badminton Flutter App

Flutter mobile client for the Good-Badminton backend API.

## Backend

Start the backend first:

```bat
D:\py\Good-Badminton\start_mobile_backend.bat
```

Default API base URL in the app:

```text
http://172.29.72.218:8001
```

You can edit the backend address in the app's upload page. For same-WiFi phone testing, use the computer's WLAN IP.

## Flutter SDK

This machine uses:

```text
D:\tools\flutter
```

Use the explicit executable if Flutter is not in PATH:

```bat
D:\tools\flutter\bin\flutter.bat doctor
D:\tools\flutter\bin\flutter.bat analyze
D:\tools\flutter\bin\flutter.bat test
```

## Android SDK

This machine has Android Studio and Android SDK configured:

```text
Android SDK: C:\Users\jiale\AppData\Local\Android\Sdk
Java/JBR: C:\Program Files\Android\Android Studio\jbr
```

Installed SDK components include:

```text
platform-tools
platforms;android-35
platforms;android-36
build-tools;35.0.0
build-tools;36.0.0
```

## Current Features

- Save/test backend base URL
- Local guest `user_id`
- Pick a video file
- Optional manual court corners with `corners_json`
- Upload video to `POST /api/videos/upload`
- Poll task progress
- Show history from `GET /api/history`
- Show training report from `GET /api/tasks/{task_id}/report`
- Play highlight and analysis videos
- Display heatmap and trajectory images
- Parse unified backend errors from `detail.code`, `detail.message`, and `detail.hint`

## Platform Notes

Android debug HTTP is enabled in:

```text
android/app/src/main/AndroidManifest.xml
```

iOS debug HTTP is enabled in:

```text
ios/Runner/Info.plist
```

These settings are convenient for LAN testing. For production or TestFlight, prefer HTTPS through a domain or tunnel.

## Local Checks

Passed:

```bat
D:\tools\flutter\bin\flutter.bat analyze
D:\tools\flutter\bin\flutter.bat test
D:\tools\flutter\bin\flutter.bat build apk --debug
```

Debug APK output:

```text
D:\py\Good-Badminton\mobile_app\build\app\outputs\flutter-apk\app-debug.apk
```

To install on a connected Android phone:

```bat
C:\Users\jiale\AppData\Local\Android\Sdk\platform-tools\adb.exe devices
C:\Users\jiale\AppData\Local\Android\Sdk\platform-tools\adb.exe install -r D:\py\Good-Badminton\mobile_app\build\app\outputs\flutter-apk\app-debug.apk
```

iOS/TestFlight still requires a Mac/Xcode or cloud build environment.
