import '../models/financial_models.dart';

abstract interface class FinanceRepository {
  Future<int> schemaVersion();
  Future<int> ledgerTransactionCount();
  Future<String> createTransfer({required String fromAccountId, required String toAccountId, required int amountSatang, bool failAfterDebit = false});
  Future<void> softDeleteTransfer(String transferGroupId, {bool failAfterFirst = false});
  Future<String> stageStatement({required String accountId, required String fileName, required String fileHash, required ParsedStatement parsed});
  Future<void> classifyStatementRow(String rowId, StatementClassification classification, {String? matchedTransactionId});
  Future<void> cancelStatement(String importId);
  Future<void> confirmStatement(String importId, {bool failMidway = false});
  Future<void> undoStatement(String importId);
  Future<List<Map<String, Object?>>> statementRows(String importId);
  Future<List<Map<String, Object?>>> dumpTable(String table);
  Future<Map<String, Object?>> exportBackup();
  Future<void> restoreBackup(Map<String, Object?> backup);
}
