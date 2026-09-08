abstract final class SchemaV6 {
  static const version = 6;

  static const statements = <String>[
    'ALTER TABLE candidate_evidence RENAME TO candidate_evidence_v5',
    '''CREATE TABLE candidate_evidence(
      id TEXT PRIMARY KEY,
      candidate_id TEXT NOT NULL REFERENCES transaction_candidates(id),
      evidence_type TEXT NOT NULL CHECK(evidence_type IN ('notification','statement','scheduled','slip')),
      notification_event_id TEXT REFERENCES raw_notification_events(id),
      statement_row_id TEXT REFERENCES statement_rows(id),
      scheduled_event_id TEXT REFERENCES scheduled_financial_events(id),
      slip_media_event_id TEXT REFERENCES slip_media_events(id),
      parser_id TEXT,
      parser_version TEXT,
      confidence REAL CHECK(confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
      created_at TEXT NOT NULL,
      CHECK(
        (evidence_type='notification' AND notification_event_id IS NOT NULL AND statement_row_id IS NULL AND scheduled_event_id IS NULL AND slip_media_event_id IS NULL)
        OR (evidence_type='statement' AND notification_event_id IS NULL AND statement_row_id IS NOT NULL AND scheduled_event_id IS NULL AND slip_media_event_id IS NULL)
        OR (evidence_type='scheduled' AND notification_event_id IS NULL AND statement_row_id IS NULL AND scheduled_event_id IS NOT NULL AND slip_media_event_id IS NULL)
        OR (evidence_type='slip' AND notification_event_id IS NULL AND statement_row_id IS NULL AND scheduled_event_id IS NULL AND slip_media_event_id IS NOT NULL)
      )
    )''',
    '''INSERT INTO candidate_evidence(id,candidate_id,evidence_type,notification_event_id,statement_row_id,scheduled_event_id,created_at)
       SELECT id,candidate_id,evidence_type,notification_event_id,statement_row_id,scheduled_event_id,created_at FROM candidate_evidence_v5''',
    'DROP TABLE candidate_evidence_v5',
    '''CREATE UNIQUE INDEX candidate_notification_evidence_unique ON candidate_evidence(notification_event_id) WHERE notification_event_id IS NOT NULL''',
    '''CREATE UNIQUE INDEX candidate_statement_evidence_unique ON candidate_evidence(statement_row_id) WHERE statement_row_id IS NOT NULL''',
    '''CREATE UNIQUE INDEX candidate_scheduled_evidence_unique ON candidate_evidence(scheduled_event_id) WHERE scheduled_event_id IS NOT NULL''',
    '''CREATE UNIQUE INDEX candidate_slip_evidence_unique ON candidate_evidence(slip_media_event_id) WHERE slip_media_event_id IS NOT NULL''',
    'CREATE INDEX candidate_evidence_candidate ON candidate_evidence(candidate_id)',
    'ALTER TABLE slip_media_events RENAME TO slip_media_events_v5',
    '''CREATE TABLE slip_media_events(
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL REFERENCES financial_profiles(id),
      media_store_id TEXT NOT NULL,
      content_uri TEXT NOT NULL,
      content_hash TEXT,
      mime_type TEXT NOT NULL,
      media_created_at TEXT,
      discovered_at TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'detected' CHECK(status IN ('detected','processing','parsed','parsed_needs_review','not_financial','failed','candidate_created','ignored','unsupported')),
      ingestion_source TEXT NOT NULL DEFAULT 'automatic' CHECK(ingestion_source IN ('automatic','manual')),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      UNIQUE(profile_id,media_store_id,content_uri)
    )''',
    '''INSERT INTO slip_media_events(id,profile_id,media_store_id,content_uri,content_hash,mime_type,media_created_at,discovered_at,status,ingestion_source,created_at,updated_at,deleted_at)
       SELECT id,profile_id,media_store_id,content_uri,content_hash,mime_type,media_created_at,discovered_at,status,ingestion_source,created_at,updated_at,deleted_at FROM slip_media_events_v5''',
    'DROP TABLE slip_media_events_v5',
    'CREATE INDEX slip_media_profile_status ON slip_media_events(profile_id,status,discovered_at)',
    '''CREATE TABLE slip_parse_results(
      id TEXT PRIMARY KEY,
      profile_id TEXT NOT NULL REFERENCES financial_profiles(id),
      slip_media_event_id TEXT NOT NULL REFERENCES slip_media_events(id),
      parser_id TEXT,
      parser_version TEXT,
      processing_status TEXT NOT NULL CHECK(processing_status IN ('processing','parsed','parsed_needs_review','not_financial','failed','candidate_created')),
      confidence REAL CHECK(confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
      candidate_type TEXT CHECK(candidate_type IN ('income','expense','refund','transfer')),
      amount_satang INTEGER CHECK(amount_satang IS NULL OR amount_satang > 0),
      occurred_at TEXT,
      merchant_or_sender TEXT,
      bank_hint TEXT,
      account_hint TEXT,
      reference_no TEXT,
      warnings_json TEXT,
      failure_code TEXT,
      candidate_id TEXT REFERENCES transaction_candidates(id),
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      deleted_at TEXT,
      UNIQUE(profile_id,slip_media_event_id)
    )''',
    'CREATE INDEX slip_parse_profile_status ON slip_parse_results(profile_id,processing_status,updated_at)',
    'PRAGMA user_version = 6',
  ];
}
