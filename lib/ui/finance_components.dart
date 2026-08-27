import 'package:flutter/material.dart';

import '../core/money.dart';
import 'theme/app_theme.dart';

abstract final class FinanceMoneyFormat {
  static String satang(int satang, {bool signed = false}) {
    final negative = satang < 0;
    final absolute = satang.abs();
    final baht = absolute ~/ 100;
    final fraction = (absolute % 100).toString().padLeft(2, '0');
    final grouped = baht.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    final prefix = negative ? '-' : (signed && satang > 0 ? '+' : '');
    return '$prefix฿$grouped.$fraction';
  }

  static String money(Money value, {bool signed = false}) =>
      satang(value.satang, signed: signed);
}

class FinanceAmountText extends StatelessWidget {
  const FinanceAmountText({
    required this.satang,
    this.signed = false,
    this.color,
    this.style,
    this.textAlign,
    super.key,
  });

  final int satang;
  final bool signed;
  final Color? color;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final label = FinanceMoneyFormat.satang(satang, signed: signed);
    return Semantics(
      label: 'จำนวนเงิน $label',
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: textAlign == TextAlign.end
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Text(
          label,
          maxLines: 1,
          textAlign: textAlign,
          style: style?.copyWith(color: color) ?? TextStyle(color: color),
        ),
      ),
    );
  }
}

class FinanceEmptyState extends StatelessWidget {
  const FinanceEmptyState({
    required this.icon,
    required this.message,
    super.key,
  });
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.muted),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
