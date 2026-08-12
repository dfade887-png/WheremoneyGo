# Schema v3 Migration Report

Migration path: v2 → v3, inside `BEGIN IMMEDIATE` / rollback on error.

Schema v3 adds account type/lifecycle fields, category type/icon/color/sort/lifecycle fields, transaction status, audit events, commitments and commitment payments plus lookup indexes.

Existing installments are copied to `fixed_total` commitments. Existing totals remain nullable and are never guessed. Linked occurrence transactions become commitment-payment links. Existing legacy tables remain intact for backward compatibility.

Verified:

- Fresh schema v3 creation.
- Representative v2 installment and payment migration.
- Unknown installment total remains null.
- Injected migration failure restores schema version 2 and removes partial columns.
- Schema v2 checksum backup restores into a schema v3 repository.
- Current schema v3 backup/restore and corrupt-checksum protection pass.

Negative account balances are preserved as user data and are not interpreted as demo data.
