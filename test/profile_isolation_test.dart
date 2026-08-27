import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/data/repositories/sqlite_finance_repository.dart';

void main() {
  late SqliteFinanceRepository repository;
  setUp(() => repository = SqliteFinanceRepository.memory());
  tearDown(() => repository.dispose());

  test('existing database is assigned to default profile', () async {
    expect(await repository.schemaVersion(), 5);
    expect(repository.activeProfileId, 'legacy-default-profile');
    expect((await repository.profiles()).single['name'], 'ข้อมูลเดิม');
  });

  test(
    'profile switch isolates accounts categories and transactions',
    () async {
      final oldAccount = await repository.createAccount(
        name: 'ทดลอง',
        type: 'bank',
        openingBalanceSatang: -6100000,
      );
      final oldCategory = await repository.createCategory(
        name: 'อาหารทดลอง',
        type: 'expense',
        iconKey: 'restaurant',
      );
      await repository.createTransaction(
        accountId: oldAccount,
        categoryId: oldCategory,
        type: 'expense',
        amountSatang: 10000,
      );

      final real = await repository.createProfile('ใช้งานจริง — สิงหาคม 2569');
      await repository.switchProfile(real);
      expect(await repository.accounts(), isEmpty);
      expect(await repository.activity(), isEmpty);
      final realAccount = await repository.createAccount(
        name: 'เงินเดือน',
        type: 'bank',
        openingBalanceSatang: 1000000,
      );
      final realCategory = await repository.createCategory(
        name: 'อาหาร',
        type: 'expense',
        iconKey: 'restaurant',
      );
      await repository.createTransaction(
        accountId: realAccount,
        categoryId: realCategory,
        type: 'expense',
        amountSatang: 5000,
      );
      expect((await repository.accounts()).single['balance_satang'], 995000);

      await repository.switchProfile('legacy-default-profile');
      expect((await repository.accounts()).single['balance_satang'], -6110000);
      expect(await repository.activity(), hasLength(1));
    },
  );

  test('cross-profile transaction and transfer are rejected', () async {
    final oldAccount = await repository.createAccount(
      name: 'Old',
      type: 'bank',
      openingBalanceSatang: 0,
    );
    final oldCategory = await repository.createCategory(
      name: 'Old category',
      type: 'expense',
      iconKey: 'category',
    );
    final next = await repository.createProfile('Next');
    await repository.switchProfile(next);
    final newAccount = await repository.createAccount(
      name: 'New',
      type: 'bank',
      openingBalanceSatang: 0,
    );
    expect(
      () => repository.createTransaction(
        accountId: newAccount,
        categoryId: oldCategory,
        type: 'expense',
        amountSatang: 100,
      ),
      throwsStateError,
    );
    expect(
      () => repository.createTransfer(
        fromAccountId: newAccount,
        toAccountId: oldAccount,
        amountSatang: 100,
      ),
      throwsStateError,
    );
  });

  test('active profile cannot be archived', () async {
    expect(
      () => repository.archiveProfile(repository.activeProfileId),
      throwsStateError,
    );
  });
}
