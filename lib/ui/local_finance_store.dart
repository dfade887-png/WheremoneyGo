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

final class OnboardingAccountInput {
  OnboardingAccountInput({
    required this.id,
    required this.name,
    required this.type,
    required this.openingBalance,
  });
  final String id;
  String name, type;
  Money openingBalance;
}

final class LocalFinanceStore {
  LocalFinanceStore._(this.repository);
  final SqliteFinanceRepository repository;
  static const _uuid = Uuid();
  static const _profileKey = 'onboarding_profile_v1';
  String get _accountId =>
      repository.activeProfileId == 'legacy-default-profile'
      ? 'primary-account'
      : 'primary-account-${repository.activeProfileId}';

  String _scopedId(String legacyId) =>
      repository.activeProfileId == 'legacy-default-profile'
      ? legacyId
      : '$legacyId-${repository.activeProfileId}';

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

  String get activeProfileId => repository.activeProfileId;
  Future<List<Map<String, Object?>>> profiles({bool includeArchived = true}) =>
      repository.profiles(includeArchived: includeArchived);
  Future<String> createProfile(String name) => repository.createProfile(name);
  Future<void> switchProfile(String id) => repository.switchProfile(id);
  Future<void> renameProfile(String id, String name) =>
      repository.renameProfile(id, name);
  Future<void> archiveProfile(String id) => repository.archiveProfile(id);
  Future<void> restoreProfile(String id) => repository.restoreProfile(id);

  Future<List<Map<String, Object?>>> accounts({bool includeArchived = true}) =>
      repository.accounts(includeArchived: includeArchived);

  Future<List<Map<String, Object?>>> categories({String? type}) =>
      repository.categories(type: type);

  Future<List<Map<String, Object?>>> activity({bool includeDeleted = false}) =>
      repository.activity(includeDeleted: includeDeleted);

  Future<Map<String, Object?>> projectionInputs() async {
    final profile = repository.activeProfileId;
    final budgets = repository.query(
      '''SELECT b.category_id,c.name category_name,b.amount_satang,b.budget_type FROM period_budgets b LEFT JOIN categories c ON c.id=b.category_id WHERE b.profile_id=? AND b.deleted_at IS NULL''',
      [profile],
    );
    final unpaid =
        repository
                .query(
                  '''SELECT COALESCE(SUM(planned_amount_satang),0) total FROM commitment_occurrences WHERE profile_id=? AND linked_transaction_id IS NULL AND is_skipped=0 AND deleted_at IS NULL''',
                  [profile],
                )
                .single['total']
            as int;
    final saving =
        repository.query(
              'SELECT COALESCE(SUM(monthly_target_satang),0) total FROM saving_goals WHERE profile_id=? AND deleted_at IS NULL',
              [profile],
            ).single['total']
            as int;
    final reserveRows = repository.query(
      "SELECT value FROM profile_settings WHERE profile_id=? AND key='minimum_reserve_satang' AND deleted_at IS NULL",
      [profile],
    );
    return {
      'categoryBudgets': budgets
          .where((b) => b['category_id'] != null)
          .toList(),
      'unpaidObligationsSatang': unpaid,
      'plannedFlexibleSpendSatang': budgets
          .where(
            (b) =>
                b['budget_type'] == 'flexible' ||
                b['budget_type'] == 'reserved',
          )
          .fold<int>(0, (sum, b) => sum + (b['amount_satang'] as int)),
      'savingReservationSatang': saving,
      'savingGoalSatang': saving,
      'minimumReserveSatang': reserveRows.isEmpty
          ? 0
          : int.tryParse(reserveRows.single['value'] as String) ?? 0,
      'expectedIncomeRemainingSatang': 0,
    };
  }

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
      'SELECT value FROM profile_settings WHERE profile_id=? AND key=? AND deleted_at IS NULL',
      [repository.activeProfileId, _profileKey],
    );
    if (rows.isEmpty) return null;
    final json =
        jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
    final food =
        repository.query(
              "SELECT COALESCE(SUM(t.amount_satang),0) AS total FROM transactions t JOIN categories c ON c.id=t.category_id WHERE t.profile_id=? AND t.type='expense' AND t.deleted_at IS NULL AND c.name='อาหาร'",
              [repository.activeProfileId],
            ).first['total']
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
    if (profile.payday < 1 || profile.payday > 31) {
      throw ArgumentError.value(profile.payday, 'payday');
    }
    if (profile.accountName.trim().isEmpty) {
      throw ArgumentError.value(profile.accountName, 'accountName');
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final value = jsonEncode({
      'payday': profile.payday,
      'holidayRule': profile.holidayRule,
      'accountName': profile.accountName,
      'openingBalanceSatang': profile.openingBalance.satang,
      'savingTargetSatang': profile.savingTarget.satang,
      'emergencyTargetSatang': profile.emergencyTarget.satang,
    });
    repository.execute('BEGIN IMMEDIATE');
    try {
      repository.execute(
        '''INSERT INTO profile_settings(id,profile_id,key,value,created_at,updated_at)
         VALUES(?,?,?,?,?,?) ON CONFLICT(profile_id,key) DO UPDATE SET
         value=excluded.value,updated_at=excluded.updated_at,deleted_at=NULL''',
        [_uuid.v4(), repository.activeProfileId, _profileKey, value, now, now],
      );
      repository.execute(
        '''INSERT INTO profile_settings(id,profile_id,key,value,created_at,updated_at)
         VALUES(?,?,?,?,?,?) ON CONFLICT(profile_id,key) DO UPDATE SET
         value=excluded.value,updated_at=excluded.updated_at,deleted_at=NULL''',
        [
          _uuid.v4(),
          repository.activeProfileId,
          'data_mode',
          'production',
          now,
          now,
        ],
      );
      repository.execute(
        '''INSERT INTO accounts(id,name,opening_balance_satang,is_active,include_in_net_worth,created_at,updated_at,profile_id)
         VALUES(?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
         name=excluded.name,opening_balance_satang=excluded.opening_balance_satang,
         is_active=1,updated_at=excluded.updated_at''',
        [
          _accountId,
          profile.accountName,
          profile.openingBalance.satang,
          1,
          1,
          now,
          now,
          repository.activeProfileId,
        ],
      );
      for (final category in const [
        ('food', 'อาหาร', 1, 'expense'),
        ('travel', 'เดินทาง', 1, 'expense'),
        ('personal', 'ใช้ส่วนตัว', 0, 'expense'),
        ('family', 'ครอบครัว', 1, 'expense'),
        ('salary', 'เงินเดือน', 0, 'income'),
        ('other-income', 'รายรับอื่น', 0, 'income'),
      ]) {
        repository.execute(
          'INSERT OR IGNORE INTO categories(id,name,is_essential,category_type,created_at,updated_at,profile_id) VALUES(?,?,?,?,?,?,?)',
          [
            _scopedId(category.$1),
            category.$2,
            category.$3,
            category.$4,
            now,
            now,
            repository.activeProfileId,
          ],
        );
      }
      repository.execute('COMMIT');
    } catch (_) {
      repository.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<void> saveOnboardingProfile(
    LocalProfile profile, {
    required List<OnboardingAccountInput> accounts,
    required String salaryAccountDraftId,
    String? savingsAccountDraftId,
  }) async {
    await saveProfile(profile);
    final now = DateTime.now().toUtc().toIso8601String();
    for (final draft in accounts) {
      final id = draft.id == salaryAccountDraftId
          ? _accountId
          : _scopedId('account-${draft.id}');
      repository.execute(
        '''INSERT INTO accounts(id,name,opening_balance_satang,is_active,include_in_net_worth,account_type,is_salary_account,created_at,updated_at,profile_id)
           VALUES(?,?,?,?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET
           name=excluded.name,opening_balance_satang=excluded.opening_balance_satang,
           account_type=excluded.account_type,is_salary_account=excluded.is_salary_account,
           is_active=1,updated_at=excluded.updated_at''',
        [
          id,
          draft.name.trim(),
          draft.openingBalance.satang,
          1,
          1,
          draft.type,
          draft.id == salaryAccountDraftId ? 1 : 0,
          now,
          now,
          repository.activeProfileId,
        ],
      );
      if (draft.id == savingsAccountDraftId) {
        repository.execute(
          '''INSERT INTO profile_settings(id,profile_id,key,value,created_at,updated_at)
             VALUES(?,?,?,?,?,?) ON CONFLICT(profile_id,key) DO UPDATE SET
             value=excluded.value,updated_at=excluded.updated_at,deleted_at=NULL''',
          [
            _uuid.v4(),
            repository.activeProfileId,
            'savings_account_id',
            id,
            now,
            now,
          ],
        );
      }
    }
  }

  Future<String> addExpense({
    required Money amount,
    required String categoryName,
  }) async {
    final categories = repository.query(
      'SELECT id FROM categories WHERE profile_id=? AND name=? AND deleted_at IS NULL LIMIT 1',
      [repository.activeProfileId, categoryName],
    );
    if (categories.isEmpty) throw StateError('Category is not configured');
    return repository.createTransaction(
      accountId: _accountId,
      categoryId: categories.first['id'] as String,
      type: 'expense',
      amountSatang: amount.satang,
    );
  }

  Future<void> editExpense(
    String id, {
    required Money amount,
    required String categoryName,
  }) async {
    final category = repository.query(
      'SELECT id FROM categories WHERE profile_id=? AND name=? AND deleted_at IS NULL LIMIT 1',
      [repository.activeProfileId, categoryName],
    );
    if (category.isEmpty) throw StateError('Category is not configured');
    repository.execute(
      "UPDATE transactions SET amount_satang=?,category_id=?,updated_at=? WHERE id=? AND profile_id=? AND source='manual' AND type='expense' AND deleted_at IS NULL",
      [
        amount.satang,
        category.first['id'],
        DateTime.now().toUtc().toIso8601String(),
        id,
        repository.activeProfileId,
      ],
    );
  }

  Future<void> softDeleteTransaction(String id) async {
    final now = DateTime.now().toUtc().toIso8601String();
    repository.execute(
      "UPDATE transactions SET deleted_at=?,updated_at=? WHERE id=? AND profile_id=? AND source='manual' AND deleted_at IS NULL",
      [now, now, id, repository.activeProfileId],
    );
  }

  Future<void> restoreTransaction(String id) async {
    repository.execute(
      "UPDATE transactions SET deleted_at=NULL,updated_at=? WHERE id=? AND profile_id=? AND source='manual' AND deleted_at IS NOT NULL",
      [
        DateTime.now().toUtc().toIso8601String(),
        id,
        repository.activeProfileId,
      ],
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
    final installmentId = _scopedId(id);
    final personalCategoryId = _scopedId('personal');
    final openingProgressKey = 'installment_opening_paid:$installmentId';
    repository.execute('BEGIN IMMEDIATE');
    try {
      repository.execute(
        "INSERT OR REPLACE INTO installments(id,category_id,name,amount_satang,due_day,start_date,total_payable_satang,regular_payment_satang,status,created_at,updated_at,profile_id) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)",
        [
          installmentId,
          personalCategoryId,
          name,
          regular.satang,
          1,
          now.split('T').first,
          total.satang,
          regular.satang,
          'active',
          now,
          now,
          repository.activeProfileId,
        ],
      );
      repository.execute(
        '''INSERT INTO profile_settings(id,profile_id,key,value,created_at,updated_at)
           VALUES(?,?,?,?,?,?) ON CONFLICT(profile_id,key) DO UPDATE SET
           value=excluded.value,updated_at=excluded.updated_at,deleted_at=NULL''',
        [
          _uuid.v4(),
          repository.activeProfileId,
          openingProgressKey,
          paid.satang.toString(),
          now,
          now,
        ],
      );
      repository.execute('COMMIT');
    } catch (_) {
      repository.execute('ROLLBACK');
      rethrow;
    }
  }

  Future<InstallmentProgress?> loadInstallmentProgress(String id) async {
    final installmentId = _scopedId(id);
    final installments = repository.query(
      'SELECT total_payable_satang,regular_payment_satang FROM installments WHERE id=? AND profile_id=? AND deleted_at IS NULL',
      [installmentId, repository.activeProfileId],
    );
    if (installments.isEmpty) return null;
    final row = installments.single;
    final openingRows = repository.query(
      'SELECT value FROM profile_settings WHERE profile_id=? AND key=? AND deleted_at IS NULL',
      [repository.activeProfileId, 'installment_opening_paid:$installmentId'],
    );
    final openingPaid = openingRows.isEmpty
        ? 0
        : int.tryParse(openingRows.single['value'] as String) ?? 0;
    final payments = repository.query(
      "SELECT t.amount_satang,t.type FROM commitment_occurrences o JOIN transactions t ON t.id=o.linked_transaction_id WHERE o.installment_id=? AND o.deleted_at IS NULL AND t.deleted_at IS NULL",
      [installmentId],
    );
    return FinancialRules.installmentProgress(
      totalPayable: row['total_payable_satang'] == null
          ? null
          : Money.fromSatang(row['total_payable_satang'] as int),
      regularPayment: row['regular_payment_satang'] == null
          ? null
          : Money.fromSatang(row['regular_payment_satang'] as int),
      confirmedPayments: [
        if (openingPaid > 0) Money.fromSatang(openingPaid),
        ...payments
            .where((e) => e['type'] == 'expense')
            .map((e) => Money.fromSatang(e['amount_satang'] as int)),
      ],
      linkedRefunds: payments
          .where((e) => e['type'] == 'refund')
          .map((e) => Money.fromSatang(e['amount_satang'] as int)),
    );
  }
}
