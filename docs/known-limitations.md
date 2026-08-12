# Known Limitations

## Experimental / pending

- No real bank adapter: anonymized notification samples and verified package identifiers are still required.
- Notification capture and transfer suggestion are not physical-device E2E validated.
- Statement Production UI remains partial; repository atomic confirm/undo tests still pass.
- Transfer edit is repository-tested but not exposed in the Activity UI.
- Dedicated account-detail filtering, category lifecycle UI, trash screen and full commitment edit/archive/history remain pending.
- Production signing, Play Store, Cloud Sync and Supabase are not started.
- Figma high-fidelity synchronization is pending quota availability.

Release APKs in this repository are debug/test signed and must not be published.
# v1.3A limitations

- Device acceptance is pending.
- Legacy Foundation opening-progress transactions are not repaired automatically; see `foundation-data-repair-plan.md`.
- Full onboarding section editor/review and all selector replacements remain partial.
- Profile deletion is intentionally unavailable until profile-scoped backup and two-step confirmation are complete.
- Release artifacts are test-only and are not production signed.
