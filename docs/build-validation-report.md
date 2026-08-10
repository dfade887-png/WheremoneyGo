# Android Build Validation Report

Project: เงินกูไปไหน — Flutter Financial Core  
Validation date: 2026-08-10  
Build source commit: `fbdb3b43a3a4ea76e0a4f1dde30f725078572ccb`

## Status

- Flutter Financial Core: Implemented / Validated
- Android Toolchain: Validated
- Analyze: Passed — 0 issues
- Tests: Passed — 54 tests (T01–T50 plus migration hardening)
- Debug APK: Passed
- Release Test APK: Passed
- Production Signing: Pending
- Flutter Production UI: Not Started
- Figma Sync: Pending Quota Reset

## Toolchain

- Flutter: 3.44.9 stable, framework `6b182d2c75`
- Dart: 3.12.2
- DevTools: 2.57.0
- Android SDK: 36.0.0
- Android platform: android-36
- Android Build-Tools: 36.0.0
- Android NDK: 28.2.13676358
- CMake: 3.22.1
- JDK: OpenJDK Runtime Environment 25.0.2+-15348964-b329.117
- Windows: Windows 11 Pro 64-bit, 25H2
- Android SDK path: `C:\Users\pondz\AppData\Local\Android\Sdk`
- JDK path: `C:\Users\pondz\Documents\Codex\tools\android-studio\jbr`

`ANDROID_HOME` and `ANDROID_SDK_ROOT` both point to the Android SDK path above.

## APK Artifacts

### Debug APK

- Path: `D:\โปรเจคเงินกูไปไหน\flutter_app\build\app\outputs\flutter-apk\app-debug.apk`
- Size: 151,256,304 bytes
- SHA-256: `A9B4370B08477E370C44CB179E4F9803907CA95CBA1068234A0658E3AEC0034B`

### Release Test APK

- Path: `D:\โปรเจคเงินกูไปไหน\flutter_app\build\app\outputs\flutter-apk\app-release.apk`
- Size: 47,610,784 bytes
- SHA-256: `46B47F37EF5D4A4F6A0E58714598261CD21227C727207AEE5D08328BBA95BD75`
- Signing: Flutter scaffold debug signing configuration

The current release APK is a packaging validation artifact only. It must not be uploaded to Google Play. Production keystore configuration is still pending.

## Validation Results

| Check | Result |
| --- | --- |
| `flutter analyze` | Passed, no issues found |
| `flutter test` | Passed, 54 tests |
| Database migration | Create, upgrade, and rollback coverage passed |
| Backup restore | Restored totals match source data |
| Statement confirm/undo | Atomic behavior passed |
| Debug APK build | Passed from the source project |
| Release APK build | Passed from the verified ASCII workspace |
| UI dependency in Financial Core | None |

## ASCII Build Workspace

Flutter Android release AOT tooling could not consume the Thai-character project path reliably. Release packaging therefore ran from:

`C:\Users\pondz\Documents\Codex\financial-core-release-build`

Before packaging, the tracked source and dependency lock files in that workspace were verified by SHA-256 against `D:\โปรเจคเงินกูไปไหน\flutter_app`. They matched the source tree committed as `fbdb3b43a3a4ea76e0a4f1dde30f725078572ccb`. The generated release APK was then copied back to the project output directory.

Future ASCII-workspace builds must start from the exact Git commit being released. The ASCII directory is a build workspace, not a second source of truth.

## `flutter doctor -v` Summary

- Android toolchain: passed; all Android licenses accepted.
- Windows, Chrome, connected devices, and network resources: passed.
- Flutter/Dart PATH warning was reported in the running shell; user-level PATH has been configured and applies to new terminals.
- Visual Studio is not installed. This is irrelevant to Android builds and is only required for Windows desktop development.

The complete captured output is stored in `docs/flutter-doctor-v.txt`.

## Security and Release Guardrails

- Do not commit keystores, signing passwords, or `key.properties`.
- `.gitignore` excludes `key.properties`, `*.jks`, `*.keystore`, and Android local configuration.
- Configure a production signing identity before any Play Store release.
- Keep Statement files local by default and never include private financial data in build logs.

