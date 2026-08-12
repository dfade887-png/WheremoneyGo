# Installment Progress Specification

Installment progress is ledger-derived. Confirmed linked expense payments increase Paid; linked refunds or reversals reduce it. Editing, soft-deleting, or restoring a linked transaction changes the derived result without mutating a duplicated paid-total field.

The UI terminology is Total Payable, Paid, Remaining, Progress, Estimated Remaining Payments, and Overpayment. An overpayment is shown separately and requires review. Recurring expenses without a finite contract total do not show finite progress.

Existing records are not assigned guessed historical totals. Users may add Total Payable later, with adjustments recorded alongside an audit reason.
