# iOS release checklist

Flutter shares the same Dart UI with Android, but iOS needs Apple tooling and
real-device validation.

## Required

- Apple Developer Program account.
- A Mac with Xcode.
- Bundle identifier reserved in Apple Developer portal.
- Signing certificate and provisioning profile.
- Privacy policy URL and support URL.

## Permissions to verify on a real iPhone

- Photo library read permission for selecting training videos.
- Photo library add permission for saving analysis videos/highlights.
- Network access to `https://api.audacity6441.kdns.fr`.

## Build notes

Use the same API endpoint:

```bash
flutter build ipa --release \
  --dart-define=API_BASE_URL=https://api.audacity6441.kdns.fr
```

Before App Store submission, verify upload, analysis polling, report playback,
and save-to-Photos on a real iPhone.
