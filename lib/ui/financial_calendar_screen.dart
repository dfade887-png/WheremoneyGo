import 'package:flutter/material.dart';

import '../domain/financial_calendar.dart';
import 'app_state.dart';
import 'financial_calendar_controller.dart';
import 'finance_components.dart';
import 'scheduled_event_editor_screen.dart';
import 'theme/app_theme.dart';

class FinancialCalendarScreen extends StatefulWidget {
  const FinancialCalendarScreen({
    required this.state,
    this.embedded = false,
    super.key,
  });

  final AppState state;
  final bool embedded;

  @override
  State<FinancialCalendarScreen> createState() =>
      _FinancialCalendarScreenState();
}

class _FinancialCalendarScreenState extends State<FinancialCalendarScreen> {
  late final FinancialCalendarController controller;

  @override
  void initState() {
    super.initState();
    final repository = widget.state.financeRepository;
    controller = FinancialCalendarController(
      calendarRepository: repository,
      projectedBalanceRepository: repository,
      confirmationRepository: repository,
    )..load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: widget.embedded
        ? null
        : AppBar(
            title: const Text('ปฏิทินการเงิน'),
            leading: IconButton(
              key: const Key('calendar-back'),
              onPressed: () => widget.state.go(AppStep.dashboard),
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            actions: [
              TextButton(
                onPressed: controller.goToday,
                child: const Text('วันนี้'),
              ),
            ],
          ),
    body: SafeArea(
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          if (controller.loading && controller.calendarResult == null) {
            return const Center(
              child: CircularProgressIndicator(key: Key('calendar-loading')),
            );
          }
          if (controller.error != null && controller.calendarResult == null) {
            return _CalendarError(
              message: controller.error!,
              onRetry: controller.load,
              onBack: () => widget.state.go(AppStep.dashboard),
            );
          }
          return RefreshIndicator(
            onRefresh: controller.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (widget.embedded)
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'ปฏิทินการเงิน',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: controller.goToday,
                        child: const Text('วันนี้'),
                      ),
                    ],
                  ),
                _MonthHeader(controller: controller),
                const SizedBox(height: 12),
                _MonthGrid(controller: controller),
                if (controller
                    .calendarResult!
                    .excludedBrokenTransferGroupIds
                    .isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const _WarningCard(),
                ],
                const SizedBox(height: 18),
                _SelectedDateHeader(date: controller.selectedDate),
                const SizedBox(height: 10),
                _BalanceSummary(controller: controller),
                if (controller.error != null) ...[
                  const SizedBox(height: 10),
                  _InlineError(message: controller.error!),
                ],
                const SizedBox(height: 16),
                const Text(
                  'รายการของวันนี้',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (controller.selectedDayEvents.isEmpty)
                  const _EmptyDay()
                else
                  ...controller.selectedDayEvents.map(
                    (event) => _EventCard(
                      event: event,
                      accountNames: {
                        for (final account in widget.state.accounts)
                          account['id'] as String: account['name'] as String,
                      },
                      busy: controller.confirmationInProgress,
                      onConfirm: () => _confirm(event),
                      onEdit:
                          event.originKind ==
                                  FinancialCalendarOriginKind.manualSchedule &&
                              event.scheduledEventId != null &&
                              (event.displayStatus ==
                                      FinancialCalendarDisplayStatus
                                          .scheduled ||
                                  event.displayStatus ==
                                      FinancialCalendarDisplayStatus.due)
                          ? () => _openEdit(event)
                          : null,
                    ),
                  ),
                if (controller.calendarResult!.events.isEmpty) ...[
                  const SizedBox(height: 14),
                  const _EmptyMonth(),
                ],
              ],
            ),
          );
        },
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      key: const Key('calendar-create-scheduled'),
      onPressed: _openCreate,
      icon: const Icon(Icons.add),
      label: const Text('เพิ่มรายการล่วงหน้า'),
    ),
  );

  Future<void> _openCreate() async {
    final selected = controller.selectedDate;
    final now = DateTime.now();
    var initial = DateTime(selected.year, selected.month, selected.day, 9);
    if (!initial.isAfter(now)) initial = now.add(const Duration(hours: 1));
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduledEventEditorScreen(
          repository: widget.state.financeRepository,
          accounts: widget.state.accounts,
          categories: widget.state.categories,
          initialScheduledAt: initial,
        ),
      ),
    );
    if (changed == true) await _reloadAfterEdit();
  }

  Future<void> _openEdit(FinancialCalendarEvent event) async {
    final id = event.scheduledEventId;
    if (id == null ||
        event.originKind != FinancialCalendarOriginKind.manualSchedule) {
      return;
    }
    final existing = (await widget.state.financeRepository.scheduledEvents())
        .where((item) => item.id == id)
        .firstOrNull;
    if (existing == null || !mounted) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduledEventEditorScreen(
          repository: widget.state.financeRepository,
          accounts: widget.state.accounts,
          categories: widget.state.categories,
          initialScheduledAt: existing.scheduledAt,
          existing: existing,
        ),
      ),
    );
    if (changed == true) await _reloadAfterEdit();
  }

  Future<void> _reloadAfterEdit() async {
    await widget.state.refreshDailyData();
    await controller.load();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('อัปเดตแผนการเงินแล้ว')));
    }
  }

  Future<void> _confirm(FinancialCalendarEvent event) async {
    final early =
        event.displayStatus == FinancialCalendarDisplayStatus.scheduled;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_confirmLabel(event)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              event.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(_signedMoney(event)),
            const SizedBox(height: 8),
            const Text('วันที่เกิดจริง: ตอนนี้'),
            if (early) ...[
              const SizedBox(height: 12),
              const Text(
                'รายการนี้ยังไม่ถึงกำหนด ต้องการยืนยันว่าเกิดขึ้นแล้วหรือไม่?',
                style: TextStyle(color: AppColors.orange),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    try {
      await controller.confirm(event);
      await widget.state.refreshDailyData();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('บันทึกรายการจริงแล้ว')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(controller.error ?? 'ยืนยันรายการไม่สำเร็จ')),
        );
      }
    }
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.controller});
  final FinancialCalendarController controller;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        key: const Key('previous-month'),
        onPressed: controller.previousMonth,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Expanded(
        child: Text(
          '${_thaiMonths[controller.visibleMonth.month - 1]} ${controller.visibleMonth.year + 543}',
          key: const Key('calendar-month-title'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
      IconButton(
        key: const Key('next-month'),
        onPressed: controller.nextMonth,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ],
  );
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.controller});
  final FinancialCalendarController controller;
  @override
  Widget build(BuildContext context) {
    final month = controller.visibleMonth;
    final first = DateTime(month.year, month.month);
    final count = DateTime(month.year, month.month + 1, 0).day;
    final leading = first.weekday % 7;
    return Column(
      children: [
        Row(
          children: [
            for (final name in const ['อา', 'จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส'])
              Expanded(
                child: Center(
                  child: Text(
                    name,
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth = (constraints.maxWidth - 24) / 7;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: ((leading + count + 6) ~/ 7) * 7,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: cellWidth.clamp(52.0, 68.0),
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                final number = index - leading + 1;
                if (number < 1 || number > count) {
                  return const SizedBox.shrink();
                }
                final date = DateTime(month.year, month.month, number);
                return _DayCell(
                  date: date,
                  events: controller.eventsFor(date),
                  selected: _sameDay(date, controller.selectedDate),
                  onTap: () => controller.selectDate(date),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.events,
    required this.selected,
    required this.onTap,
  });
  final DateTime date;
  final List<FinancialCalendarEvent> events;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final incoming = events
        .where((e) => e.direction == FinancialCalendarDirection.incoming)
        .fold<int>(0, (sum, e) => sum + e.amountSatang);
    final outgoing = events
        .where((e) => e.direction == FinancialCalendarDirection.outgoing)
        .fold<int>(0, (sum, e) => sum + e.amountSatang);
    final transfer = events.any((e) => e.isTransfer);
    final due = events.any((e) => e.isActionRequired);
    return InkWell(
      key: Key('calendar-day-${date.day}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: selected ? AppColors.mintSoft : Colors.white,
          border: Border.all(color: selected ? AppColors.mint : AppColors.line),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: due ? 12 : 0,
              child: Align(
                alignment: Alignment.topLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${date.day}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
            if (due)
              const Positioned(
                top: 0,
                right: 0,
                child: Text(
                  '!',
                  key: Key('due-indicator'),
                  style: TextStyle(
                    color: AppColors.red,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            if (incoming > 0 || outgoing > 0 || transfer)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (incoming > 0)
                        Text(
                          '+${_compact(incoming)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.violet,
                          ),
                        ),
                      if (incoming > 0 && outgoing > 0)
                        const SizedBox(width: 3),
                      if (outgoing > 0)
                        Text(
                          '-${_compact(outgoing)}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.red,
                          ),
                        ),
                      if (transfer) ...[
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.swap_horiz_rounded,
                          size: 12,
                          color: AppColors.blue,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SelectedDateHeader extends StatelessWidget {
  const _SelectedDateHeader({required this.date});
  final DateTime date;
  @override
  Widget build(BuildContext context) => Text(
    '${date.day} ${_thaiMonths[date.month - 1]} ${date.year + 543}',
    key: const Key('selected-date-title'),
    style: Theme.of(context).textTheme.titleLarge,
  );
}

class _BalanceSummary extends StatelessWidget {
  const _BalanceSummary({required this.controller});
  final FinancialCalendarController controller;
  @override
  Widget build(BuildContext context) {
    final balance = controller.projectedBalance;
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            width: constraints.maxWidth < 380
                ? constraints.maxWidth
                : (constraints.maxWidth - 8) / 2,
            child: _BalanceCard(
              label: 'เงินจริงตอนนี้',
              value: balance?.actualNetWorthSatang,
              authoritative: true,
            ),
          ),
          SizedBox(
            width: constraints.maxWidth < 380
                ? constraints.maxWidth
                : (constraints.maxWidth - 8) / 2,
            child: _BalanceCard(
              label: 'คาดการณ์ ณ วันที่เลือก',
              value: balance?.projectedNetWorthSatang,
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({
    required this.label,
    required this.value,
    this.authoritative = false,
  });
  final String label;
  final int? value;
  final bool authoritative;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: authoritative ? AppColors.ink : const Color(0xFF403343),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFFB7C2C5), fontSize: 12),
        ),
        const SizedBox(height: 6),
        if (value == null)
          const Text('—', style: TextStyle(color: Colors.white, fontSize: 18))
        else
          FinanceAmountText(
            satang: value!,
            color: Colors.white,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
      ],
    ),
  );
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.event,
    required this.accountNames,
    required this.busy,
    required this.onConfirm,
    this.onEdit,
  });
  final FinancialCalendarEvent event;
  final Map<String, String> accountNames;
  final bool busy;
  final VoidCallback onConfirm;
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context) {
    final confirmable =
        event.scheduledEventId != null &&
        (event.displayStatus == FinancialCalendarDisplayStatus.scheduled ||
            event.displayStatus == FinancialCalendarDisplayStatus.due);
    final source = accountNames[event.accountId] ?? 'บัญชีไม่ทราบชื่อ';
    final destination = event.destinationAccountId == null
        ? null
        : accountNames[event.destinationAccountId!] ?? 'บัญชีไม่ทราบชื่อ';
    return Card(
      key: Key('calendar-event-${event.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      color: event.actuality == FinancialCalendarActuality.planned
          ? const Color(0xFFFFFBFC)
          : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_eventIcon(event), color: _eventColor(event)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        event.isTransfer ? '$source → $destination' : source,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: FinanceAmountText(
                    satang:
                        event.direction == FinancialCalendarDirection.outgoing
                        ? -event.amountSatang
                        : event.amountSatang,
                    signed: !event.isTransfer,
                    textAlign: TextAlign.end,
                    color: _eventColor(event),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  _statusLabel(event.displayStatus),
                  key: event.isActionRequired ? const Key('due-label') : null,
                  style: TextStyle(
                    color: event.isActionRequired
                        ? AppColors.red
                        : AppColors.muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (confirmable)
                  TextButton(
                    key: Key('confirm-event-${event.id}'),
                    onPressed: busy ? null : onConfirm,
                    child: Text(_confirmLabel(event)),
                  ),
                if (onEdit != null)
                  IconButton(
                    key: Key('edit-event-${event.id}'),
                    tooltip: 'แก้รายการล่วงหน้า',
                    onPressed: busy ? null : onEdit,
                    icon: const Icon(Icons.edit_outlined),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyDay extends StatelessWidget {
  const _EmptyDay();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Text('ไม่มีรายการในวันนี้', key: Key('empty-day')),
    ),
  );
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(18),
      child: Text(
        'ยังไม่มีรายการทางการเงินในเดือนนี้',
        key: Key('empty-month'),
      ),
    ),
  );
}

class _WarningCard extends StatelessWidget {
  const _WarningCard();
  @override
  Widget build(BuildContext context) => const Card(
    color: Color(0xFFFFF0D9),
    child: Padding(
      padding: EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'พบข้อมูลการโอนที่ไม่สมบูรณ์ ระบบซ่อนรายการนั้นไว้เพื่อไม่ให้ยอดคลาดเคลื่อน',
            ),
          ),
        ],
      ),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Icon(Icons.error_outline, color: AppColors.red),
      const SizedBox(width: 8),
      Expanded(child: Text(message)),
    ],
  );
}

class _CalendarError extends StatelessWidget {
  const _CalendarError({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });
  final String message;
  final VoidCallback onRetry, onBack;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 42),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: const Text('ลองใหม่')),
          TextButton(onPressed: onBack, child: const Text('กลับ Dashboard')),
        ],
      ),
    ),
  );
}

const _thaiMonths = [
  'มกราคม',
  'กุมภาพันธ์',
  'มีนาคม',
  'เมษายน',
  'พฤษภาคม',
  'มิถุนายน',
  'กรกฎาคม',
  'สิงหาคม',
  'กันยายน',
  'ตุลาคม',
  'พฤศจิกายน',
  'ธันวาคม',
];
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String _money(int satang) => FinanceMoneyFormat.satang(satang);
String _compact(int satang) => satang.abs() >= 100000
    ? '${(satang / 100000).toStringAsFixed(satang % 100000 == 0 ? 0 : 1)}k'
    : (satang / 100).toStringAsFixed(satang % 100 == 0 ? 0 : 2);
String _signedMoney(FinancialCalendarEvent event) => switch (event.direction) {
  FinancialCalendarDirection.incoming => '+${_money(event.amountSatang)}',
  FinancialCalendarDirection.outgoing => '-${_money(event.amountSatang)}',
  FinancialCalendarDirection.transfer => _money(event.amountSatang),
};
String _statusLabel(FinancialCalendarDisplayStatus status) => switch (status) {
  FinancialCalendarDisplayStatus.scheduled => 'กำหนดไว้',
  FinancialCalendarDisplayStatus.due => 'ถึงกำหนด',
  FinancialCalendarDisplayStatus.fulfilled => 'สำเร็จ / เกิดขึ้นแล้ว',
  FinancialCalendarDisplayStatus.actual => 'เกิดขึ้นแล้ว',
  FinancialCalendarDisplayStatus.skipped => 'ข้าม',
  FinancialCalendarDisplayStatus.cancelled => 'ยกเลิก',
};
String _confirmLabel(FinancialCalendarEvent event) => switch (event.eventType) {
  FinancialCalendarEventType.income => 'ยืนยันเงินเข้า',
  FinancialCalendarEventType.expense => 'ยืนยันการจ่าย',
  FinancialCalendarEventType.refund => 'ยืนยันเงินคืน',
  FinancialCalendarEventType.transfer => 'ยืนยันการโอน',
};
IconData _eventIcon(FinancialCalendarEvent event) => switch (event.eventType) {
  FinancialCalendarEventType.income => Icons.south_west_rounded,
  FinancialCalendarEventType.expense => Icons.north_east_rounded,
  FinancialCalendarEventType.refund => Icons.replay_rounded,
  FinancialCalendarEventType.transfer => Icons.swap_horiz_rounded,
};
Color _eventColor(FinancialCalendarEvent event) => switch (event.direction) {
  FinancialCalendarDirection.incoming => AppColors.violet,
  FinancialCalendarDirection.outgoing => AppColors.red,
  FinancialCalendarDirection.transfer => AppColors.blue,
};
