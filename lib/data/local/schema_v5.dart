abstract final class SchemaV5 {
  static const version = 5;

  static const statements = <String>[
    'ALTER TABLE transactions ADD COLUMN posted_at TEXT',
    "UPDATE transactions SET posted_at=occurred_at WHERE status='confirmed' AND deleted_at IS NULL",
    '''CREATE TABLE scheduled_financial_events(
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL REFERENCES financial_profiles(id),
      account_id TEXT NOT NULL REFERENCES accounts(id),
      destination_account_id TEXT REFERENCES accounts(id),
      category_id TEXT REFERENCES categories(id),
      event_type TEXT NOT NULL CHECK(event_type IN ('income','expense','refund','transfer')),
      amount_satang INTEGER NOT NULL CHECK(amount_satang > 0),
      title TEXT NOT NULL,
      note TEXT,
      scheduled_at TEXT NOT NULL,
      due_at TEXT,
      stored_status TEXT NOT NULL DEFAULT 'scheduled' CHECK(stored_status IN ('scheduled','fulfilled','skipped','cancelled')),
      origin_type TEXT NOT NULL,
      origin_id TEXT,
      occurrence_key TEXT NOT NULL,
      linked_transaction_id TEXT UNIQUE REFERENCES transactions(id),
      linked_transfer_group_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      cancelled_at TEXT,
      deleted_at TEXT,
      sync_status TEXT NOT NULL DEFAULT 'local',
      user_id TEXT,
      CHECK(
        (event_type='transfer' AND destination_account_id IS NOT NULL AND destination_account_id<>account_id AND linked_transaction_id IS NULL)
        OR
        (event_type<>'transfer' AND destination_account_id IS NULL AND linked_transfer_group_id IS NULL)
      )
    )''',
    '''CREATE UNIQUE INDEX scheduled_origin_occurrence_unique
       ON scheduled_financial_events(profile_id,origin_type,origin_id,occurrence_key)
       WHERE origin_id IS NOT NULL''',
    '''CREATE UNIQUE INDEX scheduled_linked_transfer_unique
       ON scheduled_financial_events(linked_transfer_group_id)
       WHERE linked_transfer_group_id IS NOT NULL''',
    '''CREATE INDEX scheduled_profile_date_status
       ON scheduled_financial_events(profile_id,scheduled_at,stored_status)''',
    '''CREATE INDEX scheduled_profile_account_date
       ON scheduled_financial_events(profile_id,account_id,scheduled_at)''',
    '''CREATE TABLE notification_sources(
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL REFERENCES financial_profiles(id),
      source_kind TEXT NOT NULL CHECK(source_kind IN ('line','bank_app','other_android')),
      display_name TEXT NOT NULL,
      package_name TEXT NOT NULL,
      enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
      default_account_id TEXT REFERENCES accounts(id),
      retention_days INTEGER NOT NULL DEFAULT 7 CHECK(retention_days >= 0),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )''',
    '''CREATE INDEX notification_sources_profile_package_enabled
       ON notification_sources(profile_id,package_name,enabled)''',
    '''CREATE TABLE notification_rules(
      id TEXT PRIMARY KEY,
      notification_source_id TEXT NOT NULL REFERENCES notification_sources(id),
      name TEXT NOT NULL,
      sender_or_chat_pattern TEXT,
      title_pattern TEXT,
      body_pattern TEXT NOT NULL,
      parser_kind TEXT NOT NULL,
      direction_rule TEXT NOT NULL,
      account_id TEXT REFERENCES accounts(id),
      category_id TEXT REFERENCES categories(id),
      priority INTEGER NOT NULL DEFAULT 0,
      enabled INTEGER NOT NULL DEFAULT 1 CHECK(enabled IN (0,1)),
      rule_version INTEGER NOT NULL DEFAULT 1 CHECK(rule_version > 0),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT
    )''',
    '''CREATE INDEX notification_rules_source_priority_enabled
       ON notification_rules(notification_source_id,priority,enabled)''',
    '''CREATE TABLE raw_notification_events(
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL REFERENCES financial_profiles(id),
      notification_source_id TEXT REFERENCES notification_sources(id),
      package_name TEXT NOT NULL,
      notification_key_hash TEXT NOT NULL,
      content_fingerprint TEXT NOT NULL,
      title TEXT,
      body TEXT,
      sender_or_chat TEXT,
      captured_at TEXT NOT NULL,
      parse_status TEXT NOT NULL DEFAULT 'captured' CHECK(parse_status IN ('captured','parsed','parse_failed','ignored','duplicate')),
      matched_rule_id TEXT REFERENCES notification_rules(id),
      created_at TEXT NOT NULL,
      deleted_at TEXT
    )''',
    '''CREATE UNIQUE INDEX raw_notification_key_unique
       ON raw_notification_events(profile_id,package_name,notification_key_hash)''',
    '''CREATE INDEX raw_notification_fingerprint
       ON raw_notification_events(profile_id,content_fingerprint)''',
    '''CREATE INDEX raw_notification_status_captured
       ON raw_notification_events(profile_id,parse_status,captured_at)''',
    '''CREATE TABLE transaction_candidates(
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL REFERENCES financial_profiles(id),
      account_id TEXT REFERENCES accounts(id),
      destination_account_id TEXT REFERENCES accounts(id),
      category_id TEXT REFERENCES categories(id),
      candidate_type TEXT NOT NULL CHECK(candidate_type IN ('income','expense','refund','transfer')),
      amount_satang INTEGER NOT NULL CHECK(amount_satang > 0),
      occurred_at TEXT NOT NULL,
      merchant_or_sender TEXT,
      reference_no TEXT,
      confidence REAL NOT NULL CHECK(confidence >= 0 AND confidence <= 1),
      review_status TEXT NOT NULL DEFAULT 'pending_review' CHECK(review_status IN ('pending_review','suggested_match','confirmed_new','matched_existing','ignored','rejected','duplicate')),
      matched_scheduled_event_id TEXT REFERENCES scheduled_financial_events(id),
      matched_transaction_id TEXT REFERENCES transactions(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      resolved_at TEXT,
      deleted_at TEXT
    )''',
    '''CREATE INDEX candidates_profile_status_date
       ON transaction_candidates(profile_id,review_status,occurred_at)''',
    '''CREATE INDEX candidates_profile_account_amount_date
       ON transaction_candidates(profile_id,account_id,amount_satang,occurred_at)''',
    '''CREATE TABLE candidate_evidence(
      id TEXT PRIMARY KEY,
      candidate_id TEXT NOT NULL REFERENCES transaction_candidates(id),
      evidence_type TEXT NOT NULL CHECK(evidence_type IN ('notification','statement','scheduled')),
      notification_event_id TEXT REFERENCES raw_notification_events(id),
      statement_row_id TEXT REFERENCES statement_rows(id),
      scheduled_event_id TEXT REFERENCES scheduled_financial_events(id),
      created_at TEXT NOT NULL,
      CHECK(
        (evidence_type='notification' AND notification_event_id IS NOT NULL AND statement_row_id IS NULL AND scheduled_event_id IS NULL)
        OR
        (evidence_type='statement' AND notification_event_id IS NULL AND statement_row_id IS NOT NULL AND scheduled_event_id IS NULL)
        OR
        (evidence_type='scheduled' AND notification_event_id IS NULL AND statement_row_id IS NULL AND scheduled_event_id IS NOT NULL)
      )
    )''',
    '''CREATE UNIQUE INDEX candidate_notification_evidence_unique
       ON candidate_evidence(notification_event_id)
       WHERE notification_event_id IS NOT NULL''',
    '''CREATE UNIQUE INDEX candidate_statement_evidence_unique
       ON candidate_evidence(statement_row_id)
       WHERE statement_row_id IS NOT NULL''',
    '''CREATE UNIQUE INDEX candidate_scheduled_evidence_unique
       ON candidate_evidence(scheduled_event_id)
       WHERE scheduled_event_id IS NOT NULL''',
    'CREATE INDEX candidate_evidence_candidate ON candidate_evidence(candidate_id)',
    'PRAGMA user_version = 5',
  ];
}
