# Financial Core v1.1 Changes

Financial Core v1.0 rules FR-01–FR-16 retain their validated meanings. Version 1.1 adds an independent installment-progress calculation and schema migration.

## Added rule: installment progress

```text
paid = confirmed linked payments - valid linked refunds
remaining = max(0, total payable - paid)
overpayment = max(0, paid - total payable)
progress ratio = paid / total payable
estimated remaining payments = ceil(remaining / regular payment)
```

Unknown or invalid totals yield no ratio. Unknown or zero regular payments yield no payment estimate. Paid is never silently clamped.

## Schema v2

- Nullable total payable and regular payment on existing installments.
- Contract status: active, paused, cancelled, completed.
- Optional fee/interest note.
- Audited total adjustments with a required reason.
- Local-only bank-notification event staging table.

Existing installment rows migrate with unknown totals. Migration executes atomically and rolls back on failure. Backup schema version is now 2.
