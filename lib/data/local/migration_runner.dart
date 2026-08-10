import 'package:sqlite3/sqlite3.dart';

import 'schema_v1.dart';

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
}
