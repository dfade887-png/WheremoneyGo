import 'package:flutter/material.dart';

import '../domain/notification_rule_parser.dart';
import 'app_state.dart';
import 'candidate_inbox_screen.dart';
import 'notification_rule_controller.dart';

class NotificationRuleBuilderScreen extends StatefulWidget {
  const NotificationRuleBuilderScreen({required this.state, super.key});
  final AppState state;
  @override
  State<NotificationRuleBuilderScreen> createState() =>
      _NotificationRuleBuilderScreenState();
}

class _NotificationRuleBuilderScreenState
    extends State<NotificationRuleBuilderScreen> {
  late final NotificationRuleController controller;
  @override
  void initState() {
    super.initState();
    controller = NotificationRuleController(widget.state.financeRepository);
    controller.load();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('กฎการตรวจจับ')),
      body: _body(),
      floatingActionButton: controller.selectedSource == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('add-notification-rule'),
              onPressed: () => _editRule(),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มกฎ'),
            ),
    ),
  );

  Widget _body() {
    if (controller.loading && controller.sources.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.sources.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'ยังไม่มีแหล่งแจ้งเตือนที่เปิดใช้งาน\nกลับไปเปิด LINE ก่อนสร้างกฎ',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        DropdownButtonFormField<String>(
          key: const Key('rule-source-selector'),
          initialValue: controller.selectedSource!.id,
          decoration: const InputDecoration(
            labelText: 'แหล่งแจ้งเตือน',
            border: OutlineInputBorder(),
          ),
          items: [
            for (final source in controller.sources)
              DropdownMenuItem(
                value: source.id,
                child: Text(source.displayName),
              ),
          ],
          onChanged: (value) {
            if (value != null) controller.selectSource(value);
          },
        ),
        const SizedBox(height: 18),
        Text('กฎที่ตั้งไว้', style: Theme.of(context).textTheme.titleLarge),
        if (controller.rules.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Text('ยังไม่มีกฎ กด “เพิ่มกฎ” เพื่อสอนระบบอ่านข้อความ'),
            ),
          ),
        for (final rule in controller.rules)
          Card(
            child: ListTile(
              key: ValueKey('rule-${rule.id}'),
              title: Text(rule.name),
              subtitle: Text(
                '${_direction(rule.directionRule)} → ${_accountName(rule.accountId)}\n${_parser(rule.parserKind)}',
              ),
              isThreeLine: true,
              onTap: () => _editRule(rule),
              trailing: Switch(
                value: rule.enabled,
                onChanged: (value) => controller.toggle(rule, value),
              ),
            ),
          ),
        const SizedBox(height: 18),
        FilledButton.tonalIcon(
          key: const Key('reprocess-raw-events'),
          onPressed: controller.reprocessing ? null : _confirmReprocess,
          icon: const Icon(Icons.replay_outlined),
          label: Text(
            controller.reprocessing
                ? 'กำลังตรวจรายการ…'
                : 'ประมวลผลการแจ้งเตือนที่มีอยู่',
          ),
        ),
        if (controller.reprocessSummary case final summary?)
          Card(
            key: const Key('reprocess-summary'),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'ประมวลผลเสร็จแล้ว',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text('ตรวจพบ Candidate ใหม่: ${summary.created}'),
                  Text('ไม่ตรงกับกฎ: ${summary.noMatch}'),
                  Text('กำกวม: ${summary.ambiguous}'),
                  Text('ซ้ำ/มีอยู่แล้ว: ${summary.existing}'),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const Key('go-to-candidate-inbox'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CandidateInboxScreen(state: widget.state),
                      ),
                    ),
                    child: const Text('ไปที่รายการรอตรวจ'),
                  ),
                ],
              ),
            ),
          ),
        if (controller.error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        const SizedBox(height: 16),
        const Text(
          'การทดลองตรวจจับและบันทึกกฎไม่สร้างรายการเงินจริง การประมวลผลจะสร้างเพียงรายการรอตรวจเท่านั้น',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Future<void> _confirmReprocess() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ตรวจรายการที่เก็บไว้?'),
        content: const Text(
          'ระบบจะตรวจการแจ้งเตือนล่าสุดไม่เกิน 50 รายการ และสร้างได้เฉพาะรายการรอตรวจ ไม่กระทบเงินจริง',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('เริ่มตรวจ'),
          ),
        ],
      ),
    );
    if (accepted == true) await controller.reprocess();
  }

  Future<void> _editRule([NotificationRule? existing]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _RuleForm(
        state: widget.state,
        controller: controller,
        existing: existing,
      ),
    );
    if (saved == true) await controller.load();
  }

  String _accountName(String? id) =>
      widget.state.accounts
          .where((row) => row['id'] == id)
          .map((row) => row['name'] as String)
          .firstOrNull ??
      'ยังไม่ระบุบัญชี';
  static String _direction(String value) => switch (value) {
    'incoming' => 'รายรับ',
    'outgoing' => 'รายจ่าย',
    'refund' => 'เงินคืน',
    'transfer' => 'โอนเงิน',
    _ => value,
  };
  static String _parser(String value) => switch (value) {
    'template' => 'รูปแบบข้อความ',
    'keyword' => 'คำสำคัญ',
    'regex' => 'ขั้นสูง (Regex)',
    _ => value,
  };
}

class _RuleForm extends StatefulWidget {
  const _RuleForm({
    required this.state,
    required this.controller,
    this.existing,
  });
  final AppState state;
  final NotificationRuleController controller;
  final NotificationRule? existing;
  @override
  State<_RuleForm> createState() => _RuleFormState();
}

class _RuleFormState extends State<_RuleForm> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final sender = TextEditingController(
    text: widget.existing?.senderOrChatPattern ?? '',
  );
  late final title = TextEditingController(
    text: widget.existing?.titlePattern ?? '',
  );
  late final pattern = TextEditingController(
    text: widget.existing?.bodyPattern ?? 'รายการ {amount} บาท',
  );
  late final priority = TextEditingController(
    text: '${widget.existing?.priority ?? 0}',
  );
  late String parserKind = widget.existing?.parserKind ?? 'template';
  late String direction = widget.existing?.directionRule ?? 'outgoing';
  late String? accountId = widget.existing?.accountId;
  late String? categoryId = widget.existing?.categoryId;
  late bool enabled = widget.existing?.enabled ?? true;
  bool advanced = false;

  @override
  void dispose() {
    name.dispose();
    sender.dispose();
    title.dispose();
    pattern.dispose();
    priority.dispose();
    super.dispose();
  }

  NotificationRule get draft => NotificationRule(
    id: widget.existing?.id ?? 'draft',
    notificationSourceId: widget.controller.selectedSource!.id,
    name: name.text,
    senderOrChatPattern: sender.text.trim().isEmpty ? null : sender.text.trim(),
    titlePattern: title.text.trim().isEmpty ? null : title.text.trim(),
    bodyPattern: pattern.text,
    parserKind: parserKind,
    directionRule: direction,
    accountId: accountId,
    categoryId: categoryId,
    priority: int.tryParse(priority.text) ?? 0,
    enabled: enabled,
    ruleVersion: widget.existing?.ruleVersion ?? 1,
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      18,
      18,
      18,
      18 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.existing == null ? 'เพิ่มกฎ' : 'แก้ไขกฎ',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 14),
          TextFormField(
            key: const Key('rule-name'),
            controller: name,
            decoration: const InputDecoration(
              labelText: 'ชื่อกฎ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('rule-sender-pattern'),
            controller: sender,
            decoration: const InputDecoration(
              labelText: 'ผู้ส่ง / ห้อง เช่น SCB Connect',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('rule-parser-kind'),
            initialValue: parserKind,
            decoration: const InputDecoration(
              labelText: 'วิธีตรวจข้อความ',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'template', child: Text('รูปแบบข้อความ')),
              DropdownMenuItem(value: 'keyword', child: Text('คำสำคัญ')),
              DropdownMenuItem(value: 'regex', child: Text('ขั้นสูง (Regex)')),
            ],
            onChanged: (value) => setState(() => parserKind = value!),
          ),
          const SizedBox(height: 12),
          TextFormField(
            key: const Key('rule-body-pattern'),
            controller: pattern,
            decoration: InputDecoration(
              labelText: parserKind == 'keyword'
                  ? 'ข้อความที่ต้องมี'
                  : 'รูปแบบข้อความ',
              helperText: parserKind == 'template'
                  ? 'ใช้ {amount} แทนจำนวนเงิน เช่น รายการเงินออก {amount} บาท'
                  : null,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('rule-direction'),
            initialValue: direction,
            decoration: const InputDecoration(
              labelText: 'ประเภท',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'outgoing', child: Text('รายจ่าย')),
              DropdownMenuItem(value: 'incoming', child: Text('รายรับ')),
              DropdownMenuItem(value: 'refund', child: Text('เงินคืน')),
            ],
            onChanged: (value) => setState(() {
              direction = value!;
              categoryId = null;
            }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('rule-account'),
            initialValue: accountId,
            decoration: const InputDecoration(
              labelText: 'บัญชี',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final row in widget.state.accounts.where(
                (a) => a['is_active'] == 1,
              ))
                DropdownMenuItem(
                  value: row['id'] as String,
                  child: Text(row['name'] as String),
                ),
            ],
            onChanged: (value) => setState(() => accountId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            key: const Key('rule-category'),
            initialValue: categoryId,
            decoration: const InputDecoration(
              labelText: 'หมวดหมู่ (ไม่บังคับ)',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('ไม่ระบุ'),
              ),
              for (final row in widget.state.categories.where(
                (c) =>
                    c['category_type'] ==
                    (direction == 'incoming' ? 'income' : 'expense'),
              ))
                DropdownMenuItem<String?>(
                  value: row['id'] as String,
                  child: Text(row['name'] as String),
                ),
            ],
            onChanged: (value) => setState(() => categoryId = value),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: const Key('pick-raw-sample'),
            icon: const Icon(Icons.notifications_outlined),
            label: Text(
              widget.controller.selectedSample == null
                  ? 'ใช้การแจ้งเตือนที่ตรวจพบเป็นตัวอย่าง'
                  : 'เลือกตัวอย่างแล้ว • ${_date(widget.controller.selectedSample!.capturedAt)}',
            ),
            onPressed: _pickSample,
          ),
          if (widget.controller.selectedSample case final sample?)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sample.senderOrChat ?? 'ไม่ระบุผู้ส่ง',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Text(_snippet(sample.body)),
                  ],
                ),
              ),
            ),
          OutlinedButton(
            key: const Key('preview-rule'),
            onPressed: _preview,
            child: const Text('ทดลองตรวจจับ'),
          ),
          if (widget.controller.preview case final preview?)
            Card(
              key: const Key('rule-preview-result'),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  preview.matched
                      ? 'ตรวจพบ: ${_direction(preview.candidateType)} • ${_money(preview.amountSatang)} • ${_account(preview.accountId)}'
                      : 'ไม่พบรายการที่ตรงกับกฎนี้',
                ),
              ),
            ),
          ExpansionTile(
            title: const Text('ขั้นสูง'),
            onExpansionChanged: (value) => advanced = value,
            children: [
              TextFormField(
                controller: title,
                decoration: const InputDecoration(
                  labelText: 'รูปแบบหัวข้อ (ไม่บังคับ)',
                ),
              ),
              TextFormField(
                controller: priority,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ลำดับความสำคัญ'),
              ),
              SwitchListTile(
                title: const Text('เปิดใช้กฎ'),
                value: enabled,
                onChanged: (value) => setState(() => enabled = value),
              ),
            ],
          ),
          if (widget.controller.error != null)
            Text(
              widget.controller.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('save-rule'),
            onPressed: widget.controller.saving ? null : _save,
            child: Text(widget.controller.saving ? 'กำลังบันทึก…' : 'บันทึก'),
          ),
        ],
      ),
    ),
  );

  Future<void> _pickSample() async {
    final sample = await showDialog<RawNotificationSample>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('เลือกการแจ้งเตือนตัวอย่าง'),
        children: [
          if (widget.controller.samples.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('ยังไม่มีการแจ้งเตือนที่ตรวจพบ'),
            ),
          for (final sample in widget.controller.samples)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, sample),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sample.senderOrChat ?? 'ไม่ระบุผู้ส่ง',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    '${_date(sample.capturedAt)} • ${_snippet(sample.body)}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (sample != null) {
      widget.controller.selectSample(sample);
      setState(() {});
    }
  }

  Future<void> _preview() async {
    await widget.controller.previewRule(draft);
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (await widget.controller.saveRule(
          draft,
          isNew: widget.existing == null,
        ) &&
        mounted) {
      Navigator.pop(context, true);
    }
  }

  String _account(String? id) =>
      widget.state.accounts
          .where((a) => a['id'] == id)
          .map((a) => a['name'] as String)
          .firstOrNull ??
      'ไม่ระบุบัญชี';
  static String _direction(String? value) => switch (value) {
    'income' => 'รายรับ',
    'expense' => 'รายจ่าย',
    'refund' => 'เงินคืน',
    _ => 'รายการ',
  };
  static String _money(int? satang) =>
      satang == null ? '-' : '฿${(satang / 100).toStringAsFixed(2)}';
  static String _snippet(String? body) {
    final clean = body?.replaceAll(RegExp(r'\s+'), ' ').trim() ?? '';
    return clean.length > 100 ? '${clean.substring(0, 100)}…' : clean;
  }

  static String _date(DateTime value) {
    final local = value.toLocal();
    return '${local.day}/${local.month}/${local.year} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
