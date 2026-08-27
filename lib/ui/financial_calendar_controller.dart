import 'package:flutter/foundation.dart';

import '../domain/financial_calendar.dart';
import '../domain/projected_balance.dart';
import '../domain/repositories/financial_calendar_repository.dart';
import '../domain/repositories/projected_balance_repository.dart';
import '../domain/repositories/scheduled_financial_event_repository.dart';

final class FinancialCalendarController extends ChangeNotifier {
  FinancialCalendarController({
    required FinancialCalendarRepository calendarRepository,
    required ProjectedBalanceRepository projectedBalanceRepository,
    required ScheduledFinancialEventRepository confirmationRepository,
    DateTime Function()? now,
  }) : this._(
         calendarRepository,
         projectedBalanceRepository,
         confirmationRepository,
         now ?? DateTime.now,
       );

  FinancialCalendarController._(
    this._calendarRepository,
    this._projectedBalanceRepository,
    this._confirmationRepository,
    this._now,
  ) : visibleMonth = DateTime(_now().year, _now().month),
      selectedDate = DateTime(_now().year, _now().month, _now().day);

  final FinancialCalendarRepository _calendarRepository;
  final ProjectedBalanceRepository _projectedBalanceRepository;
  final ScheduledFinancialEventRepository _confirmationRepository;
  final DateTime Function() _now;

  DateTime visibleMonth;
  DateTime selectedDate;
  FinancialCalendarResult? calendarResult;
  ProjectedBalanceResult? projectedBalance;
  bool loading = false;
  bool confirmationInProgress = false;
  String? error;

  List<FinancialCalendarEvent> get selectedDayEvents => eventsFor(selectedDate);

  List<FinancialCalendarEvent> eventsFor(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return (calendarResult?.events ?? const <FinancialCalendarEvent>[])
        .where((event) {
          final local = event.dateTime.toLocal();
          return DateTime(local.year, local.month, local.day) == day;
        })
        .toList(growable: false);
  }

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      final fromLocal = DateTime(visibleMonth.year, visibleMonth.month);
      final toLocal = DateTime(
        visibleMonth.year,
        visibleMonth.month + 1,
      ).subtract(const Duration(microseconds: 1));
      calendarResult = await _calendarRepository.calendarEvents(
        from: fromLocal.toUtc(),
        to: toLocal.toUtc(),
        now: _now().toUtc(),
      );
      await _loadProjection();
    } catch (_) {
      error = 'โหลดปฏิทินการเงินไม่สำเร็จ ลองใหม่อีกครั้ง';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectDate(DateTime value) async {
    selectedDate = DateTime(value.year, value.month, value.day);
    error = null;
    notifyListeners();
    try {
      await _loadProjection();
    } catch (_) {
      error = 'โหลดข้อมูลคาดการณ์ไม่สำเร็จ ลองใหม่อีกครั้ง';
      notifyListeners();
    }
  }

  Future<void> previousMonth() => _changeMonth(-1);
  Future<void> nextMonth() => _changeMonth(1);

  Future<void> _changeMonth(int delta) async {
    visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + delta);
    selectedDate = DateTime(visibleMonth.year, visibleMonth.month, 1);
    await load();
  }

  Future<void> goToday() async {
    final value = _now();
    visibleMonth = DateTime(value.year, value.month);
    selectedDate = DateTime(value.year, value.month, value.day);
    await load();
  }

  Future<void> confirm(FinancialCalendarEvent event) async {
    final id = event.scheduledEventId;
    if (id == null) throw StateError('Event is not confirmable');
    confirmationInProgress = true;
    error = null;
    notifyListeners();
    try {
      if (event.isTransfer) {
        await _confirmationRepository.confirmScheduledTransfer(
          id,
          occurredAt: _now(),
        );
      } else {
        await _confirmationRepository.confirmScheduledEvent(
          id,
          occurredAt: _now(),
        );
      }
      await load();
    } catch (_) {
      error = 'ยืนยันรายการไม่สำเร็จ รายการอาจถูกดำเนินการไปแล้ว';
      rethrow;
    } finally {
      confirmationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _loadProjection() async {
    final endOfDay = DateTime(
      selectedDate.year,
      selectedDate.month,
      selectedDate.day + 1,
    ).subtract(const Duration(microseconds: 1));
    projectedBalance = await _projectedBalanceRepository.projectedBalance(
      cutoff: endOfDay.toUtc(),
    );
  }
}
