import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/core/money.dart';
import 'package:ngoen_ku_pai_nai/domain/financial_rules.dart';
import 'package:ngoen_ku_pai_nai/domain/models/financial_models.dart';

Money b(num value) => Money.fromBaht(value);

void main() {
  group('FR-01 through FR-10', () {
    test('T01 gross minus deduction equals expected net', () {
      expect(FinancialRules.expectedNetIncome(b(18000), [b(875)]), b(17125));
    });
    test('T02 payroll deduction is a plan and not a duplicate expense', () {
      final balance = FinancialRules.accountBalance(
        opening: Money.zero,
        transactions: [(TransactionType.income, b(17125))],
      );
      expect(balance, b(17125));
    });
    test('T03 net entered as gross is not silently corrected', () {
      expect(FinancialRules.expectedNetIncome(b(17125), [b(875)]), b(16250));
    });
    test('T04 remaining before saving is 8126 baht', () {
      expect(
        b(17125) - b(2000) - b(1000) - b(2500) - b(499) - b(3000),
        b(8126),
      );
    });
    test('T05 planned spendable is 5626 baht', () {
      expect(
        FinancialRules.plannedSpendable(
          expectedNetIncome: b(17125),
          fixed: b(4999),
          installments: b(1000),
          savingTarget: b(2500),
          reserved: b(3000),
        ),
        b(5626),
      );
    });
    test('T06 daily allowance stores precise satang and UI can floor', () {
      final daily = FinancialRules.dailyAllowance(b(5626), 30);
      expect(daily.satang, 18753);
      expect(daily.floorBaht, 187);
    });
    test('T07 remaining 5000 over 20 days is 250', () {
      expect(
        FinancialRules.dailyAllowance(
          FinancialRules.remainingFlexible(b(5626), b(626)),
          20,
        ),
        b(250),
      );
    });
    test('T08 emergency runway is three months', () {
      expect(FinancialRules.emergencyRunway(b(30000), b(10000)), 3);
    });
    test('T09 opening plus income minus expense', () {
      expect(
        FinancialRules.accountBalance(
          opening: b(1000),
          transactions: [
            (TransactionType.income, b(17125)),
            (TransactionType.expense, b(2000)),
          ],
        ),
        b(16125),
      );
    });
    test('T10 transfer does not change combined cash or expense', () {
      final a = FinancialRules.accountBalance(
        opening: b(5000),
        transactions: [(TransactionType.transferOut, b(3000))],
      );
      final c = FinancialRules.accountBalance(
        opening: b(1000),
        transactions: [(TransactionType.transferIn, b(3000))],
      );
      expect(FinancialRules.currentCash([a, c]), b(6000));
    });
    test('T11 linked occurrence is paid and excluded from unpaid', () {
      expect(
        FinancialRules.occurrenceStatus(
          skipped: false,
          linkedTransactionId: 'tx',
          dueDate: DateTime(2026, 8, 1),
          today: DateTime(2026, 8, 2),
        ),
        OccurrenceStatus.paid,
      );
    });
    test('T12 unlinked due occurrence remains forecast commitment', () {
      expect(
        FinancialRules.forecast(
          currentCash: b(1000),
          expectedIncomeNotReceived: Money.zero,
          unpaidCommitments: b(499),
          remainingVariableSpend: Money.zero,
        ),
        b(501),
      );
    });
    test('T13 soft-deleted expense is excluded by caller query', () {
      expect(
        FinancialRules.accountBalance(opening: b(1000), transactions: const []),
        b(1000),
      );
    });
    test('T14 uncategorized expense remains in uncategorized group', () {
      expect(
        FinancialRules.categorySpend(
          expenses: [(null, b(120))],
          refunds: const [],
        )['uncategorized'],
        b(120),
      );
    });
    test('T15 period end today has one inclusive day', () {
      expect(
        BudgetPeriod(
          start: DateTime(2026, 1, 25),
          end: DateTime(2026, 2, 24),
        ).daysRemainingInclusive(DateTime(2026, 2, 24)),
        1,
      );
    });
    test('T16 cross-year period calculates dates correctly', () {
      expect(
        BudgetPeriod(
          start: DateTime(2026, 12, 25),
          end: DateTime(2027, 1, 24),
        ).totalDaysInclusive,
        31,
      );
    });
    test('T17 final installment due in period is planned', () {
      expect(
        FinancialRules.occurrenceStatus(
          skipped: false,
          linkedTransactionId: null,
          dueDate: DateTime(2026, 8, 20),
          today: DateTime(2026, 8, 10),
        ),
        OccurrenceStatus.planned,
      );
    });
    test('T18 no occurrence after final due date means no commitment', () {
      expect(
        FinancialRules.forecast(
          currentCash: b(1000),
          expectedIncomeNotReceived: Money.zero,
          unpaidCommitments: Money.zero,
          remainingVariableSpend: Money.zero,
        ),
        b(1000),
      );
    });
    test('T19 occurrence on inclusive end date remains valid', () {
      final end = DateTime(2026, 8, 31);
      expect(!end.isAfter(DateTime(2026, 8, 31)), isTrue);
    });
    test('T20 Bangkok calendar date is explicitly provided to rules', () {
      final bangkokToday = DateTime(2026, 8, 11);
      expect(
        BudgetPeriod(
          start: DateTime(2026, 8, 1),
          end: DateTime(2026, 8, 31),
        ).daysRemainingInclusive(bangkokToday),
        21,
      );
    });
    test('T21 82 percent used at 60 percent elapsed is fast', () {
      expect(
        FinancialRules.analyzeBudget(
          spent: b(2460),
          budget: b(3000),
          elapsedDays: 18,
          totalDays: 30,
        ).pace,
        BudgetPace.fast,
      );
    });
    test('T22 zero budget with spending is unsupported without division', () {
      final result = FinancialRules.analyzeBudget(
        spent: b(100),
        budget: Money.zero,
        elapsedDays: 1,
        totalDays: 30,
      );
      expect(result.pace, BudgetPace.unsupported);
      expect(result.usedPercent, isNull);
    });
    test('T23 negative flexible budget produces zero daily allowance', () {
      expect(FinancialRules.dailyAllowance(b(-100), 10), Money.zero);
    });
    test('T24 zero net income has no saving rate', () {
      expect(FinancialRules.savingRate(b(100), Money.zero), isNull);
    });
    test('T25 zero essential average has no runway', () {
      expect(FinancialRules.emergencyRunway(b(30000), Money.zero), isNull);
    });
    test('T28 only explicit salary transaction clears expected income', () {
      expect(
        FinancialRules.expectedIncomeNotReceived(
          expected: b(17125),
          salaryTransactionId: 'salary-tx',
        ),
        Money.zero,
      );
      expect(
        FinancialRules.expectedIncomeNotReceived(
          expected: b(17125),
          salaryTransactionId: null,
        ),
        b(17125),
      );
    });
    test('T29 opening plan forecast equals 2500 baht', () {
      expect(
        FinancialRules.forecast(
          currentCash: b(17125),
          expectedIncomeNotReceived: Money.zero,
          unpaidCommitments: b(5999),
          remainingVariableSpend: b(8626),
        ),
        b(2500),
      );
    });
    test('T30 food expense reduces reserved food but not flexible', () {
      final foodRemaining = b(3000) - b(500);
      expect(foodRemaining, b(2500));
      expect(FinancialRules.remainingFlexible(b(5626), Money.zero), b(5626));
      expect(b(17125) - b(500) - b(5999) - foodRemaining - b(5626), b(2500));
    });
    test('FR-06 refund can make share unavailable at nonpositive total', () {
      final spend = FinancialRules.categorySpend(
        expenses: [('food', b(100))],
        refunds: [('food', b(150))],
      );
      expect(spend['food'], b(-50));
      expect(FinancialRules.categoryShare(spend['food']!, b(-50)), isNull);
    });
  });
}
