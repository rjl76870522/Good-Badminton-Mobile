# Good-Badminton iOS and Codemagic

## What Codemagic does

Codemagic is a cloud CI/CD service. It starts a temporary macOS build machine,
clones this GitHub repository, installs the selected Flutter and Xcode versions,
then runs the workflow in `codemagic.yaml`.

Codemagic does not run on the Ubuntu server and does not require a personal Mac
for the unsigned verification workflow.

## Current workflow

The `ios-unsigned` workflow performs these checks on a Codemagic Mac:

1. Enable Flutter Swift Package Manager integration
2. Download iOS Flutter artifacts and packages
3. Validate `Info.plist` and the Xcode project
4. Run `flutter analyze`
5. Run all Flutter tests
6. Build an unsigned release `.app` with the production API URL

The unsigned `.app` proves that the Flutter and native iOS code compile, but it
cannot be installed on a physical iPhone or uploaded to TestFlight.

## Run the unsigned build

1. Sign in at <https://codemagic.io> with GitHub
2. Add the `rundon0401-hue/Good-Badminton-1` repository
3. Choose configuration from `codemagic.yaml`
4. Select the `ios-unsigned` workflow
5. Start a build from the `ios/codemagic` branch

Pushes to branches matching `ios/*` trigger this workflow automatically after
the Codemagic application has been created.

## Install on iPhone and use TestFlight

A signed iPhone build requires an active Apple Developer Program membership.
After joining the program:

1. Create an app in App Store Connect with bundle ID
   `com.rundon0401.goodbadminton`
2. Create a dedicated App Store Connect API key with App Manager access
3. In Codemagic, open Team settings, Developer Portal, and add the API key
4. Configure automatic iOS signing for the same bundle ID
5. Add a signed `flutter build ipa` workflow
6. Publish the resulting IPA to TestFlight

Do not commit `.p8`, `.p12`, provisioning profiles, API keys, or Apple account
passwords to Git. Store signing credentials only in Codemagic integrations or
encrypted environment variables.

## iOS project settings

- Bundle ID: `com.rundon0401.goodbadminton`
- Minimum iOS version: 13.0
- Display name: `Good-Badminton`
- API: `https://api.audacity6441.kdns.fr`
- Photo library read permission: select training videos
- Photo library add permission: save analysis videos and highlights
- Network policy: HTTPS only

## What Ubuntu can verify

Ubuntu can run Flutter analysis, unit tests, and validate project files. It
cannot run Xcode or produce an Apple-signed IPA. The Codemagic macOS machine is
responsible for those Apple-only build steps.
