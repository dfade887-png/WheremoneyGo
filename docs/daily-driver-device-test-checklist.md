# Daily Driver Device Test Checklist

Backup first. Install the Debug APK over the existing Debug app; do not uninstall it.

- [ ] Existing v1.1 data remains after schema v2 → v3 migration.
- [ ] Open Settings and verify `เงินจริงรวม` equals the active-account sum.
- [ ] Add Bank, Wallet and Cash=0 accounts; archive and restore Cash.
- [ ] Add category `เติมเกม` with the game icon.
- [ ] Record one income and one expense; restart and verify both remain.
- [ ] Transfer Bank → Wallet; verify total cash does not change.
- [ ] Edit an ordinary transaction, swipe-delete it and tap `เลิกทำ`.
- [ ] Add a fixed-total phone commitment and record a payment.
- [ ] Add an open-ended dental commitment and record a payment.
- [ ] Create a Backup and confirm its path is shown.
- [ ] Review the two reset warnings, then cancel without losing data.
- [ ] Confirm negative balances render without layout failure.
- [ ] Notification physical-device test remains pending until anonymized fixtures and real package identifiers exist.

Update command:

```powershell
adb install -r "D:\โปรเจคเงินกูไปไหน\flutter_app\artifacts\v1.2.0+3\app-debug.apk"
```

If Android reports a signature mismatch, stop and do not uninstall the existing app.
