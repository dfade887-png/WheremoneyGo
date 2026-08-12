abstract final class SchemaV4 {
  static const version = 4;
  static const legacyProfileId = 'legacy-default-profile';

  static const statements = <String>[
    '''CREATE TABLE financial_profiles(id TEXT PRIMARY KEY, name TEXT NOT NULL, is_primary INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active' CHECK(status IN ('draft','active','archived')), last_used_at TEXT NOT NULL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, sync_status TEXT NOT NULL DEFAULT 'local', user_id TEXT)''',
    '''INSERT INTO financial_profiles(id,name,is_primary,status,last_used_at,created_at,updated_at) VALUES('legacy-default-profile','ข้อมูลเดิม',1,'active',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP,CURRENT_TIMESTAMP)''',
    '''CREATE TABLE application_metadata(key TEXT PRIMARY KEY,value TEXT NOT NULL,updated_at TEXT NOT NULL)''',
    '''INSERT INTO application_metadata(key,value,updated_at) VALUES('active_profile_id','legacy-default-profile',CURRENT_TIMESTAMP)''',
    '''CREATE TABLE profile_settings(id TEXT PRIMARY KEY,profile_id TEXT NOT NULL REFERENCES financial_profiles(id),key TEXT NOT NULL,value TEXT NOT NULL,created_at TEXT NOT NULL,updated_at TEXT NOT NULL,deleted_at TEXT,sync_status TEXT NOT NULL DEFAULT 'local',user_id TEXT,UNIQUE(profile_id,key))''',
    '''INSERT INTO profile_settings(id,profile_id,key,value,created_at,updated_at,deleted_at,sync_status,user_id) SELECT 'profile-' || id,'legacy-default-profile',key,value,created_at,updated_at,deleted_at,sync_status,user_id FROM app_settings''',
    "ALTER TABLE accounts ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE categories ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE budget_periods ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE transactions ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE recurring_expenses ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE installments ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE commitment_occurrences ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE period_budgets ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE saving_goals ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE salary_profiles ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE payroll_deductions ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE statement_imports ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE statement_rows ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE installment_total_adjustments ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE bank_notification_events ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE audit_events ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE commitments ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    "ALTER TABLE commitment_payments ADD COLUMN profile_id TEXT NOT NULL DEFAULT 'legacy-default-profile' REFERENCES financial_profiles(id)",
    'CREATE INDEX accounts_profile_active ON accounts(profile_id,is_active,archived_at)',
    'CREATE INDEX categories_profile_type ON categories(profile_id,category_type,archived_at)',
    'CREATE INDEX transactions_profile_date ON transactions(profile_id,occurred_at,status,deleted_at)',
    'CREATE INDEX commitments_profile_status ON commitments(profile_id,status)',
    'CREATE INDEX statements_profile_status ON statement_imports(profile_id,status)',
    'CREATE INDEX bank_events_profile_status ON bank_notification_events(profile_id,status)',
    'CREATE INDEX audit_profile_date ON audit_events(profile_id,occurred_at)',
    'PRAGMA user_version = 4',
  ];
}
