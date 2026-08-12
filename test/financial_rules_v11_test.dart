import 'package:flutter_test/flutter_test.dart';
import 'package:ngoen_ku_pai_nai/core/money.dart';
import 'package:ngoen_ku_pai_nai/domain/financial_rules.dart';

Money b(num value) => Money.fromBaht(value);

void main() {
  group('Financial Core v1.1 installment progress', () {
    test('16000 paid from 27000 gives 59.26 percent and 11 payments', () {
      final result = FinancialRules.installmentProgress(
        totalPayable: b(27000),
        regularPayment: b(1000),
        confirmedPayments: [b(16000)],
        linkedRefunds: const [],
      );
      expect(result.paid, b(16000));
      expect(result.remaining, b(11000));
      expect(result.progressRatio, closeTo(0.592592, 0.000001));
      expect(result.estimatedRemainingPayments, 11);
    });
    test('partial and extra payments derive from ledger', () {
      final result = FinancialRules.installmentProgress(
        totalPayable: b(27000),
        regularPayment: b(1000),
        confirmedPayments: [b(500), b(2500)],
        linkedRefunds: const [],
      );
      expect(result.paid, b(3000));
      expect(result.estimatedRemainingPayments, 24);
    });
    test('early payoff and final smaller payment complete contract', () {
      final result = FinancialRules.installmentProgress(
        totalPayable: b(27000),
        regularPayment: b(1000),
        confirmedPayments: [b(26000), b(1000)],
        linkedRefunds: const [],
      );
      expect(result.remaining, Money.zero);
      expect(result.estimatedRemainingPayments, 0);
    });
    test('refund reduces paid amount', () {
      final result = FinancialRules.installmentProgress(
        totalPayable: b(27000),
        regularPayment: b(1000),
        confirmedPayments: [b(16000)],
        linkedRefunds: [b(1000)],
      );
      expect(result.paid, b(15000));
      expect(result.remaining, b(12000));
    });
    test('overpayment remains visible instead of clamping paid', () {
      final result = FinancialRules.installmentProgress(
        totalPayable: b(27000),
        regularPayment: b(1000),
        confirmedPayments: [b(28000)],
        linkedRefunds: const [],
      );
      expect(result.paid, b(28000));
      expect(result.remaining, Money.zero);
      expect(result.overpayment, b(1000));
      expect(result.progressRatio, greaterThan(1));
    });
    test('unknown total and regular payment are safe', () {
      final unknown = FinancialRules.installmentProgress(
        totalPayable: null,
        regularPayment: null,
        confirmedPayments: [b(1000)],
        linkedRefunds: const [],
      );
      expect(unknown.progressRatio, isNull);
      expect(unknown.estimatedRemainingPayments, isNull);
      final noRegular = FinancialRules.installmentProgress(
        totalPayable: b(27000),
        regularPayment: null,
        confirmedPayments: [b(1000)],
        linkedRefunds: const [],
      );
      expect(noRegular.estimatedRemainingPayments, isNull);
    });
  });
}
