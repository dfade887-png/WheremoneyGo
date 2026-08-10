import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/money.dart';
import '../data/repositories/sqlite_finance_repository.dart';

final class LocalProfile {
  const LocalProfile({required this.payday, required this.holidayRule, required this.accountName, required this.openingBalance, required this.savingTarget, required this.emergencyTarget, required this.foodSpent});
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
    return LocalFinanceStore._(SqliteFinanceRepository.file(p.join(directory.path, 'ngoen_ku_pai_nai.sqlite')));
  }
  static LocalFinanceStore memory() => LocalFinanceStore._(SqliteFinanceRepository.memory());

  Future<LocalProfile?> loadProfile() async {
    final rows = repository.query('SELECT value FROM app_settings WHERE key = ? AND deleted_at IS NULL', [_profileKey]);
    if (rows.isEmpty) return null;
    final json = jsonDecode(rows.first['value'] as String) as Map<String, dynamic>;
    final food = repository.query("SELECT COALESCE(SUM(t.amount_satang),0) AS total FROM transactions t JOIN categories c ON c.id=t.category_id WHERE t.type='expense' AND t.deleted_at IS NULL AND c.name='อาหาร'").first['total'] as int;
    final movement = repository.query("SELECT COALESCE(SUM(CASE WHEN type IN ('income','refund','transfer_in') THEN amount_satang WHEN type IN ('expense','transfer_out') THEN -amount_satang WHEN type='balance_adjustment' THEN amount_satang ELSE 0 END),0) AS total FROM transactions WHERE deleted_at IS NULL AND account_id=?", [_accountId]).first['total'] as int;
    return LocalProfile(
      payday: json['payday'] as int, holidayRule: json['holidayRule'] as String, accountName: json['accountName'] as String,
      openingBalance: Money.fromSatang((json['openingBalanceSatang'] as int) + movement), savingTarget: Money.fromSatang(json['savingTargetSatang'] as int),
      emergencyTarget: Money.fromSatang(json['emergencyTargetSatang'] as int), foodSpent: Money.fromSatang(food),
    );
  }

  Future<void> saveProfile(LocalProfile profile) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final value = jsonEncode({'payday': profile.payday, 'holidayRule': profile.holidayRule, 'accountName': profile.accountName, 'openingBalanceSatang': profile.openingBalance.satang, 'savingTargetSatang': profile.savingTarget.satang, 'emergencyTargetSatang': profile.emergencyTarget.satang});
    repository.execute('INSERT OR REPLACE INTO app_settings(id,key,value,created_at,updated_at) VALUES(COALESCE((SELECT id FROM app_settings WHERE key=?),?),?,?,?,?)', [_profileKey, _uuid.v4(), _profileKey, value, now, now]);
    repository.execute('INSERT OR REPLACE INTO accounts(id,name,opening_balance_satang,is_active,include_in_net_worth,created_at,updated_at) VALUES(?,?,?,?,?,?,?)', [_accountId, profile.accountName, profile.openingBalance.satang, 1, 1, now, now]);
    for (final category in const [('food', 'อาหาร', 1), ('travel', 'เดินทาง', 1), ('personal', 'ใช้ส่วนตัว', 0), ('family', 'ครอบครัว', 1)]) {
      repository.execute('INSERT OR IGNORE INTO categories(id,name,is_essential,created_at,updated_at) VALUES(?,?,?,?,?)', [category.$1, category.$2, category.$3, now, now]);
    }
  }

  Future<void> addExpense({required Money amount, required String categoryName}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final categories = repository.query('SELECT id FROM categories WHERE name=? AND deleted_at IS NULL LIMIT 1', [categoryName]);
    if (categories.isEmpty) throw StateError('Category is not configured');
    repository.execute('INSERT INTO transactions(id,account_id,category_id,type,amount_satang,occurred_at,source,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?,?)', [_uuid.v4(), _accountId, categories.first['id'], 'expense', amount.satang, now, 'manual', now, now]);
  }
}
