# Bank Notification Privacy

- Processing remains on device.
- The feature is disabled by default and requires explicit Notification Access.
- No AccessibilityService is used.
- Only explicitly allowlisted source packages may be inspected.
- Raw titles and bodies are not persisted or logged.
- Stored events contain hashes and normalized fields only.
- Bank-event staging data is local-only and excluded from cloud backup by default.
- A detected event never creates a transaction before confirmation or matching.
- Notification actions and confirmations are idempotent.
- Lock-screen prompts must use private visibility and avoid merchant/account details.
- Removing Notification Access stops future callbacks at the Android system boundary.

Android may redact notification content, manufacturers may kill background services, and bank formats may change. Detection is best-effort, not guaranteed.
