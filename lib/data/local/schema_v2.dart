abstract final class SchemaV2 {
  static const version = 2;
  static const statements = <String>[
    'ALTER TABLE installments ADD COLUMN total_payable_satang INTEGER CHECK(total_payable_satang IS NULL OR total_payable_satang > 0)',
    'ALTER TABLE installments ADD COLUMN regular_payment_satang INTEGER CHECK(regular_payment_satang IS NULL OR regular_payment_satang > 0)',
    'ALTER TABLE installments ADD COLUMN interest_or_fee_note TEXT',
    "ALTER TABLE installments ADD COLUMN status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','paused','cancelled','completed'))",
    '''CREATE TABLE installment_total_adjustments(id TEXT PRIMARY KEY, installment_id TEXT NOT NULL REFERENCES installments(id), previous_total_satang INTEGER, new_total_satang INTEGER NOT NULL CHECK(new_total_satang > 0), reason TEXT NOT NULL, effective_at TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, sync_status TEXT NOT NULL DEFAULT 'local', user_id TEXT)''',
    '''CREATE TABLE bank_notification_events(id TEXT PRIMARY KEY, source_package TEXT NOT NULL, institution TEXT NOT NULL, adapter_version TEXT NOT NULL, notification_key_hash TEXT NOT NULL, content_fingerprint TEXT NOT NULL, detected_at TEXT NOT NULL, posted_at TEXT, direction TEXT, amount_satang INTEGER, account_hint_masked TEXT, merchant_hint TEXT, status TEXT NOT NULL CHECK(status IN ('pending','confirmed','matched_existing','ignored','parse_failed','duplicate')), matched_transaction_id TEXT REFERENCES transactions(id), parse_error_code TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    'CREATE UNIQUE INDEX bank_event_key_unique ON bank_notification_events(notification_key_hash)',
    'CREATE INDEX bank_event_fingerprint ON bank_notification_events(content_fingerprint)',
    'PRAGMA user_version = 2',
  ];
}
