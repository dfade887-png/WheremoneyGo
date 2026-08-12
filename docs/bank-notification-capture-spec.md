# Bank Notification Capture — Experimental v0.1

This Android-only feature is opt-in, disabled by default, and pending-first. Notification access never authorizes an automatic ledger expense. A normalized local event must be reviewed as Expense, Transfer, Installment payment, Match existing, or Ignore.

The native listener uses a strict package allowlist. The production allowlist is currently empty because no verified bank package or anonymized notification fixture has been supplied. The included reference adapter uses `com.example.reference.bank` only in automated fixtures and is not a supported institution.

The platform channel exposes notification-access status and opens Android's Notification Access settings. Android 13+ also requires POST_NOTIFICATIONS before the app can display a follow-up prompt.

States: Disabled, Permission missing, Listening, Bank unsupported, Parse failed, Ready.
