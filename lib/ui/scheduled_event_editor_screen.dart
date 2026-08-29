import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/models/scheduled_financial_event.dart';
import '../domain/repositories/scheduled_financial_event_repository.dart';
import 'finance_components.dart';
import 'theme/app_theme.dart';

class ScheduledEventEditorScreen extends StatefulWidget {
  const ScheduledEventEditorScreen({
    required this.repository,
    required this.accounts,
    required this.categories,
    required this.initialScheduledAt,
    this.existing,
    this.now,
    super.key,
  });

  final ScheduledFinancialEventRepository repository;
  final List<Map<String, Object?>> accounts;
  final List<Map<String, Object?>> categories;
  final DateTime initialScheduledAt;
  final ScheduledFinancialEvent? existing;
  final DateTime Function()? now;

  @override
  State<ScheduledEventEditorScreen> createState() =>
      _ScheduledEventEditorScreenState();
}

class _ScheduledEventEditorScreenState
    extends State<ScheduledEventEditorScreen> {
  late ScheduledEventType type =
      widget.existing?.eventType ?? ScheduledEventType.expense;
  late final title = TextEditingController(text: widget.existing?.title ?? '');
  late final amount = TextEditingController(
    text: widget.existing == null
        ? ''
        : _amountText(widget.existing!.amountSatang),
  );
  late final note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime scheduledAt =
      widget.existing?.scheduledAt.toLocal() ??
      widget.initialScheduledAt.toLocal();
  late String? accountId =
      widget.existing?.accountId ??
      _activeAccounts.firstOrNull?['id'] as String?;
  late String? destinationAccountId = widget.existing?.destinationAccountId;
  late String? categoryId = widget.existing?.categoryId;
  bool saving = false;
  String? error;

  List<Map<String, Object?>> get _activeAccounts => widget.accounts
      .where((row) => row['is_active'] == 1)
      .toList(growable: false);

  List<Map<String, Object?>> get _validCategories => widget.categories
      .where(
        (row) =>
            row['category_type'] ==
            (type == ScheduledEventType.income ? 'income' : 'expense'),
      )
      .toList(growable: false);

  int? get amountSatang => parseBahtToSatang(amount.text);
  bool get scheduledTimeValid =>
      widget.existing != null ||
      scheduledAt.isAfter((widget.now ?? DateTime.now)());

  bool get valid {
    if (title.text.trim().isEmpty ||
        amountSatang == null ||
        accountId == null) {
      return false;
    }
    if (!scheduledTimeValid) return false;
    if (type == ScheduledEventType.transfer) {
      return destinationAccountId != null && destinationAccountId != accountId;
    }
    return categoryId != null;
  }

  @override
  void dispose() {
    title.dispose();
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.existing == null ? 'เพิ่มรายการล่วงหน้า' : 'แก้รายการล่วงหน้า',
      ),
      actions: [
        if (widget.existing != null)
          IconButton(
            key: const Key('scheduled-cancel'),
            tooltip: 'ยกเลิกรายการล่วงหน้า',
            onPressed: saving ? null : _cancel,
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        children: [
          const Text('ประเภท', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SegmentedButton<ScheduledEventType>(
            key: const Key('scheduled-type'),
            segments: const [
              ButtonSegment(
                value: ScheduledEventType.expense,
                label: Text('รายจ่าย'),
                icon: Icon(Icons.north_east_rounded),
              ),
              ButtonSegment(
                value: ScheduledEventType.income,
                label: Text('รายรับ'),
                icon: Icon(Icons.south_west_rounded),
              ),
              ButtonSegment(
                value: ScheduledEventType.transfer,
                label: Text('โอน'),
                icon: Icon(Icons.swap_horiz_rounded),
              ),
            ],
            selected: {type},
            onSelectionChanged: saving
                ? null
                : (values) => setState(() {
                    type = values.first;
                    categoryId = null;
                    destinationAccountId = null;
                    error = null;
                  }),
          ),
          const SizedBox(height: 18),
          TextField(
            key: const Key('scheduled-title'),
            controller: title,
            autofocus: widget.existing == null,
            decoration: const InputDecoration(
              labelText: 'ชื่อรายการ *',
              hintText: 'เช่น ทำฟัน',
            ),
            onChanged: (_) => setState(() => error = null),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('scheduled-amount'),
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
            decoration: InputDecoration(
              labelText: 'จำนวนเงิน *',
              prefixText: '฿',
              errorText: amount.text.isNotEmpty && amountSatang == null
                  ? 'กรอกจำนวนมากกว่า 0 และทศนิยมไม่เกิน 2 ตำแหน่ง'
                  : null,
            ),
            onChanged: (_) => setState(() => error = null),
          ),
          const SizedBox(height: 12),
          _Picker(
            key: const Key('scheduled-account'),
            label: type == ScheduledEventType.income
                ? 'เงินเข้าบัญชี *'
                : 'จากบัญชี *',
            value: _name(widget.accounts, accountId),
            onTap: saving ? null : () => _pickAccount(destination: false),
          ),
          if (type == ScheduledEventType.transfer) ...[
            const SizedBox(height: 12),
            _Picker(
              key: const Key('scheduled-destination'),
              label: 'ไปบัญชี *',
              value: _name(widget.accounts, destinationAccountId),
              onTap: saving ? null : () => _pickAccount(destination: true),
            ),
          ] else ...[
            const SizedBox(height: 12),
            _Picker(
              key: const Key('scheduled-category'),
              label: 'หมวดหมู่ *',
              value: _name(widget.categories, categoryId),
              onTap: saving ? null : _pickCategory,
            ),
          ],
          const SizedBox(height: 12),
          _Picker(
            key: const Key('scheduled-date-time'),
            label: 'วันและเวลาที่คาดว่าจะเกิด *',
            value: _dateTime(scheduledAt),
            onTap: saving ? null : _pickDateTime,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'รายละเอียดเพิ่มเติม (ไม่บังคับ)',
            ),
          ),
          const SizedBox(height: 12),
          if (!scheduledTimeValid) ...[
            const Text(
              'รายการใหม่ต้องตั้งไว้ในอนาคต',
              key: Key('scheduled-date-error'),
              style: TextStyle(color: AppColors.red),
            ),
            const SizedBox(height: 8),
          ],
          Card(
            color: const Color(0xFFFFE8F3),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                amountSatang == null
                    ? 'รายการนี้เป็นแผน ยังไม่เปลี่ยนเงินจริง'
                    : '${_typeLabel(type)} ${FinanceMoneyFormat.satang(amountSatang!)} จะกระทบเฉพาะ Forecast จนกว่าจะยืนยันว่าเกิดขึ้นจริง',
              ),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              key: const Key('scheduled-error'),
              style: const TextStyle(color: AppColors.red),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton(
            key: const Key('scheduled-save'),
            onPressed: !valid || saving ? null : _save,
            child: Text(saving ? 'กำลังบันทึก…' : 'บันทึกรายการล่วงหน้า'),
          ),
        ],
      ),
    ),
  );

  Future<void> _save() async {
    if (!valid || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final utc = scheduledAt.toUtc();
      if (widget.existing == null) {
        await widget.repository.createScheduledEvent(
          eventType: type,
          amountSatang: amountSatang!,
          title: title.text.trim(),
          accountId: accountId!,
          destinationAccountId: type == ScheduledEventType.transfer
              ? destinationAccountId
              : null,
          categoryId: type == ScheduledEventType.transfer ? null : categoryId,
          note: _nullable(note.text),
          scheduledAt: utc,
          dueAt: utc,
        );
      } else {
        await widget.repository.updateScheduledEvent(
          id: widget.existing!.id,
          eventType: type,
          amountSatang: amountSatang!,
          title: title.text.trim(),
          accountId: accountId!,
          destinationAccountId: type == ScheduledEventType.transfer
              ? destinationAccountId
              : null,
          categoryId: type == ScheduledEventType.transfer ? null : categoryId,
          note: _nullable(note.text),
          scheduledAt: utc,
          dueAt: utc,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'บันทึกไม่สำเร็จ กรุณาตรวจบัญชี หมวดหมู่ และลองใหม่';
        });
      }
    }
  }

  Future<void> _cancel() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ยกเลิกรายการล่วงหน้า?'),
        content: const Text(
          'รายการจะไม่กระทบ Forecast อีก แต่ประวัติจะยังตรวจสอบได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('เก็บไว้'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ยกเลิกรายการ'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    setState(() => saving = true);
    try {
      await widget.repository.cancelScheduledEvent(widget.existing!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'ยกเลิกไม่สำเร็จ รายการอาจถูกดำเนินการแล้ว';
        });
      }
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: scheduledAt,
      firstDate: DateTime((widget.now ?? DateTime.now)().year - 1),
      lastDate: DateTime((widget.now ?? DateTime.now)().year + 10),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(scheduledAt),
    );
    if (time == null) return;
    setState(
      () => scheduledAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ),
    );
  }

  Future<void> _pickAccount({required bool destination}) async {
    final rows = destination
        ? _activeAccounts.where((row) => row['id'] != accountId).toList()
        : _activeAccounts;
    final selected = await _selection(
      context,
      destination ? 'เลือกบัญชีปลายทาง' : 'เลือกบัญชี',
      rows,
    );
    if (selected == null) return;
    setState(() {
      if (destination) {
        destinationAccountId = selected;
      } else {
        accountId = selected;
        if (destinationAccountId == selected) destinationAccountId = null;
      }
    });
  }

  Future<void> _pickCategory() async {
    final selected = await _selection(
      context,
      'เลือกหมวดหมู่',
      _validCategories,
    );
    if (selected != null) setState(() => categoryId = selected);
  }

  static int? parseBahtToSatang(String input) {
    final value = input.trim();
    if (!RegExp(
      r'^(?:\d+|\d{1,3}(?:,\d{3})+)(?:\.\d{1,2})?$',
    ).hasMatch(value)) {
      return null;
    }
    final parts = value.replaceAll(',', '').split('.');
    final baht = int.tryParse(parts[0]);
    if (baht == null) return null;
    final fraction = parts.length == 1
        ? 0
        : int.parse(parts[1].padRight(2, '0'));
    final satang = baht * 100 + fraction;
    return satang > 0 ? satang : null;
  }
}

class _Picker extends StatelessWidget {
  const _Picker({
    required this.label,
    required this.value,
    required this.onTap,
    super.key,
  });
  final String label;
  final String? value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: '$label ${value ?? 'ยังไม่ได้เลือก'}',
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.chevron_right),
        ),
        child: Text(
          value ?? 'แตะเพื่อเลือก',
          style: TextStyle(color: value == null ? AppColors.muted : null),
        ),
      ),
    ),
  );
}

Future<String?> _selection(
  BuildContext context,
  String title,
  List<Map<String, Object?>> rows,
) => showModalBottomSheet<String>(
  context: context,
  useSafeArea: true,
  builder: (context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Text(title, style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 12),
      if (rows.isEmpty) const Text('ยังไม่มีตัวเลือกที่ใช้งานได้'),
      for (final row in rows)
        ListTile(
          title: Text(row['name'] as String),
          onTap: () => Navigator.pop(context, row['id'] as String),
        ),
    ],
  ),
);

String? _name(List<Map<String, Object?>> rows, String? id) =>
    rows.where((row) => row['id'] == id).firstOrNull?['name'] as String?;
String? _nullable(String value) => value.trim().isEmpty ? null : value.trim();
String _amountText(int satang) => satang % 100 == 0
    ? '${satang ~/ 100}'
    : '${satang ~/ 100}.${(satang % 100).toString().padLeft(2, '0')}';
String _dateTime(DateTime value) =>
    '${value.day}/${value.month}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _typeLabel(ScheduledEventType type) => switch (type) {
  ScheduledEventType.expense => 'รายจ่าย',
  ScheduledEventType.income => 'รายรับ',
  ScheduledEventType.transfer => 'การโอน',
  ScheduledEventType.refund => 'เงินคืน',
};
