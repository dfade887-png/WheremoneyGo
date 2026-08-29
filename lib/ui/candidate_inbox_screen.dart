import 'package:flutter/material.dart';

import '../domain/candidate_matching.dart';
import '../domain/candidate_review.dart';
import '../domain/transfer_correlation.dart';
import 'app_state.dart';
import 'candidate_inbox_controller.dart';
import 'finance_components.dart';

class CandidateInboxScreen extends StatefulWidget {
  const CandidateInboxScreen({
    this.state,
    this.controller,
    this.embedded = false,
    super.key,
  });
  final AppState? state;
  final CandidateInboxController? controller;
  final bool embedded;
  @override
  State<CandidateInboxScreen> createState() => _CandidateInboxScreenState();
}

class _CandidateInboxScreenState extends State<CandidateInboxScreen> {
  CandidateInboxController? _controller;
  bool _ownsController = false;
  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    final state = widget.state;
    if (_controller == null && state != null) {
      _controller = CandidateInboxController(
        state.financeRepository,
        onFinancialChange: state.refreshDailyData,
      );
      _ownsController = true;
    }
    _controller?.load();
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(title: const Text('รายการรอตรวจ')),
      body: controller == null
          ? const SafeArea(
              child: FinanceEmptyState(
                key: Key('candidate-inbox-empty'),
                icon: Icons.fact_check_outlined,
                message:
                    'ระบบจะแสดงรายการจากการแจ้งเตือนที่ต้องให้คุณตรวจสอบที่นี่',
              ),
            )
          : ListenableBuilder(
              listenable: controller,
              builder: (_, _) => _body(controller),
            ),
    );
  }

  Widget _body(CandidateInboxController controller) {
    if (controller.loading && controller.pendingCandidates.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.error != null && controller.pendingCandidates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.sync_problem_outlined, size: 40),
            const SizedBox(height: 10),
            Text(controller.error!),
            TextButton(
              onPressed: controller.load,
              child: const Text('ลองใหม่'),
            ),
          ],
        ),
      );
    }
    if (controller.pendingCandidates.isEmpty) {
      return const FinanceEmptyState(
        key: Key('candidate-inbox-empty'),
        icon: Icons.task_alt_outlined,
        message:
            'ไม่มีรายการที่ต้องตรวจสอบตอนนี้\nระบบจะแสดงรายการที่ต้องให้คุณตรวจสอบที่นี่',
      );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.builder(
        key: const Key('candidate-pending-list'),
        padding: const EdgeInsets.all(16),
        itemCount: controller.pendingCandidates.length,
        itemBuilder: (_, index) {
          final item = controller.pendingCandidates[index];
          final rawCorrelation = controller.correlations[item.id];
          final correlation = controller.correlationFor(item.id);
          return Card(
            key: ValueKey('candidate-${item.id}'),
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FinanceAmountText(
                          satang: signedAmount(item),
                          signed: true,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Chip(
                        label: Text(_CandidateDetailSheet.typeLabel(item.type)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${item.accountName ?? 'ยังไม่ระบุบัญชี'} • ตรวจพบจาก ${item.sourceLabel}',
                  ),
                  Text(dateTime(item.occurredAt)),
                  if (item.merchantOrSender != null)
                    Text('ผู้ส่ง/ร้านค้า: ${item.merchantOrSender}'),
                  const SizedBox(height: 10),
                  Text(recommendation(item.match.kind)),
                  if (rawCorrelation?.kind ==
                      TransferCorrelationKind.ambiguous) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: ValueKey('transfer-ambiguous-${item.id}'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.rule_folder_outlined),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'พบคู่การโอนมากกว่าหนึ่งรายการ กรุณาตรวจแต่ละรายการแยกกัน ระบบจะไม่จับคู่ให้อัตโนมัติ',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (correlation != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      key: ValueKey('transfer-suggestion-${item.id}'),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE8F3),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _correlationLabel(correlation.kind),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(_correlationAccounts(correlation)),
                          Text(
                            'จับคู่จากรายการรอตรวจ 2 รายการ • ${FinanceMoneyFormat.satang(correlation.amountSatang)}',
                          ),
                          const SizedBox(height: 8),
                          FilledButton.tonal(
                            key: ValueKey('review-transfer-${item.id}'),
                            onPressed: controller.resolvingCandidateId == null
                                ? () => _openTransferReview(
                                    controller,
                                    correlation,
                                  )
                                : null,
                            child: const Text('ตรวจสอบการโอน'),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      key: ValueKey('review-${item.id}'),
                      onPressed: controller.resolvingCandidateId == null
                          ? () => _openDetail(controller, item)
                          : null,
                      child: const Text('ตรวจสอบ'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openDetail(
    CandidateInboxController controller,
    CandidateReviewItem item,
  ) async {
    await controller.select(item);
    if (!mounted || controller.selectedCandidate == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: controller,
        builder: (_, _) => _CandidateDetailSheet(
          controller: controller,
          item: item,
          accounts: widget.state?.accounts ?? const [],
          categories: widget.state?.categories ?? const [],
          close: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  }

  Future<void> _openTransferReview(
    CandidateInboxController controller,
    TransferCorrelationResult correlation,
  ) async {
    final accounts = {
      for (final row
          in widget.state?.accounts ?? const <Map<String, Object?>>[])
        row['id'] as String: row['name'] as String,
    };
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => ListenableBuilder(
        listenable: controller,
        builder: (_, _) => _TransferCorrelationReview(
          controller: controller,
          correlation: correlation,
          sourceName: accounts[correlation.sourceAccountId] ?? 'บัญชีต้นทาง',
          destinationName:
              accounts[correlation.destinationAccountId] ?? 'บัญชีปลายทาง',
          close: () => Navigator.pop(sheetContext),
        ),
      ),
    );
  }

  String _correlationAccounts(TransferCorrelationResult result) {
    String account(String? id) =>
        widget.state?.accounts
                .where((row) => row['id'] == id)
                .firstOrNull?['name']
            as String? ??
        'บัญชีไม่ทราบชื่อ';
    return '${account(result.sourceAccountId)} → ${account(result.destinationAccountId)}';
  }

  static String _correlationLabel(
    TransferCorrelationKind kind,
  ) => switch (kind) {
    TransferCorrelationKind.existingTransfer =>
      'น่าจะเป็นการโอนที่บันทึกไว้แล้ว',
    TransferCorrelationKind.scheduledTransfer => 'น่าจะตรงกับรายการโอนล่วงหน้า',
    TransferCorrelationKind.likelyTransferPair => 'อาจเป็นการโอนระหว่างบัญชี',
    TransferCorrelationKind.ambiguous => 'พบคู่การโอนมากกว่าหนึ่งรายการ',
    TransferCorrelationKind.noCorrelation => 'ยังไม่พบคู่การโอน',
  };

  static int signedAmount(CandidateReviewItem item) =>
      const {'income', 'refund'}.contains(item.type)
      ? item.amountSatang
      : -item.amountSatang;
  static String recommendation(CandidateMatchKind kind) => switch (kind) {
    CandidateMatchKind.existingTransactionMatch =>
      'ระบบพบว่ารายการนี้น่าจะถูกบันทึกแล้ว',
    CandidateMatchKind.scheduledMatch => 'ระบบพบรายการที่วางแผนไว้',
    CandidateMatchKind.ambiguous => 'พบรายการที่อาจตรงกันมากกว่าหนึ่งรายการ',
    CandidateMatchKind.noMatch => 'ยังไม่พบรายการที่ตรงกัน',
  };
  static String dateTime(DateTime value) {
    final local = value.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
  }
}

class _TransferCorrelationReview extends StatelessWidget {
  const _TransferCorrelationReview({
    required this.controller,
    required this.correlation,
    required this.sourceName,
    required this.destinationName,
    required this.close,
  });

  final CandidateInboxController controller;
  final TransferCorrelationResult correlation;
  final String sourceName;
  final String destinationName;
  final VoidCallback close;

  @override
  Widget build(BuildContext context) {
    final busy = controller.resolvingCandidateId != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'ตรวจสอบการโอนระหว่างบัญชี',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                IconButton(
                  tooltip: 'ปิด',
                  onPressed: busy ? null : close,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FinanceAmountText(
              satang: correlation.amountSatang,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _TransferAccountRow(
                      icon: Icons.account_balance_wallet_outlined,
                      label: 'เงินออกจาก',
                      accountName: sourceName,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Icon(Icons.arrow_downward),
                    ),
                    _TransferAccountRow(
                      icon: Icons.savings_outlined,
                      label: 'เงินเข้าที่',
                      accountName: destinationName,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(switch (correlation.kind) {
              TransferCorrelationKind.existingTransfer =>
                'พบการโอนที่บันทึกไว้แล้ว ระบบจะเชื่อมรายการแจ้งเตือนทั้งสองโดยไม่สร้างรายการเงินจริงซ้ำ',
              TransferCorrelationKind.scheduledTransfer =>
                'พบรายการโอนล่วงหน้าที่ตรงกัน ระบบจะยืนยันรายการนั้นและเชื่อมการแจ้งเตือนทั้งสอง',
              _ =>
                'ตรวจพบจากรายการเงินออกและเงินเข้า 2 รายการที่ยอดและเวลาใกล้กัน',
            }),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('ทำไมระบบถึงเสนอรายการนี้'),
              children: [
                for (final reason in correlation.reasonCodes)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text('✓ $reason'),
                  ),
              ],
            ),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Padding(
                padding: EdgeInsets.all(14),
                child: Text(
                  'เงินจริงจะเปลี่ยนเมื่อคุณกดยืนยันเท่านั้น ไม่มีการโพสต์หรือจับคู่อัตโนมัติ',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('confirm-correlated-transfer'),
              onPressed: busy ? null : () => _confirm(context),
              child: Text(
                correlation.kind == TransferCorrelationKind.existingTransfer
                    ? 'ยืนยันว่าเป็นการโอนที่บันทึกไว้แล้ว'
                    : 'ยืนยันเป็นการโอนระหว่างบัญชี',
              ),
            ),
            TextButton(
              key: const Key('reject-correlated-transfer'),
              onPressed: busy
                  ? null
                  : () {
                      controller.rejectCorrelation(correlation);
                      close();
                    },
              child: const Text('ไม่ใช่การโอนเดียวกัน'),
            ),
            TextButton(
              onPressed: busy ? null : close,
              child: const Text('กลับ'),
            ),
            if (busy) const Center(child: CircularProgressIndicator()),
            if (controller.error != null)
              Text(
                controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ยืนยันการโอน?'),
        content: Text(
          '$sourceName → $destinationName\n${FinanceMoneyFormat.satang(correlation.amountSatang)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('กลับไปตรวจ'),
          ),
          FilledButton(
            key: const Key('confirm-correlated-transfer-dialog'),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ยืนยัน'),
          ),
        ],
      ),
    );
    if (confirmed == true && await controller.confirmCorrelation(correlation)) {
      close();
    }
  }
}

class _TransferAccountRow extends StatelessWidget {
  const _TransferAccountRow({
    required this.icon,
    required this.label,
    required this.accountName,
  });
  final IconData icon;
  final String label;
  final String accountName;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(
              accountName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ],
  );
}

class _CandidateDetailSheet extends StatelessWidget {
  const _CandidateDetailSheet({
    required this.controller,
    required this.item,
    required this.accounts,
    required this.categories,
    required this.close,
  });
  final CandidateInboxController controller;
  final CandidateReviewItem item;
  final List<Map<String, Object?>> accounts, categories;
  final VoidCallback close;
  @override
  Widget build(BuildContext context) {
    final busy = controller.resolvingCandidateId == item.id;
    final existing = controller.alternatives
        .where(
          (target) =>
              target.targetType != CandidateMatchTargetType.scheduledEvent,
        )
        .firstOrNull;
    final scheduled = controller.alternatives
        .where(
          (target) =>
              target.targetType == CandidateMatchTargetType.scheduledEvent,
        )
        .firstOrNull;
    final canReconcileAll =
        item.match.kind == CandidateMatchKind.ambiguous &&
        existing != null &&
        scheduled != null &&
        existing.type == scheduled.type &&
        existing.amountSatang == scheduled.amountSatang &&
        existing.accountId == scheduled.accountId &&
        (existing.type != 'transfer' ||
            existing.destinationAccountId == scheduled.destinationAccountId);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ตรวจสอบรายการ',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            FinanceAmountText(
              satang: _CandidateInboxScreenState.signedAmount(item),
              signed: true,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text('${typeLabel(item.type)} • ${item.sourceLabel}'),
            Text('บัญชี: ${item.accountName ?? 'ยังไม่ระบุ'}'),
            if (item.destinationAccountName != null)
              Text('ปลายทาง: ${item.destinationAccountName}'),
            Text('หมวดหมู่: ${item.categoryName ?? 'ยังไม่ระบุ'}'),
            Text(
              'เวลา: ${_CandidateInboxScreenState.dateTime(item.occurredAt)}',
            ),
            const Divider(height: 28),
            Text(
              _CandidateInboxScreenState.recommendation(item.match.kind),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (canReconcileAll) ...[
              const SizedBox(height: 12),
              Card(
                color: Theme.of(context).colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'รายการนี้ถูกบันทึกแล้ว และตรงกับรายการในปฏิทินด้วย',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text('รายการจริง: ${existing.title}'),
                      Text('รายการในปฏิทิน: ${scheduled.title}'),
                      const SizedBox(height: 10),
                      FilledButton(
                        key: const Key('candidate-reconcile-all'),
                        onPressed: busy
                            ? null
                            : () => _reconcileAll(existing, scheduled),
                        child: const Text('ยืนยันว่าเป็นรายการเดียวกันทั้งหมด'),
                      ),
                      const Text(
                        'หรือเลือก “ใช่ รายการเดียวกัน” ด้านล่าง หากต้องการเชื่อมเฉพาะรายการที่บันทึกแล้ว',
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (controller.alternatives.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('เลือกสร้างรายการใหม่ หรือข้ามรายการนี้'),
              ),
            for (final target in controller.alternatives)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        target.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        '${target.accountName} • ${_CandidateInboxScreenState.dateTime(target.occurredAt)}',
                      ),
                      ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: const Text('ดูเหตุผล'),
                        children: [
                          for (final reason in target.reasons)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text('✓ ${friendlyReason(reason)}'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      FilledButton.tonal(
                        onPressed: busy ? null : () => _acceptTarget(target),
                        child: Text(
                          target.targetType ==
                                  CandidateMatchTargetType.scheduledEvent
                              ? 'ยืนยันว่ารายการนี้เกิดขึ้นแล้ว'
                              : 'ใช่ รายการเดียวกัน',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ผลที่จะเกิดขึ้น',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.type == 'transfer'
                          ? 'จะสร้างการโอน ${FinanceMoneyFormat.satang(item.amountSatang)} แบบสองฝั่งหลังยืนยัน'
                          : '${typeLabel(item.type)} ${FinanceMoneyFormat.satang(item.amountSatang)} จะเปลี่ยนเงินจริงหลังยืนยันเท่านั้น',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              key: const Key('candidate-create-new'),
              onPressed: busy ? null : () => _createNew(context),
              child: const Text('สร้างเป็นรายการใหม่'),
            ),
            TextButton(
              key: const Key('candidate-ignore'),
              onPressed: busy ? null : () => _ignore(context),
              child: const Text('ไม่ใช่รายการเงิน / ข้ามรายการนี้'),
            ),
            if (busy) const Center(child: CircularProgressIndicator()),
            if (controller.error != null)
              Text(
                controller.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _acceptTarget(CandidateTargetSummary target) async {
    final ok = target.targetType == CandidateMatchTargetType.scheduledEvent
        ? await controller.resolveScheduled(
            target,
            destinationAccountId: item.destinationAccountId,
          )
        : await controller.resolveExisting(target);
    if (ok) close();
  }

  Future<void> _reconcileAll(
    CandidateTargetSummary existing,
    CandidateTargetSummary scheduled,
  ) async {
    if (await controller.reconcileAll(existing, scheduled)) close();
  }

  Future<void> _createNew(BuildContext context) async {
    String? categoryId = item.categoryId;
    String? destinationId = item.destinationAccountId;
    if (item.type == 'transfer' && destinationId == null) {
      destinationId = await select(
        context,
        'เลือกบัญชีปลายทาง',
        accounts
            .where((a) => a['id'] != item.accountId && a['is_active'] == 1)
            .toList(),
      );
      if (destinationId == null) return;
    } else if (item.type != 'transfer' && categoryId == null) {
      final expected = item.type == 'income' ? 'income' : 'expense';
      categoryId = await select(
        context,
        'เลือกหมวดหมู่',
        categories.where((c) => c['category_type'] == expected).toList(),
      );
      if (categoryId == null) return;
    }
    if (await controller.createNew(
      categoryId: categoryId,
      destinationAccountId: destinationId,
    )) {
      close();
    }
  }

  Future<void> _ignore(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ข้ามรายการนี้?'),
        content: const Text('จะไม่มีการเพิ่มหรือลดยอดเงินจริง'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ข้ามรายการ'),
          ),
        ],
      ),
    );
    if (confirmed == true && await controller.ignore()) close();
  }

  Future<String?> select(
    BuildContext context,
    String title,
    List<Map<String, Object?>> rows,
  ) => showDialog<String>(
    context: context,
    builder: (_) => SimpleDialog(
      title: Text(title),
      children: [
        for (final row in rows)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, row['id'] as String),
            child: Text(row['name'] as String),
          ),
      ],
    ),
  );
  static String typeLabel(String type) => switch (type) {
    'income' => 'รายรับ',
    'expense' => 'รายจ่าย',
    'refund' => 'เงินคืน',
    'transfer' => 'โอนเงิน',
    _ => 'รายการเงิน',
  };
  static String friendlyReason(CandidateMatchReason reason) =>
      switch (reason.code) {
        'exact_amount' => 'ยอดเงินตรงกัน',
        'exact_account' => 'บัญชีตรงกัน',
        'close_time' => 'เวลาใกล้กับรายการที่บันทึกไว้',
        'scheduled_time' => 'เวลาใกล้กับวันที่วางแผนไว้',
        'exact_category' => 'หมวดหมู่ตรงกัน',
        'exact_destination' => 'บัญชีปลายทางตรงกัน',
        _ => reason.description,
      };
}
