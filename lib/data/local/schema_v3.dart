abstract final class SchemaV3 {
  static const version = 3;

  static const statements = <String>[
    "ALTER TABLE accounts ADD COLUMN account_type TEXT NOT NULL DEFAULT 'bank' CHECK(account_type IN ('bank','cash','wallet'))",
    'ALTER TABLE accounts ADD COLUMN icon_key TEXT',
    'ALTER TABLE accounts ADD COLUMN color_value INTEGER',
    'ALTER TABLE accounts ADD COLUMN is_salary_account INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE accounts ADD COLUMN archived_at TEXT',
    "ALTER TABLE categories ADD COLUMN category_type TEXT NOT NULL DEFAULT 'expense' CHECK(category_type IN ('income','expense'))",
    "ALTER TABLE categories ADD COLUMN icon_key TEXT NOT NULL DEFAULT 'category'",
    'ALTER TABLE categories ADD COLUMN color_value INTEGER',
    'ALTER TABLE categories ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE categories ADD COLUMN is_system INTEGER NOT NULL DEFAULT 0',
    'ALTER TABLE categories ADD COLUMN archived_at TEXT',
    "ALTER TABLE transactions ADD COLUMN status TEXT NOT NULL DEFAULT 'confirmed' CHECK(status IN ('pending','confirmed','deleted'))",
    '''CREATE TABLE audit_events(id TEXT PRIMARY KEY, entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, action TEXT NOT NULL CHECK(action IN ('create','update','delete','restore','archive','reset','adjust')), occurred_at TEXT NOT NULL, metadata_json TEXT, created_at TEXT NOT NULL)''',
    '''CREATE TABLE commitments(id TEXT PRIMARY KEY, legacy_installment_id TEXT UNIQUE REFERENCES installments(id), category_id TEXT REFERENCES categories(id), default_account_id TEXT REFERENCES accounts(id), name TEXT NOT NULL, commitment_type TEXT NOT NULL CHECK(commitment_type IN ('fixed_total','open_ended')), total_payable_satang INTEGER CHECK(total_payable_satang IS NULL OR total_payable_satang > 0), regular_payment_satang INTEGER CHECK(regular_payment_satang IS NULL OR regular_payment_satang > 0), target_satang INTEGER CHECK(target_satang IS NULL OR target_satang > 0), due_day INTEGER CHECK(due_day IS NULL OR due_day BETWEEN 1 AND 31), start_date TEXT, expected_final_date TEXT, status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('active','paused','completed','archived')), created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, sync_status TEXT NOT NULL DEFAULT 'local', user_id TEXT)''',
    '''CREATE TABLE commitment_payments(id TEXT PRIMARY KEY, commitment_id TEXT NOT NULL REFERENCES commitments(id), transaction_id TEXT NOT NULL UNIQUE REFERENCES transactions(id), created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT)''',
    '''INSERT INTO commitments(id,legacy_installment_id,category_id,name,commitment_type,total_payable_satang,regular_payment_satang,due_day,start_date,expected_final_date,status,created_at,updated_at,deleted_at,sync_status,user_id) SELECT 'migrated-' || id,id,category_id,name,'fixed_total',total_payable_satang,COALESCE(regular_payment_satang,amount_satang),due_day,start_date,final_due_date,CASE WHEN status='cancelled' THEN 'archived' ELSE status END,created_at,updated_at,deleted_at,sync_status,user_id FROM installments''',
    '''INSERT INTO commitment_payments(id,commitment_id,transaction_id,created_at,updated_at,deleted_at) SELECT 'migrated-payment-' || o.id,'migrated-' || o.installment_id,o.linked_transaction_id,o.created_at,o.updated_at,o.deleted_at FROM commitment_occurrences o WHERE o.installment_id IS NOT NULL AND o.linked_transaction_id IS NOT NULL''',
    'CREATE INDEX accounts_active_index ON accounts(is_active,archived_at)',
    'CREATE INDEX categories_active_type_index ON categories(category_type,archived_at,sort_order)',
    'CREATE INDEX transactions_occurred_status_index ON transactions(occurred_at,status,deleted_at)',
    'CREATE INDEX audit_entity_index ON audit_events(entity_type,entity_id,occurred_at)',
    'CREATE INDEX commitments_status_index ON commitments(status,commitment_type)',
    'CREATE INDEX commitment_payments_commitment_index ON commitment_payments(commitment_id)',
    'CREATE INDEX bank_event_match_index ON bank_notification_events(status,direction,amount_satang,detected_at)',
    'PRAGMA user_version = 3',
  ];
}
