# Flutter Production UI Build Report

Date: 2026-08-10

## Validation

- Flutter analyze: passed, 0 issues
- Automated tests: 61 passed
- Financial Rules FR-01–FR-16: unchanged
- SQLite migration and repository tests: passed
- Onboarding profile persistence: passed
- Quick Add ledger persistence: passed
- UX Scenario coverage: onboarding, three-tap Quick Add, dirty-form discard, Statement manual matching, Refund, Transfer, and reconciliation blocking
- Debug APK: passed
- Release test APK: passed

## APK artifacts

### Debug

- Path: `build/app/outputs/flutter-apk/app-debug.apk`
- Size: 168,598,975 bytes
- SHA-256: `5E0D54678FA49A463E4477063355FCB46F8C72F4092FF7BEB3EF177B7C347605`

### Release test

- Path: `build/app/outputs/flutter-apk/app-release.apk`
- Size: 55,392,406 bytes
- SHA-256: `F8D92856CACBE245EE18BE95CC90FDBADDB4495604F57752008021D97ED593E7`

The release test APK still uses debug signing and must not be uploaded to Google Play.

## Delivered behavior

- Local-first onboarding stored in SQLite.
- Existing profile skips onboarding on the next launch.
- Quick Add writes a manual expense to the ledger.
- Dashboard cash and category spending refresh after save and after restart.
- Food spending remains separate from the flexible budget, matching T30.
- Statement rows remain staged until reviewed; non-zero reconciliation keeps Confirm disabled.

## Current limitations

- Statement screen uses Demo rows until the first institution adapter and redacted sample file are supplied.
- Recurring expense and saving-goal screens save the initial profile, but full edit/history management is a later feature slice.
- Production signing is not configured.
