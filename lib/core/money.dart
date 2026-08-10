import 'dart:math' as math;

final class Money implements Comparable<Money> {
  const Money.fromSatang(this.satang);

  factory Money.fromBaht(num baht) {
    if (!baht.isFinite) throw const FormatException('Money must be finite');
    return Money.fromSatang((baht * 100).round());
  }

  static const zero = Money.fromSatang(0);
  final int satang;

  Money operator +(Money other) => Money.fromSatang(satang + other.satang);
  Money operator -(Money other) => Money.fromSatang(satang - other.satang);
  Money operator -() => Money.fromSatang(-satang);
  Money abs() => Money.fromSatang(satang.abs());
  Money max(Money other) => Money.fromSatang(math.max(satang, other.satang));

  int get floorBaht => satang ~/ 100;
  double get baht => satang / 100;
  bool get isPositive => satang > 0;
  bool get isNegative => satang < 0;

  @override
  int compareTo(Money other) => satang.compareTo(other.satang);

  @override
  bool operator ==(Object other) => other is Money && other.satang == satang;

  @override
  int get hashCode => satang.hashCode;

  @override
  String toString() => 'Money($satang satang)';
}
