import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/money.dart';
import 'app_state.dart';
import 'theme/app_theme.dart';

class DailyDriverScreen extends StatefulWidget {
  const DailyDriverScreen({required this.state, super.key});
  final AppState state;

  @override
  State<DailyDriverScreen> createState() => _DailyDriverScreenState();
}

class _DailyDriverScreenState extends State<DailyDriverScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Text(
          ['บัญชีของฉัน', 'ประวัติทั้งหมด', 'หมวดหมู่', 'ข้อมูลของฉัน'][index],
        ),
      ),
      body: [
        _AccountsTab(state: widget.state),
        _ActivityTab(state: widget.state),
        _CategoriesTab(state: widget.state),
        _DataTab(state: widget.state),
      ][index],
      floatingActionButton: index < 3
          ? FloatingActionButton.extended(
              onPressed: () => index == 0
                  ? _accountDialog(context, widget.state)
                  : index == 1
                  ? showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) => DailyQuickAdd(state: widget.state),
                    )
                  : _categoryDialog(context, widget.state),
              icon: const Icon(Icons.add),
              label: Text(
                index == 0
                    ? 'เพิ่มบัญชี'
                    : index == 1
                    ? 'บันทึกรายการ'
                    : 'เพิ่มหมวด',
              ),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            label: 'บัญชี',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'รายการ',
          ),
          NavigationDestination(
            icon: Icon(Icons.category_outlined),
            label: 'หมวด',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            label: 'ข้อมูล',
          ),
        ],
      ),
    ),
  );
}

class _AccountsTab extends StatelessWidget {
  const _AccountsTab({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final total = state.accounts
        .where((a) => a['is_active'] == 1 && a['include_in_net_worth'] == 1)
        .fold<int>(0, (sum, a) => sum + (a['balance_satang'] as int));
    return RefreshIndicator(
      onRefresh: state.refreshDailyData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _HeroCard(
            title: 'เงินจริงรวม',
            value: _money(total),
            subtitle: 'ผลรวมบัญชี Active ที่รวมในเงินจริง',
          ),
          const SizedBox(height: 12),
          if (state.accounts.isEmpty)
            const _Empty(
              icon: Icons.account_balance_wallet_outlined,
              text: 'ยังไม่มีบัญชี กดเพิ่มบัญชีเพื่อเริ่มใช้เงินจริง',
            ),
          for (final account in state.accounts)
            Card(
              child: ListTile(
                minTileHeight: 72,
                leading: Icon(_accountIcon(account['account_type'] as String?)),
                title: Text(account['name'] as String),
                subtitle: Text(
                  '${_accountType(account['account_type'] as String?)} • ${account['is_active'] == 1 ? 'Active' : 'Archived'}',
                ),
                trailing: Text(
                  _money(account['balance_satang'] as int),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: (account['balance_satang'] as int) < 0
                        ? AppColors.red
                        : null,
                  ),
                ),
                onTap: () => _accountActions(context, state, account),
                onLongPress: () async {
                  try {
                    if (account['is_active'] == 1) {
                      await state._storeArchive(account['id'] as String);
                    } else {
                      await state._storeRestore(account['id'] as String);
                    }
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('$error')));
                    }
                  }
                },
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'แตะค้างบัญชีเพื่อ Archive/Restore • บัญชีสุดท้ายปิดไม่ได้',
              style: TextStyle(color: AppColors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTab extends StatelessWidget {
  const _ActivityTab({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => state.activities.isEmpty
      ? const _Empty(
          icon: Icons.receipt_long_outlined,
          text: 'ยังไม่มีรายการ กดบันทึกรายการแรก',
        )
      : ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: state.activities.length,
          itemBuilder: (context, index) {
            final row = state.activities[index];
            final type = row['type'] as String;
            final incoming =
                type == 'income' || type == 'refund' || type == 'transfer_in';
            return Dismissible(
              key: ValueKey(row['id']),
              background: Container(
                color: AppColors.red,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.all(20),
                child: const Icon(Icons.delete_outline, color: Colors.white),
              ),
              direction: DismissDirection.endToStart,
              confirmDismiss: (_) async => type != 'transfer_in',
              onDismissed: (_) async {
                final id = row['id'] as String;
                await state.removeTransaction(id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('ย้ายรายการไปถังขยะแล้ว'),
                      action: SnackBarAction(
                        label: 'เลิกทำ',
                        onPressed: () => state.undoTransaction(id),
                      ),
                    ),
                  );
                }
              },
              child: ListTile(
                leading: CircleAvatar(
                  child: Icon(_icon(row['icon_key'] as String?)),
                ),
                title: Text(
                  (row['category_name'] as String?) ?? _typeLabel(type),
                ),
                subtitle: Text(
                  '${row['account_name']} • ${_date(row['occurred_at'] as String)}\n${row['source']} ${row['note'] == null ? '' : '• ${row['note']}'}',
                ),
                isThreeLine: true,
                trailing: Text(
                  '${incoming ? '+' : '-'}${_money(row['amount_satang'] as int)}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: incoming ? Colors.green.shade700 : AppColors.red,
                  ),
                ),
                onTap:
                    type == 'transfer_in' ||
                        type == 'transfer_out' ||
                        type == 'balance_adjustment'
                    ? null
                    : () => _editTransaction(context, state, row),
              ),
            );
          },
        );
}

class _CategoriesTab extends StatelessWidget {
  const _CategoriesTab({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (state.categories.isEmpty)
        const _Empty(icon: Icons.category_outlined, text: 'ยังไม่มีหมวดหมู่'),
      for (final row in state.categories)
        Card(
          child: ListTile(
            leading: Icon(_icon(row['icon_key'] as String?)),
            title: Text(row['name'] as String),
            subtitle: Text(
              row['category_type'] == 'income' ? 'รายรับ' : 'รายจ่าย',
            ),
          ),
        ),
    ],
  );
}

class _DataTab extends StatelessWidget {
  const _DataTab({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const _HeroCard(
        title: 'โหมดข้อมูลจริง',
        value: 'Local-first',
        subtitle: 'ไม่มี Demo seed ถูกล้างอัตโนมัติ แม้ยอดติดลบ',
      ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        icon: const Icon(Icons.save_outlined),
        label: const Text('โปรไฟล์การเงิน'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => FinancialProfilesScreen(state: state),
          ),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.flag_outlined),
        label: const Text('ภาระและเป้าหมายค่าใช้จ่าย'),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => CommitmentsScreen(state: state)),
        ),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        icon: const Icon(Icons.backup_outlined),
        label: const Text('Backup ข้อมูลตอนนี้'),
        onPressed: () async {
          final path = await state.createBackup();
          if (context.mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('Backup แล้ว: $path')));
          }
        },
      ),
      const SizedBox(height: 8),
      FilledButton.tonalIcon(
        icon: const Icon(Icons.delete_sweep_outlined),
        label: const Text('ล้างข้อมูลทดลองและเริ่มใช้เงินจริง'),
        onPressed: () => _resetFlow(context, state),
      ),
    ],
  );
}

class FinancialProfilesScreen extends StatelessWidget {
  const FinancialProfilesScreen({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('โปรไฟล์การเงิน')),
      body: RefreshIndicator(
        onRefresh: state.refreshDailyData,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'เหมือน Save Slot ในเกม • เปิดใช้งานทีละโปรไฟล์',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            for (final profile in state.profiles)
              Card(
                color: profile['id'] == state.activeProfileId
                    ? AppColors.mintSoft
                    : null,
                child: ListTile(
                  minTileHeight: 78,
                  leading: Icon(
                    profile['id'] == state.activeProfileId
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                  ),
                  title: Text(profile['name'] as String),
                  subtitle: Text(
                    '${profile['account_count']} บัญชี • ${profile['transaction_count']} รายการ\n${profile['status']}',
                  ),
                  isThreeLine: true,
                  trailing: profile['id'] == state.activeProfileId
                      ? const Chip(label: Text('กำลังใช้'))
                      : const Icon(Icons.chevron_right),
                  onTap:
                      profile['status'] == 'archived' ||
                          profile['id'] == state.activeProfileId
                      ? null
                      : () async {
                          final confirmed =
                              await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('สลับโปรไฟล์?'),
                                  content: Text(
                                    'Dashboard และรายการทั้งหมดจะเปลี่ยนเป็น “${profile['name']}”',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('ยกเลิก'),
                                    ),
                                    FilledButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      child: const Text('สลับ'),
                                    ),
                                  ],
                                ),
                              ) ??
                              false;
                          if (confirmed) {
                            await state.switchFinancialProfile(
                              profile['id'] as String,
                            );
                          }
                        },
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('สร้างโปรไฟล์ใหม่'),
        onPressed: () async {
          final name = TextEditingController();
          final created = await showModalBottomSheet<String>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (context) => Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                MediaQuery.viewInsetsOf(context).bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'สร้าง Save ใหม่',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  TextField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อโปรไฟล์ *',
                      hintText: 'ใช้งานจริง — สิงหาคม 2569',
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      if (name.text.trim().isNotEmpty) {
                        Navigator.pop(context, name.text.trim());
                      }
                    },
                    child: const Text('สร้างและเริ่ม Onboarding'),
                  ),
                ],
              ),
            ),
          );
          name.dispose();
          if (created != null) {
            await state.createAndSwitchProfile(created);
            if (context.mounted) {
              Navigator.popUntil(context, (route) => route.isFirst);
            }
          }
        },
      ),
    ),
  );
}

class CommitmentsScreen extends StatelessWidget {
  const CommitmentsScreen({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => Scaffold(
      appBar: AppBar(title: const Text('ภาระและเป้าหมายค่าใช้จ่าย')),
      body: state.commitments.isEmpty
          ? const _Empty(
              icon: Icons.flag_outlined,
              text: 'ยังไม่มีภาระ กดเพิ่มรายการใหม่',
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final row in state.commitments)
                  Card(
                    child: ListTile(
                      minTileHeight: 84,
                      title: Text(row['name'] as String),
                      subtitle: Text(_commitmentSummary(row)),
                      trailing: IconButton(
                        tooltip: 'บันทึกจ่ายงวดนี้',
                        icon: const Icon(Icons.add_card),
                        onPressed: () => _payCommitment(context, state, row),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _commitmentDialog(context, state),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มรายการ'),
      ),
    ),
  );
}

String _commitmentSummary(Map<String, Object?> row) {
  final paid = row['paid_satang'] as int;
  if (row['commitment_type'] == 'open_ended') {
    final target = row['target_satang'] as int?;
    return target == null
        ? 'ค่าใช้จ่ายต่อเนื่อง • จ่ายสะสม ${_money(paid)}\nยังไม่กำหนดยอดเป้าหมาย'
        : 'จ่ายสะสม ${_money(paid)} จาก ${_money(target)}';
  }
  final total = row['total_payable_satang'] as int?;
  final remaining = total == null ? null : (total - paid).clamp(0, total);
  return 'ผ่อนแบบมียอดรวม • ${_money(paid)} / ${total == null ? 'ไม่ทราบ' : _money(total)}\nคงเหลือ ${remaining == null ? 'ไม่ทราบ' : _money(remaining)}';
}

Future<void> _commitmentDialog(BuildContext context, AppState state) async {
  final name = TextEditingController();
  final total = TextEditingController();
  final regular = TextEditingController();
  var type = 'fixed_total';
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('เพิ่มภาระ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(
                    value: 'fixed_total',
                    child: Text('ผ่อนแบบมียอดรวม'),
                  ),
                  DropdownMenuItem(
                    value: 'open_ended',
                    child: Text('ค่าใช้จ่ายต่อเนื่อง'),
                  ),
                ],
                onChanged: (v) => setDialog(() => type = v!),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'ชื่อ *'),
              ),
              if (type == 'fixed_total') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: total,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'ยอดทั้งหมด *',
                    suffixText: 'บาท',
                  ),
                ),
              ],
              const SizedBox(height: 10),
              TextField(
                controller: regular,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'จ่ายต่อเดือน (ไม่บังคับ)',
                  suffixText: 'บาท',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              final totalValue = double.tryParse(total.text);
              if (name.text.trim().isEmpty ||
                  (type == 'fixed_total' &&
                      (totalValue == null || totalValue <= 0))) {
                return;
              }
              await state.addCommitment(
                name: name.text.trim(),
                type: type,
                totalSatang: totalValue == null
                    ? null
                    : Money.fromBaht(totalValue).satang,
                regularSatang: double.tryParse(regular.text) == null
                    ? null
                    : Money.fromBaht(double.parse(regular.text)).satang,
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  total.dispose();
  regular.dispose();
}

Future<void> _payCommitment(
  BuildContext context,
  AppState state,
  Map<String, Object?> row,
) async {
  final activeAccounts = state.accounts
      .where((a) => a['is_active'] == 1)
      .toList();
  final expenseCategories = state.categories
      .where((c) => c['category_type'] == 'expense')
      .toList();
  if (activeAccounts.isEmpty || expenseCategories.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('ต้องมีบัญชีและหมวดรายจ่ายก่อน')),
    );
    return;
  }
  final amount = TextEditingController(
    text: ((row['regular_payment_satang'] as int? ?? 0) / 100).toStringAsFixed(
      2,
    ),
  );
  var account =
      row['default_account_id'] as String? ??
      activeAccounts.first['id'] as String;
  var category =
      row['category_id'] as String? ?? expenseCategories.first['id'] as String;
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: Text('จ่าย ${row['name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'จำนวนเงิน *',
                suffixText: 'บาท',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: account,
              items: [
                for (final a in activeAccounts)
                  DropdownMenuItem(
                    value: a['id'] as String,
                    child: Text(a['name'] as String),
                  ),
              ],
              onChanged: (v) => setDialog(() => account = v!),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: category,
              items: [
                for (final c in expenseCategories)
                  DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text(c['name'] as String),
                  ),
              ],
              onChanged: (v) => setDialog(() => category = v!),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              final value = double.tryParse(amount.text);
              if (value == null || value <= 0) return;
              await state.payCommitment(
                commitmentId: row['id'] as String,
                accountId: account,
                categoryId: category,
                amount: Money.fromBaht(value),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('บันทึกจ่าย'),
          ),
        ],
      ),
    ),
  );
  amount.dispose();
}

class DailyQuickAdd extends StatefulWidget {
  const DailyQuickAdd({required this.state, super.key});
  final AppState state;
  @override
  State<DailyQuickAdd> createState() => _DailyQuickAddState();
}

class _DailyQuickAddState extends State<DailyQuickAdd> {
  final amount = TextEditingController();
  final note = TextEditingController();
  String type = 'expense';
  String? accountId, toAccountId, categoryId;
  bool saving = false;

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeAccounts = widget.state.accounts
        .where((a) => a['is_active'] == 1)
        .toList();
    final validCategories = widget.state.categories
        .where(
          (c) =>
              c['category_type'] == (type == 'income' ? 'income' : 'expense'),
        )
        .toList();
    final value = double.tryParse(amount.text);
    final ready =
        value != null &&
        value > 0 &&
        accountId != null &&
        (type == 'transfer'
            ? toAccountId != null && toAccountId != accountId
            : categoryId != null);
    return PopScope(
      canPop: amount.text.isEmpty && note.text.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop && await _discard(context) && context.mounted) {
          Navigator.pop(context);
        }
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () async {
                      if ((amount.text.isEmpty && note.text.isEmpty) ||
                          await _discard(context)) {
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                    icon: const Icon(Icons.close),
                  ),
                  const Text(
                    'บันทึกรายการ',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('รายจ่าย')),
                  ButtonSegment(value: 'income', label: Text('รายรับ')),
                  ButtonSegment(value: 'transfer', label: Text('โอน')),
                ],
                selected: {type},
                onSelectionChanged: (v) => setState(() {
                  type = v.first;
                  categoryId = null;
                  toAccountId = null;
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'จำนวนเงิน *',
                  suffixText: 'บาท',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: accountId,
                decoration: InputDecoration(
                  labelText: type == 'income'
                      ? 'บัญชีปลายทาง *'
                      : 'บัญชีต้นทาง *',
                ),
                items: [
                  for (final a in activeAccounts)
                    DropdownMenuItem(
                      value: a['id'] as String,
                      child: Text(a['name'] as String),
                    ),
                ],
                onChanged: (v) => setState(() => accountId = v),
              ),
              const SizedBox(height: 12),
              if (type == 'transfer')
                DropdownButtonFormField<String>(
                  initialValue: toAccountId,
                  decoration: const InputDecoration(
                    labelText: 'บัญชีปลายทาง *',
                  ),
                  items: [
                    for (final a in activeAccounts.where(
                      (a) => a['id'] != accountId,
                    ))
                      DropdownMenuItem(
                        value: a['id'] as String,
                        child: Text(a['name'] as String),
                      ),
                  ],
                  onChanged: (v) => setState(() => toAccountId = v),
                )
              else
                DropdownButtonFormField<String>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(
                    labelText: 'หมวดหมู่ *',
                    helperText: 'กรุณาเลือกหมวดก่อนบันทึก',
                  ),
                  items: [
                    for (final c in validCategories)
                      DropdownMenuItem(
                        value: c['id'] as String,
                        child: Text(c['name'] as String),
                      ),
                  ],
                  onChanged: (v) => setState(() => categoryId = v),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: const InputDecoration(
                  labelText: 'หมายเหตุ (ไม่บังคับ)',
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: !ready || saving
                    ? null
                    : () async {
                        setState(() => saving = true);
                        try {
                          final money = Money.fromBaht(value);
                          if (type == 'transfer') {
                            await widget.state.addTransfer(
                              accountId!,
                              toAccountId!,
                              money,
                            );
                          } else {
                            await widget.state.addDailyTransaction(
                              accountId: accountId!,
                              categoryId: categoryId!,
                              type: type,
                              amount: money,
                              note: note.text.trim().isEmpty
                                  ? null
                                  : note.text.trim(),
                            );
                          }
                          if (context.mounted) Navigator.pop(context);
                        } catch (error) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('บันทึกไม่สำเร็จ: $error'),
                              ),
                            );
                          }
                          setState(() => saving = false);
                        }
                      },
                child: Text(saving ? 'กำลังบันทึก…' : 'บันทึก'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _accountActions(
  BuildContext context,
  AppState state,
  Map<String, Object?> account,
) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('แก้ชื่อ/ประเภท'),
            onTap: () => Navigator.pop(context, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('ปรับยอดพร้อม Audit trail'),
            onTap: () => Navigator.pop(context, 'adjust'),
          ),
          ListTile(
            leading: Icon(
              account['is_active'] == 1
                  ? Icons.archive_outlined
                  : Icons.unarchive_outlined,
            ),
            title: Text(
              account['is_active'] == 1 ? 'Archive บัญชี' : 'Restore บัญชี',
            ),
            onTap: () => Navigator.pop(context, 'archive'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted || action == null) return;
  if (action == 'archive') {
    try {
      if (account['is_active'] == 1) {
        await state.archiveDailyAccount(account['id'] as String);
      } else {
        await state.restoreDailyAccount(account['id'] as String);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
    return;
  }
  final value = TextEditingController(
    text: action == 'edit' ? account['name'] as String : '0',
  );
  final reason = TextEditingController();
  var type = account['account_type'] as String? ?? 'bank';
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: Text(action == 'edit' ? 'แก้บัญชี' : 'ปรับยอดบัญชี'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: value,
              keyboardType: action == 'adjust'
                  ? const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    )
                  : TextInputType.text,
              decoration: InputDecoration(
                labelText: action == 'edit'
                    ? 'ชื่อบัญชี *'
                    : 'จำนวนที่ปรับ (+/-) *',
              ),
            ),
            if (action == 'edit') ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'bank', child: Text('ธนาคาร')),
                  DropdownMenuItem(value: 'cash', child: Text('เงินสด')),
                  DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
                ],
                onChanged: (v) => setDialog(() => type = v!),
              ),
            ] else ...[
              const SizedBox(height: 10),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'เหตุผล *'),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              if (action == 'edit') {
                if (value.text.trim().isEmpty) return;
                await state.updateDailyAccount(
                  account['id'] as String,
                  value.text.trim(),
                  type,
                );
              } else {
                final delta = double.tryParse(value.text);
                if (delta == null || delta == 0 || reason.text.trim().isEmpty) {
                  return;
                }
                await state.adjustDailyAccount(
                  account['id'] as String,
                  Money.fromBaht(delta),
                  reason.text.trim(),
                );
              }
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );
  value.dispose();
  reason.dispose();
}

Future<void> _editTransaction(
  BuildContext context,
  AppState state,
  Map<String, Object?> row,
) async {
  final type = row['type'] as String;
  final amount = TextEditingController(
    text: ((row['amount_satang'] as int) / 100).toStringAsFixed(2),
  );
  final note = TextEditingController(text: row['note'] as String? ?? '');
  var account = row['account_id'] as String;
  var category = row['category_id'] as String;
  final accounts = state.accounts.where((a) => a['is_active'] == 1).toList();
  final categories = state.categories
      .where(
        (c) => c['category_type'] == (type == 'income' ? 'income' : 'expense'),
      )
      .toList();
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('แก้รายการ'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'จำนวนเงิน *'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: account,
                items: [
                  for (final a in accounts)
                    DropdownMenuItem(
                      value: a['id'] as String,
                      child: Text(a['name'] as String),
                    ),
                ],
                onChanged: (v) => setDialog(() => account = v!),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: category,
                items: [
                  for (final c in categories)
                    DropdownMenuItem(
                      value: c['id'] as String,
                      child: Text(c['name'] as String),
                    ),
                ],
                onChanged: (v) => setDialog(() => category = v!),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: note,
                decoration: const InputDecoration(labelText: 'หมายเหตุ'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              final value = double.tryParse(amount.text);
              if (value == null || value <= 0) return;
              await state.editDailyTransaction(
                id: row['id'] as String,
                accountId: account,
                categoryId: category,
                amount: Money.fromBaht(value),
                occurredAt: DateTime.parse(row['occurred_at'] as String),
                note: note.text.trim().isEmpty ? null : note.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );
  amount.dispose();
  note.dispose();
}

Future<void> _accountDialog(BuildContext context, AppState state) async {
  final name = TextEditingController();
  final amount = TextEditingController(text: '0');
  var type = 'bank';
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('เพิ่มบัญชี'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'ชื่อบัญชี *'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: type,
              items: const [
                DropdownMenuItem(value: 'bank', child: Text('ธนาคาร')),
                DropdownMenuItem(value: 'cash', child: Text('เงินสด')),
                DropdownMenuItem(value: 'wallet', child: Text('Wallet')),
              ],
              onChanged: (v) => setDialog(() => type = v!),
              decoration: const InputDecoration(labelText: 'ประเภท *'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
                signed: true,
              ),
              decoration: const InputDecoration(
                labelText: 'ยอดเริ่มต้น',
                suffixText: 'บาท',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await state.addAccount(
                name.text.trim(),
                type,
                Money.fromBaht(double.tryParse(amount.text) ?? 0),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  amount.dispose();
}

Future<void> _categoryDialog(BuildContext context, AppState state) async {
  final name = TextEditingController();
  var type = 'expense';
  var icon = 'sports_esports';
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialog) => AlertDialog(
        title: const Text('เพิ่มหมวดหมู่'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'ชื่อหมวด *'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: type,
              items: const [
                DropdownMenuItem(value: 'expense', child: Text('รายจ่าย')),
                DropdownMenuItem(value: 'income', child: Text('รายรับ')),
              ],
              onChanged: (v) => setDialog(() => type = v!),
              decoration: const InputDecoration(labelText: 'ประเภท *'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: icon,
              items: const [
                DropdownMenuItem(value: 'sports_esports', child: Text('เกม')),
                DropdownMenuItem(value: 'restaurant', child: Text('อาหาร')),
                DropdownMenuItem(value: 'payments', child: Text('เงิน')),
                DropdownMenuItem(value: 'category', child: Text('ทั่วไป')),
              ],
              onChanged: (v) => setDialog(() => icon = v!),
              decoration: const InputDecoration(labelText: 'ไอคอน *'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () async {
              if (name.text.trim().isEmpty) return;
              await state.addCategory(name.text.trim(), type, icon);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('เพิ่ม'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
}

Future<void> _resetFlow(BuildContext context, AppState state) async {
  final first =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ล้างข้อมูลทั้งหมด?'),
          content: const Text(
            'บัญชี หมวด รายการ ภาระ เป้าหมาย และข้อมูลนำเข้าจะถูกล้างแบบ Atomic\n\nแนะนำให้ Backup ก่อนดำเนินการ',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton.tonal(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ดำเนินการต่อ'),
            ),
          ],
        ),
      ) ??
      false;
  if (!first || !context.mounted) return;
  final second =
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ยืนยันครั้งสุดท้าย'),
          content: const Text(
            'การล้างไม่สามารถ Undo ได้ และจะกลับไปหน้าเริ่มต้น',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ไม่ล้าง'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ล้างข้อมูล'),
            ),
          ],
        ),
      ) ??
      false;
  if (second) {
    await state.resetAllData();
    if (context.mounted) Navigator.popUntil(context, (route) => route.isFirst);
  }
}

Future<bool> _discard(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ทิ้งข้อมูลที่กรอก?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('แก้ไขต่อ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ทิ้งข้อมูล'),
          ),
        ],
      ),
    ) ??
    false;

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });
  final String title, value, subtitle;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70)),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 30,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(subtitle, style: const TextStyle(color: AppColors.mint)),
      ],
    ),
  );
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.muted),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

String _money(int satang) => '฿${(satang / 100).toStringAsFixed(2)}';
String _date(String iso) {
  final d = DateTime.parse(iso).toLocal();
  return '${d.day}/${d.month}/${d.year + 543} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String _accountType(String? type) => switch (type) {
  'cash' => 'เงินสด',
  'wallet' => 'Wallet',
  _ => 'ธนาคาร',
};
IconData _accountIcon(String? type) => switch (type) {
  'cash' => Icons.payments_outlined,
  'wallet' => Icons.account_balance_wallet_outlined,
  _ => Icons.account_balance_outlined,
};
String _typeLabel(String type) => switch (type) {
  'income' => 'รายรับ',
  'expense' => 'รายจ่าย',
  'refund' => 'เงินคืน',
  'transfer_in' || 'transfer_out' => 'โอน',
  'balance_adjustment' => 'ปรับยอด',
  _ => type,
};
IconData _icon(String? key) => switch (key) {
  'sports_esports' => Icons.sports_esports,
  'restaurant' => Icons.restaurant,
  'payments' => Icons.payments_outlined,
  'phone_android' => Icons.phone_android,
  _ => Icons.category_outlined,
};

extension _DailyStoreActions on AppState {
  Future<void> _storeArchive(String id) async {
    await archiveDailyAccount(id);
  }

  Future<void> _storeRestore(String id) async {
    await restoreDailyAccount(id);
  }
}
