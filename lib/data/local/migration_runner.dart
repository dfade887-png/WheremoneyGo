import 'package:sqlite3/sqlite3.dart';

import 'schema_v1.dart';
import 'schema_v2.dart';

abstract final class MigrationRunner {
  static void migrateToV1(Database database, {List<String>? statements}) {
    if (database.userVersion >= SchemaV1.version) return;
    database.execute('BEGIN IMMEDIATE');
    try {
      for (final statement in statements ?? SchemaV1.statements) {
        database.execute(statement);
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  static void migrateToLatest(Database database, {List<String>? v2Statements}) {
    migrateToV1(database);
    if (database.userVersion >= SchemaV2.version) return;
    database.execute('BEGIN IMMEDIATE');
    try {
      for (final statement in v2Statements ?? SchemaV2.statements) {
        database.execute(statement);
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }
}
