import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/money.dart';
import '../data/repositories/sqlite_finance_repository.dart';
import '../domain/financial_rules.dart';
import '../domain/models/financial_models.dart';

final class LocalProfile {
  const LocalProfile({
    required this.payday,
    required this.holidayRule,
    required this.accountName,
    required this.openingBalance,
    required this.savingTarget,
    required this.emergencyTarget,
    required this.foodSpent,
  });
  final int payday;
  final String holidayRule, accountName;
  final Money openingBalance, savingTarget, emergencyTarget, foodSpent;
}

final class LocalFinanceStore {
  LocalFinanceStore._(this.repository);
  final SqliteFinanceRepository repository;
  static const _uuid = Uuid();
  static const _profileKey = 'onboarding_profile_v1';
  static const _accountId = 'primary-account';

  static Future<LocalFinanceStore> open() async {
    final directory = await getApplicationDocumentsDirectory();
    return LocalFinanceStore._(
      SqliteFinanceRepository.file(
        p.join(directory.path, 'ngoen_ku_pai_nai.sqlite'),
      ),
    );
  }

  static LocalFinanceStore memory() =>
      LocalFinanceStore._(SqliteFinanceRepository.memory());

  Future<List<Map<String, Object?>>> accounts({bool includeArchived = true}) =>
      repository.accounts(includeArchived: includeArchived);

  Future<List<Map<String, Object?>>> categories({String? type}) =>
      repository.categories(type: type);

  Future<List<Map<String, Object?>>> activity({bool includeDeleted = false}) =>
      repository.activity(includeDeleted: includeDeleted);

  Future<String> addAccount({
    required String name,
    required String type,
    required Money openingBalance,
  }) => repository.createAccount(
    name: name,
    type: type,
    openingBalanceSatang: openingBalance.satang,
  );

  Future<String> addCategory({
    required String name,
    required String type,
    required String iconKey,
  }) => repository.createCategory(name: name, type: type, iconKey: iconKey);

  Future<String> addTransaction({
    required String accountId,
    required String categoryId,
    required String type,
    required Money amount,
    DateTime? occurredAt,
    String? note,
  }) => repository.createTransaction(
    accountId: accountId,
    categoryId: categoryId,
    type: type,
    amountSatang: amount.satang,
    occurredAt: occurredAt,
    note: note,
  );

  Future<String> transfer({
    required String fromAccountId,
    required String toAccountId,
    required Money amount,
  }) => repository.createTransfer(
    fromAccountId: fromAccountId,
    toAccountId: toAccountId,
    amountSatang: amount.satang,
  );

  Future<void> archiveAccount(String id) => repository.archiveAccount(id);
  Future<void> restoreAccount(String id) => repository.restoreAccount(id);
  Future<void> updateAccount(String id, String name, String type) =>
      repository.updateAccount(id, name: name, type: type);
  Future<String> adjustAccount(String id, Money delta, String reason) =>
      repository.adjustBalance(
        accountId: id,
        deltaSatang: delta.satang,
        reason: reason,
      );
  Future<void> deleteTransaction(String id) =>
      repository.softDeleteTransaction(id);
  Future<void> restoreDeletedTransaction(String id) =>
      repository.restoreTransactionRecord(id);
  Future<void> updateTransaction({
    required String id,
    required String accountId,
    required String categoryId,
    required Money amount,
    required DateTime occurredAt,
    String? note,
  }) => repository.updateTransaction(
    id: id,
    accountId: accountId,
    categoryId: categoryId,
    amountSatang: amount.satang,
    occurredAt: occurredAt,
    note: note,
  );
  Future<Map<String, Object?>> backup() => repository.exportBackup();
  Future<String> backupToFile() async {
    final directory = await getApplicationDocumentsDirectory();
    final path = p.join(
      directory.path,
      'backup-${DateTime.now().millisecondsSinceEpoch}.json',
    );
    await File(path).writeAsString(jsonEncode(await backup()), flush: true);
    return path;
  }

  Future<void> resetAll() => repository.resetUserData();
  Future<List<Map<String, Object?>>> commitments() => repository.commitments();
  Future<String> addCommitment({
    required String name,
    required String type,
    int? totalSatang,
    int? regularSatang,
    String? accountId,
    String? categoryId,
  }) => repository.createCommitment(
    name: name,
    type: type,
    totalSatang: totalSatang,
    regularSatang: regularSatang,
    accountId: accountId,
    categoryId: categoryId,
  );
  Future<String> payCommitment({
    required String commitmentId,
    required String accountId,
    required String categoryId,
    required Money amount,
  }) => repository.recordCommitmentPayment(
    commitmentId: commitmentId,
    accountId: accountId,
    categoryId: categoryId,
    amountSatang: amount.satang,
  );

  Future<LocalProfile?> loadProfile() async {
    final rows = repository.query(
      'SELECT value FROM app_settings WHERE key = ? AND deleted_at IS NULL',
      [_profileKey],
    );
    if (rows.isEmpty) return null;
    final json =
        jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
    final food =
        repository
                .query(
                  "SELECT COALESCE(SUM(t.amount_satang),0) AS total FROM transactions t JOIN categories c ON c.id=t.category_id WHERE t.type='expense' AND t.deleted_at IS NULL AND c.name='อาหาร'",
                )
                .first['total']
            as int;
    final movement =
        repository.query(
              "SELECT COALESCE(SUM(CASE WHEN type IN ('income','refund','transfer_in') THEN amount_satang WHEN type IN ('expense','transfer_out') THEN -amount_satang WHEN type='balance_adjustment' THEN amount_satang ELSE 0 END),0) AS total FROM transactions WHERE deleted_at IS NULL AND account_id=?",
              [_accountId],
            ).first['total']
            as int;
    return LocalProfile(
      payday: json['payday'] as int,
      holidayRule: json['holidayRule'] as String,
      accountName: json['accountName'] as String,
      openingBalance: Money.fromSatang(
        (json['openingBalanceSatang'] as int) + movement,
      ),
      savingTarget: Money.fromSatang(json['savingTargetSatang'] as int),
      emergencyTarget: Money.fromSatang(json['emergencyTargetSatang'] as int),
      foodSpent: Money.fromSatang(food),
    );
  }

  Future<void> saveProfile(LocalProfile profile) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final value = jsonEncode({
      'payday': profile.payday,
      'holidayRule': profile.holidayRule,
      'accountName': profile.accountName,
      'openingBalanceSatang': profile.openingBalance.satang,
      'savingTargetSatang': profile.savingTarget.satang,
      'emergencyTargetSatang': profile.emergencyTarget.satang,
    });
    repository.execute(
      'INSERT OR REPLACE INTO app_settings(id,key,value,created_at,updated_at) VALUES(COALESCE((SELECT id FROM app_settings WHERE key=?),?),?,?,?,?)',
      [_profileKey, _uuid.v4(), _profileKey, value, now, now],
    );
    repository.execute(
      'INSERT OR REPLACE INTO app_settings(id,key,value,created_at,updated_at) VALUES(COALESCE((SELECT id FROM app_settings WHERE key=?),?),?,?,?,?)',
      ['data_mode', _uuid.v4(), 'data_mode', 'production', now, now],
    );
    repository.execute(
      'INSERT OR REPLACE INTO accounts(id,name,opening_balance_satang,is_active,include_in_net_worth,created_at,updated_at) VALUES(?,?,?,?,?,?,?)',
      [
        _accountId,
        profile.accountName,
        profile.openingBalance.satang,
        1,
        1,
        now,
        now,
      ],
    );
    for (final category in const [
      ('food', 'อาหาร', 1),
      ('travel', 'เดินทาง', 1),
      ('personal', 'ใช้ส่วนตัว', 0),
      ('family', 'ครอบครัว', 1),
    ]) {
      repository.execute(
        'INSERT OR IGNORE INTO categories(id,name,is_essential,created_at,updated_at) VALUES(?,?,?,?,?)',
        [category.$1, category.$2, category.$3, now, now],
      );
    }
  }

  Future<String> addExpense({
    required Money amount,
    required String categoryName,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final categories = repository.query(
      'SELECT id FROM categories WHERE name=? AND deleted_at IS NULL LIMIT 1',
      [categoryName],
    );
    if (categories.isEmpty) throw StateError('Category is not configured');
    final id = _uuid.v4();
    repository.execute(
      'INSERT INTO transactions(id,account_id,category_id,type,amount_satang,occurred_at,source,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)',
      [
        id,
        _accountId,
        categories.first['id'],
        'expense',
        amount.satang,
        now,
        'manual',
        now,
        now,
      ],
    );
    return id;
  }

  Future<void> editExpense(
    String id, {
    required Money amount,
    required String categoryName,
  }) async {
    final category = repository.query(
      'SELECT id FROM categories WHERE name=? AND deleted_at IS NULL LIMIT 1',
      [categoryName],
    );
    if (category.isEmpty) throw StateError('Category is not configured');
    repository.execute(
      "UPDATE transactions SET amount_satang=?,category_id=?,updated_at=? WHERE id=? AND source='manual' AND type='expense' AND deleted_at IS NULL",
      [
        amount.satang,
        category.first['id'],
        DateTime.now().toUtc().toIso8601String(),
        id,
      ],
    );
  }

  Future<void> softDeleteTransaction(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    repository.execute(
      "UPDATE transactions SET deleted_at=?,updated_at=? WHERE id=? AND source='manual' AND deleted_at IS NULL",
      [now, now, id],
    );
  }

  Future<void> restoreTransaction(String id) async {
    repository.execute(
      "UPDATE transactions SET deleted_at=NULL,updated_at=? WHERE id=? AND source='manual' AND deleted_at IS NOT NULL",
      [DateTime.now().toUtc().toIso8601String(), id],
    );
  }

  Future<void> configureInstallment({
    required String id,
    required String name,
    required Money total,
    required Money paid,
    required Money regular,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    repository.execute('BEGIN IMMEDIATE');
    try {
      repository.execute(
        "INSERT OR REPLACE INTO installments(id,category_id,name,amount_satang,due_day,start_date,total_payable_satang,regular_payment_satang,status,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?,?)",
        [
          id,
          'personal',
          name,
          regular.satang,
          1,
          now.split('T').first,
          total.satang,
          regular.satang,
          'active',
          now,
          now,
        ],
      );
      repository.execute(
        "DELETE FROM commitment_occurrences WHERE installment_id=?",
        [id],
      );
      if (paid.satang > 0) {
        final transactionId = _uuid.v4();
        repository.execute(
          "INSERT INTO transactions(id,account_id,category_id,type,amount_satang,occurred_at,source,note,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?,?)",
          [
            transactionId,
            _accountId,
            'personal',
            'expense',
            paid.satang,
            now,
            'manual',
            'ยอดชำระสะสมที่ผู้ใช้ยืนยัน',
            now,
            now,
          ],
        );
        repository.execute(
          "INSERT INTO commitment_occurrences(id,installment_id,due_date,planned_amount_satang,linked_transaction_id,created_at,updated_at) VALUES(?,?,?,?,?,?,?)",
          [
            _uuid.v4(),
            id,
            now.split('T').first,
            paid.satang,
            transactionId,
            now,
            now,
          ],
        );
      }
      repository.execute('COMMIT');
    } catch (_) {
      repository.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<InstallmentProgress?> loadInstallmentProgress(String id) async {
    final installments = repository.query(
      'SELECT total_payable_satang,regular_payment_satang FROM installments WHERE id=? AND deleted_at IS NULL',
      [id],
    );
    if (installments.isEmpty) return null;
    final row = installments.single;
    final payments = repository.query(
      "SELECT t.amount_satang,t.type FROM commitment_occurrences o JOIN transactions t ON t.id=o.linked_transaction_id WHERE o.installment_id=? AND o.deleted_at IS NULL AND t.deleted_at IS NULL",
      [id],
    );
    return FinancialRules.installmentProgress(
      totalPayable: row['total_payable_satang'] == null
          ? null
          : Money.fromSatang(row['total_payable_satang'] as int),
      regularPayment: row['regular_payment_satang'] == null
          ? null
          : Money.fromSatang(row['regular_payment_satang'] as int),
      confirmedPayments: payments
          .where((e) => e['type'] == 'expense')
          .map((e) => Money.fromSatang(e['amount_satang'] as int)),
      linkedRefunds: payments
          .where((e) => e['type'] == 'refund')
          .map((e) => Money.fromSatang(e['amount_satang'] as int)),
    );
  }
}
