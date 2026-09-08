abstract final class SchemaV7 {
  static const version = 7;
  static const statements = <String>[
    '''CREATE TABLE category_monthly_budgets(
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL REFERENCES financial_profiles(id),
      category_id TEXT NOT NULL REFERENCES categories(id),
      monthly_budget_satang INTEGER NOT NULL CHECK(monthly_budget_satang > 0),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      UNIQUE(profile_id,category_id)
    )''',
    'CREATE INDEX category_monthly_budgets_profile ON category_monthly_budgets(profile_id,category_id)',
    'PRAGMA user_version = 7',
  ];
}
