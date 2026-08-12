import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/money.dart';
import '../domain/models/financial_models.dart';
import 'app_state.dart';
import 'theme/app_theme.dart';
import 'daily_driver_screen.dart';
import 'local_finance_store.dart';

class FinanceApp extends StatefulWidget {
  const FinanceApp({this.state, super.key});
  final AppState? state;
  @override
  State<FinanceApp> createState() => _FinanceAppState();
}

class _FinanceAppState extends State<FinanceApp> {
  late final state = widget.state ?? AppState();

  @override
  void initState() {
    super.initState();
    state.initialize();
  }

  @override
  void dispose() {
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'เงินกูไปไหน',
    theme: AppTheme.light,
    home: ListenableBuilder(
      listenable: state,
      builder: (context, child) => _AppRouter(state: state),
    ),
  );
}

class _AppRouter extends StatelessWidget {
  const _AppRouter({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    if (!state.initialized && state.viewStatus == ViewStatus.loading) {
      return _SystemState(state: state);
    }
    if (state.viewStatus != ViewStatus.ready) return _SystemState(state: state);
    return switch (state.step) {
      AppStep.welcome => WelcomeScreen(onNext: () => state.go(AppStep.payday)),
      AppStep.payday => PaydayScreen(state: state),
      AppStep.accounts => AccountScreen(state: state),
      AppStep.recurring => RecurringScreen(state: state),
      AppStep.saving => SavingScreen(state: state),
      AppStep.dashboard => DashboardScreen(state: state),
    };
  }
}

class _Page extends StatelessWidget {
  const _Page({required this.child, this.dark = false});
  final Widget child;
  final bool dark;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: dark ? AppColors.ink : AppColors.paper,
    body: SafeArea(
      child: Padding(padding: const EdgeInsets.all(22), child: child),
    ),
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({required this.onNext, super.key});
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) => _Page(
    dark: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Spacer(),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppColors.mint,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Icon(Icons.currency_exchange_rounded, size: 36),
        ),
        const SizedBox(height: 28),
        const Text(
          'PERSONAL FINANCE HEALTH',
          style: TextStyle(
            color: AppColors.mint,
            fontSize: 12,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'เงินหายไปไหน\nเดี๋ยวหาให้',
          style: Theme.of(
            context,
          ).textTheme.displaySmall?.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 16),
        const Text(
          'รู้เงินจริง งบวันนี้ และ Forecast แบบไม่หลอกตัวเอง',
          style: TextStyle(color: Color(0xFFB7C2C5), fontSize: 16),
        ),
        const SizedBox(height: 28),
        const _WelcomeItem('01', 'ตั้งรอบเงินเดือน'),
        const _WelcomeItem('02', 'เพิ่มบัญชี'),
        const _WelcomeItem('03', 'เริ่มตามเงิน'),
        const Spacer(),
        FilledButton(
          onPressed: onNext,
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('เริ่มตั้งค่า'),
              SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'ข้อมูลเก็บในเครื่อง • ไม่ขอรหัส Banking',
            style: TextStyle(color: Color(0xFFB7C2C5), fontSize: 12),
          ),
        ),
      ],
    ),
  );
}

class _WelcomeItem extends StatelessWidget {
  const _WelcomeItem(this.number, this.label);
  final String number, label;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      '$number  $label',
      style: const TextStyle(color: Colors.white, fontSize: 15),
    ),
  );
}

Future<bool> _confirmDiscard(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ทิ้งการเปลี่ยนแปลง?'),
        content: const Text(
          'ข้อมูลที่แก้ในหน้านี้จะหาย แต่รายการที่บันทึกแล้วไม่โดนแตะ',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('แก้ไขต่อ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'ทิ้งข้อมูล',
              style: TextStyle(color: AppColors.red),
            ),
          ),
        ],
      ),
    ) ??
    false;

class _FormShell extends StatelessWidget {
  const _FormShell({
    required this.title,
    required this.onBack,
    required this.children,
    required this.onNext,
    this.nextEnabled = true,
  });
  final String title;
  final VoidCallback onBack, onNext;
  final List<Widget> children;
  final bool nextEnabled;
  @override
  Widget build(BuildContext context) => _Page(
    child: Column(
      children: [
        Row(
          children: [
            IconButton.filledTonal(
              onPressed: onBack,
              tooltip: 'ย้อนกลับ',
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'เงินกูไปไหน',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Expanded(child: ListView(children: children)),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: nextEnabled ? onNext : null,
          child: const Text('ถัดไป'),
        ),
      ],
    ),
  );
}

class PaydayScreen extends StatefulWidget {
  const PaydayScreen({required this.state, super.key});
  final AppState state;
  @override
  State<PaydayScreen> createState() => _PaydayScreenState();
}

class _PaydayScreenState extends State<PaydayScreen> {
  late final controller = TextEditingController(text: '${widget.state.payday}');
  bool dirty = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void back() async {
    if (!dirty || await _confirmDiscard(context)) {
      widget.state.go(AppStep.welcome);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = int.tryParse(controller.text);
    return _FormShell(
      title: 'วันเงินเดือนออก',
      onBack: back,
      nextEnabled: day != null && day >= 1 && day <= 31,
      onNext: () {
        widget.state.payday = day!;
        widget.state.go(AppStep.accounts);
      },
      children: [
        const Text(
          'Required ก่อนสร้างรอบงบแรก',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'วันที่เงินเดือนออก'),
          onChanged: (_) => setState(() => dirty = true),
        ),
        const SizedBox(height: 16),
        const Text('ถ้าชนวันหยุด', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'before', label: Text('ก่อนหน้า')),
            ButtonSegment(value: 'after', label: Text('วันถัดไป')),
            ButtonSegment(value: 'same', label: Text('วันเดิม')),
          ],
          selected: {widget.state.holidayRule},
          onSelectionChanged: (values) => setState(() {
            widget.state.holidayRule = values.first;
            dirty = true;
          }),
        ),
        const SizedBox(height: 16),
        const _Info('ใช้ค่านี้แบ่ง “รอบเงินเดือน” ไม่ได้ Hardcode ไว้ในแอป'),
      ],
    );
  }
}

class AccountScreen extends StatefulWidget {
  const AccountScreen({required this.state, super.key});
  final AppState state;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  bool dirty = false;

  @override
  void initState() {
    super.initState();
    if (widget.state.onboardingAccounts.isEmpty) {
      widget.state.onboardingAccounts = [
        OnboardingAccountInput(
          id: 'primary',
          name: widget.state.accountName,
          type: 'bank',
          openingBalance: widget.state.openingBalance,
        ),
      ];
      widget.state.salaryAccountDraftId = 'primary';
    }
  }

  void back() async {
    if (!dirty || await _confirmDiscard(context)) {
      widget.state.go(AppStep.payday);
    }
  }

  Future<void> editAccount([OnboardingAccountInput? existing]) async {
    final result = await Navigator.push<OnboardingAccountInput>(
      context,
      MaterialPageRoute(
        builder: (_) => _AccountDraftEditor(existing: existing),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final index = widget.state.onboardingAccounts.indexWhere(
        (item) => item.id == result.id,
      );
      if (index < 0) {
        widget.state.onboardingAccounts.add(result);
      } else {
        widget.state.onboardingAccounts[index] = result;
      }
      widget.state.salaryAccountDraftId ??= result.id;
      dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.state.onboardingAccounts.fold<Money>(
      Money.zero,
      (sum, item) => sum + item.openingBalance,
    );
    return _FormShell(
      title: 'บัญชีและยอดเริ่มต้น',
      onBack: back,
      nextEnabled: widget.state.onboardingAccounts.isNotEmpty,
      onNext: () {
        final salary = widget.state.onboardingAccounts.firstWhere(
          (item) => item.id == widget.state.salaryAccountDraftId,
          orElse: () => widget.state.onboardingAccounts.first,
        );
        widget.state.accountName = salary.name;
        widget.state.openingBalance = salary.openingBalance;
        widget.state.go(AppStep.recurring);
      },
      children: [
        const Text(
          'ยอด Required ตอนเพิ่มบัญชีแต่ละใบ',
          style: TextStyle(color: AppColors.muted),
        ),
        const SizedBox(height: 18),
        for (final account in widget.state.onboardingAccounts)
          Card(
            child: ListTile(
              onTap: () => editAccount(account),
              leading: Icon(
                account.type == 'wallet' ? Icons.wallet : Icons.account_balance,
              ),
              title: Text(account.name),
              subtitle: Text(
                account.id == widget.state.salaryAccountDraftId
                    ? 'บัญชีเงินเดือน'
                    : account.type,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_money(account.openingBalance)),
                  IconButton(
                    onPressed: widget.state.onboardingAccounts.length == 1
                        ? null
                        : () => setState(() {
                            widget.state.onboardingAccounts.removeWhere(
                              (item) => item.id == account.id,
                            );
                            if (widget.state.salaryAccountDraftId ==
                                account.id) {
                              widget.state.salaryAccountDraftId =
                                  widget.state.onboardingAccounts.first.id;
                            }
                            dirty = true;
                          }),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
            ),
          ),
        _DarkCard(
          label: 'เงินจริงรวม',
          value: _money(total),
          note:
              'ผลรวมยอดตั้งต้น ${widget.state.onboardingAccounts.length} บัญชี',
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: editAccount,
          icon: const Icon(Icons.add),
          label: const Text('เพิ่มบัญชี'),
        ),
      ],
    );
  }
}

class _AccountDraftEditor extends StatefulWidget {
  const _AccountDraftEditor({this.existing});
  final OnboardingAccountInput? existing;
  @override
  State<_AccountDraftEditor> createState() => _AccountDraftEditorState();
}

class _AccountDraftEditorState extends State<_AccountDraftEditor> {
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final balance = TextEditingController(
    text: widget.existing?.openingBalance.baht.toStringAsFixed(0) ?? '0',
  );
  late String type = widget.existing?.type ?? 'bank';
  bool submitting = false;

  @override
  void dispose() {
    name.dispose();
    balance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(balance.text);
    final valid = name.text.trim().isNotEmpty && amount != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? 'เพิ่มบัญชี' : 'แก้บัญชี'),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            20,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          children: [
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'ชื่อบัญชี *'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            const Text('ประเภทบัญชี'),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'bank', label: Text('ธนาคาร')),
                ButtonSegment(value: 'wallet', label: Text('Wallet')),
                ButtonSegment(value: 'cash', label: Text('เงินสด')),
              ],
              selected: {type},
              onSelectionChanged: (value) => setState(() => type = value.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: balance,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              decoration: const InputDecoration(
                labelText: 'ยอดเริ่มต้น',
                suffixText: 'บาท',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            const Text(
              'ยอดตั้งต้นไม่ใช่รายรับ และจะไม่แสดงใน Activity',
              style: TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: !valid || submitting
                  ? null
                  : () {
                      setState(() => submitting = true);
                      Navigator.pop(
                        context,
                        OnboardingAccountInput(
                          id:
                              widget.existing?.id ??
                              DateTime.now().microsecondsSinceEpoch.toString(),
                          name: name.text.trim(),
                          type: type,
                          openingBalance: Money.fromBaht(amount),
                        ),
                      );
                    },
              child: const Text('บันทึกบัญชี'),
            ),
          ],
        ),
      ),
    );
  }
}

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) => _FormShell(
    title: 'รายจ่ายประจำ',
    onBack: () => state.go(AppStep.accounts),
    onNext: () => state.go(AppStep.saving),
    children: [
      const Text(
        'วันสิ้นสุดไม่ทราบได้ ระบบจะทำซ้ำจนกว่าจะปิด',
        style: TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 14),
      for (final item in const [
        ('ให้พ่อแม่', 2000),
        ('ผ่อนโทรศัพท์', 1000),
        ('ค่าฟัน', 2500),
        ('ค่าเน็ต', 499),
      ])
        _RecurringRow(name: item.$1, amount: item.$2),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () {},
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มรายการประจำ'),
      ),
    ],
  );
}

class SavingScreen extends StatefulWidget {
  const SavingScreen({required this.state, super.key});
  final AppState state;
  @override
  State<SavingScreen> createState() => _SavingScreenState();
}

class _SavingScreenState extends State<SavingScreen> {
  late final saving = TextEditingController(
    text: widget.state.savingTarget.baht.toStringAsFixed(0),
  );
  late final emergency = TextEditingController(
    text: widget.state.emergencyTarget.baht.toStringAsFixed(0),
  );
  @override
  void dispose() {
    saving.dispose();
    emergency.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _FormShell(
    title: 'เป้าหมายเงินออม',
    onBack: () => widget.state.go(AppStep.recurring),
    onNext: () {
      widget.state.savingTarget = Money.fromBaht(
        double.tryParse(saving.text) ?? 0,
      );
      widget.state.emergencyTarget = Money.fromBaht(
        double.tryParse(emergency.text) ?? 0,
      );
      widget.state.completeOnboarding();
    },
    children: [
      TextField(
        controller: saving,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'ออมต่อรอบ',
          suffixText: 'บาท',
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: emergency,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          labelText: 'เป้าหมายฉุกเฉิน',
          suffixText: 'บาท',
        ),
      ),
      const SizedBox(height: 14),
      const Text('บัญชีออมแยก (เลือกภายหลังได้)'),
      const SizedBox(height: 8),
      for (final account in widget.state.onboardingAccounts)
        ListTile(
          selected: account.id == widget.state.savingsAccountDraftId,
          leading: Icon(
            account.id == widget.state.savingsAccountDraftId
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
          ),
          title: Text(account.name),
          subtitle: Text(account.type),
          onTap: () =>
              setState(() => widget.state.savingsAccountDraftId = account.id),
        ),
      const SizedBox(height: 16),
      const _Info(
        'เงินฉุกเฉินจะคำนวณหลังเชื่อมบัญชีออม ห้ามนับยอดรวมให้อัตโนมัติ',
      ),
    ],
  );
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final data = state.snapshot;
    final projection = state.projectionSnapshot;
    final foodBudget = projection?.categoryBudgets
        .where((item) => item.name == 'อาหาร')
        .firstOrNull;
    final foodRatio = (foodBudget?.budgetUsedRatio ?? 0).clamp(0.0, 1.0);
    final accountBreakdown = state.accounts
        .where((account) => account['is_active'] == 1)
        .map(
          (account) =>
              '${account['name']} ${_money(Money.fromSatang(account['balance_satang'] as int))}',
        )
        .toList();
    return Scaffold(
      backgroundColor: const Color(0xFFEDF1EE),
      body: SafeArea(
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 26),
              decoration: const BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const _DataPill(),
                      IconButton(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DailyDriverScreen(state: state),
                          ),
                        ),
                        tooltip: 'ตั้งค่า',
                        icon: const Icon(
                          Icons.settings_outlined,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'เงินหายไปไหน เดี๋ยวหาให้',
                    style: TextStyle(color: Color(0xFFAAB8BD)),
                  ),
                  const Text(
                    'วันนี้ยังรอด',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 40,
                      height: 1,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'เงินจริงรวม',
                    style: TextStyle(color: Color(0xFFAAB8BD)),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _money(data.currentCash),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextButton(
                        onPressed: () => _breakdown(
                          context,
                          'เงินจริงรวม',
                          accountBreakdown.isEmpty
                              ? ['ยังไม่มีบัญชีที่เปิดใช้งาน']
                              : accountBreakdown,
                        ),
                        child: const Text(
                          'ดูที่มา',
                          style: TextStyle(color: AppColors.mint),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _MetricCard(
                          label: 'วันนี้ใช้ได้',
                          value: _money(data.dailyAllowance),
                          note:
                              'งบคงเหลือ ÷ ${projection?.daysRemaining ?? 1} วัน',
                          tone: AppColors.mintSoft,
                          onTap: () => _breakdown(context, 'งบใช้ได้วันนี้', [
                            'งบยืดหยุ่นคงเหลือ ${_money(projection?.flexibleMoneyRemaining ?? Money.zero)}',
                            '÷ ${projection?.daysRemaining ?? 1} วันที่เหลือ',
                            '= ${_money(data.dailyAllowance)}',
                          ]),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MetricCard(
                          label: 'Forecast สิ้นรอบ',
                          value: _money(data.forecast),
                          note: 'เหลือตามแผน',
                          onTap: () => _breakdown(context, 'Forecast สิ้นรอบ', [
                            'เงินจริง ${_money(projection?.actualMoney ?? Money.zero)}',
                            '+ รายรับที่ยังไม่เข้า ${_money(projection?.expectedIncomeRemaining ?? Money.zero)}',
                            '− ภาระที่ยังไม่จ่าย ${_money(projection?.unpaidObligations ?? Money.zero)}',
                            '− งบที่ยังวางแผนใช้ ${_money(projection?.plannedFlexibleSpendRemaining ?? Money.zero)}',
                            '= ${_money(data.forecast)}',
                          ]),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => _breakdown(
                      context,
                      foodBudget?.name ?? 'การใช้จ่ายตามหมวด',
                      foodBudget == null
                          ? ['ยังไม่ได้ตั้งงบหมวดอาหาร']
                          : [
                              'ใช้สุทธิ ${_money(foodBudget.spentNet)}',
                              'งบทั้งหมด ${_money(foodBudget.budget)}',
                              'คงเหลือ ${_money(foodBudget.remainingBudget)}',
                              'รอบผ่านไป ${(foodBudget.cycleElapsedRatio * 100).round()}%',
                            ],
                    ),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            projection?.warnings.firstOrNull ??
                                'รายจ่ายยังอยู่ในแผน',
                            style: const TextStyle(
                              color: AppColors.orange,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            foodBudget == null
                                ? 'ยังไม่ได้ตั้งงบอาหาร'
                                : 'อาหารใช้ไปแล้ว ${((foodBudget.budgetUsedRatio ?? 0) * 100).round()}%',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                            value: foodRatio,
                            minHeight: 8,
                            color: AppColors.orange,
                            backgroundColor: Color(0xFFE4E8E5),
                            borderRadius: BorderRadius.all(Radius.circular(99)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            foodBudget == null
                                ? 'แตะเพื่อตรวจรายละเอียด'
                                : 'ใช้ ${_money(foodBudget.spentNet)} จากงบ ${_money(foodBudget.budget)}',
                            style: const TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _InstallmentCard(
                    progress: state.phoneProgress,
                    onSetup: () => _configureInstallment(context, state),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => DailyQuickAdd(state: state),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('บันทึกรายการเร็ว'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const StatementPreviewScreen(),
                      ),
                    ),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('นำเข้า Statement'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class QuickAddSheet extends StatefulWidget {
  const QuickAddSheet({super.key});
  @override
  State<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends State<QuickAddSheet> {
  final amount = TextEditingController();
  final focus = FocusNode();
  String? category;
  bool dirty = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => focus.requestFocus());
  }

  @override
  void dispose() {
    amount.dispose();
    focus.dispose();
    super.dispose();
  }

  Future<void> close() async {
    if (!dirty || await _confirmDiscard(context)) {
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) close();
    },
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        22,
        12,
        22,
        MediaQuery.viewInsetsOf(context).bottom + 22,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: close,
                  tooltip: 'ปิด',
                  icon: const Icon(Icons.close),
                ),
                const SizedBox(width: 8),
                Text(
                  'บันทึกรายการเร็ว',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('รายจ่าย')),
                ButtonSegment(value: 'income', label: Text('รายรับ')),
                ButtonSegment(value: 'transfer', label: Text('โอน')),
              ],
              selected: const {'expense'},
              onSelectionChanged: (_) {},
            ),
            const SizedBox(height: 18),
            TextField(
              controller: amount,
              focusNode: focus,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(fontSize: 42, fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: 'จำนวนเงิน',
                suffixText: 'บาท',
              ),
              onChanged: (_) => setState(() => dirty = true),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: () async {
                final result = await showModalBottomSheet<String>(
                  context: context,
                  builder: (_) => const _CategoryPicker(),
                );
                if (result != null) {
                  setState(() {
                    category = result;
                    dirty = true;
                  });
                }
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(category ?? 'เลือกหมวด (Required)'),
                  const Icon(Icons.keyboard_arrow_down),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const DropdownMenu<String>(
              expandedInsets: EdgeInsets.zero,
              initialSelection: 'salary',
              label: Text('บัญชี'),
              dropdownMenuEntries: [
                DropdownMenuEntry(value: 'salary', label: 'บัญชีเงินเดือน'),
                DropdownMenuEntry(value: 'cash', label: 'เงินสด'),
              ],
            ),
            const SizedBox(height: 18),
            FilledButton(
              onPressed:
                  (double.tryParse(amount.text) ?? 0) > 0 && category != null
                  ? () => Navigator.pop(
                      context,
                      Money.fromBaht(double.parse(amount.text)),
                    )
                  : null,
              child: Text(
                (double.tryParse(amount.text) ?? 0) > 0 && category != null
                    ? 'บันทึก ${_money(Money.fromBaht(double.parse(amount.text)))}'
                    : 'บันทึก',
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CategoryPicker extends StatelessWidget {
  const _CategoryPicker();
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('เลือกหมวด', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            for (final item in const [
              'อาหาร',
              'เดินทาง',
              'ใช้ส่วนตัว',
              'ครอบครัว',
            ])
              ListTile(
                minTileHeight: 52,
                title: Text(item),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.pop(context, item),
              ),
          ],
        ),
      ),
    ),
  );
}

class StatementPreviewScreen extends StatefulWidget {
  const StatementPreviewScreen({super.key});
  @override
  State<StatementPreviewScreen> createState() => _StatementPreviewScreenState();
}

class _StatementPreviewScreenState extends State<StatementPreviewScreen> {
  final rows = <_StatementUiRow>[
    _StatementUiRow(
      '25 ส.ค.',
      'เงินเดือน',
      17125,
      StatementClassification.income,
    ),
    _StatementUiRow(
      '26 ส.ค.',
      'ร้านอาหาร',
      -120,
      StatementClassification.pending,
    ),
    _StatementUiRow(
      '27 ส.ค.',
      'โอนเงิน',
      -500,
      StatementClassification.pending,
    ),
    _StatementUiRow(
      '28 ส.ค.',
      'เงินคืนร้านค้า',
      60,
      StatementClassification.pending,
    ),
  ];
  int get pending =>
      rows.where((e) => e.kind == StatementClassification.pending).length;
  Future<void> classify(_StatementUiRow row) async {
    final kind = await showModalBottomSheet<StatementClassification>(
      context: context,
      builder: (_) => _ClassificationSheet(row: row),
    );
    if (kind != null) setState(() => row.kind = kind);
  }

  @override
  Widget build(BuildContext context) {
    final difference = pending * 320;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statement Preview'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'DEMO DATA • ทุกแถวต้องผ่าน Preview ก่อนเข้า Ledger',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final row = rows[i];
                    return _StatementTile(row: row, onTap: () => classify(row));
                  },
                ),
              ),
              InkWell(
                onTap: difference == 0
                    ? null
                    : () {
                        final row = rows.firstWhere(
                          (e) => e.kind == StatementClassification.pending,
                        );
                        classify(row);
                      },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: difference == 0 ? Colors.green : AppColors.red,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Reconciliation'),
                      Text(
                        'Difference ฿$difference',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        difference == 0
                            ? 'สมดุลแล้ว พร้อม Confirm'
                            : 'มี $pending แถวต้องกลับไปตรวจ',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: difference == 0
                    ? () => showDialog<void>(
                        context: context,
                        builder: (_) => AlertDialog(
                          icon: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 52,
                          ),
                          title: const Text('Import สำเร็จ'),
                          content: const Text(
                            'บันทึกทั้งชุดแบบ Atomic แล้ว • Undo ได้',
                          ),
                          actions: [
                            FilledButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pop(context);
                              },
                              child: const Text('กลับ Dashboard'),
                            ),
                          ],
                        ),
                      )
                    : null,
                child: const Text('Confirm ทั้งชุด'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatementUiRow {
  _StatementUiRow(this.date, this.title, this.amount, this.kind);
  final String date, title;
  final int amount;
  StatementClassification kind;
}

class _StatementTile extends StatelessWidget {
  const _StatementTile({required this.row, required this.onTap});
  final _StatementUiRow row;
  final VoidCallback onTap;
  Color get color => switch (row.kind) {
    StatementClassification.pending => AppColors.orange,
    StatementClassification.refund => AppColors.blue,
    StatementClassification.transfer ||
    StatementClassification.matchExisting => AppColors.violet,
    _ => Colors.green,
  };
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(14),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: color, width: 5)),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row.date,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    row.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    row.kind == StatementClassification.pending
                        ? '! ต้องตรวจ'
                        : '✓ ${row.kind.name}',
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              '${row.amount > 0 ? '+' : ''}฿${row.amount.abs()}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ClassificationSheet extends StatelessWidget {
  const _ClassificationSheet({required this.row});
  final _StatementUiRow row;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'จัดประเภทรายการ',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              '${row.date} • ${row.title} • ฿${row.amount.abs()}',
              style: const TextStyle(color: AppColors.muted),
            ),
            const SizedBox(height: 12),
            for (final kind in const [
              StatementClassification.matchExisting,
              StatementClassification.income,
              StatementClassification.expense,
              StatementClassification.refund,
              StatementClassification.transfer,
              StatementClassification.ignore,
            ])
              ListTile(
                minTileHeight: 48,
                title: Text(kind.name),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  if (kind == StatementClassification.matchExisting) {
                    final matched = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('จับคู่ Manual Transaction'),
                        content: Text(
                          '${row.date} • ฿${row.amount.abs()}\n${row.title} • บัญชีเงินเดือน',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('ยกเลิก'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('เลือก'),
                          ),
                        ],
                      ),
                    );
                    if (matched != true || !context.mounted) return;
                  }
                  if (context.mounted) Navigator.pop(context, kind);
                },
              ),
          ],
        ),
      ),
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.note,
    required this.onTap,
    this.tone = Colors.white,
  });
  final String label, value, note;
  final VoidCallback onTap;
  final Color tone;
  @override
  Widget build(BuildContext context) => Material(
    color: tone,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 148,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const Spacer(),
            FittedBox(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$note ↗',
              style: const TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DarkCard extends StatelessWidget {
  const _DarkCard({
    required this.label,
    required this.value,
    required this.note,
  });
  final String label, value, note;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppColors.ink,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFFAEBBC0))),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 31,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(note, style: const TextStyle(color: Color(0xFFAEBBC0))),
      ],
    ),
  );
}

class _RecurringRow extends StatelessWidget {
  const _RecurringRow({required this.name, required this.amount});
  final String name;
  final int amount;
  @override
  Widget build(BuildContext context) => Card(
    color: Colors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: const BorderSide(color: AppColors.line),
    ),
    child: ListTile(
      minTileHeight: 66,
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: const Text('จำเป็น • สิ้นสุดยังไม่ทราบ'),
      trailing: Text(
        '฿$amount',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      onTap: () {},
    ),
  );
}

class _Info extends StatelessWidget {
  const _Info(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFE7EBE8),
      borderRadius: BorderRadius.circular(13),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _DataPill extends StatelessWidget {
  const _DataPill();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFF738189)),
      borderRadius: BorderRadius.circular(99),
    ),
    child: const Text(
      'LOCAL DATA • ข้อมูลจริง',
      style: TextStyle(color: Colors.white, fontSize: 10, letterSpacing: 1),
    ),
  );
}

class _SystemState extends StatelessWidget {
  const _SystemState({required this.state});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final data = switch (state.viewStatus) {
      ViewStatus.loading => (
        'กำลังคำนวณเงิน...',
        'เดี๋ยวนะ กำลังไล่นับทุกบาท',
        'กลับ',
      ),
      ViewStatus.empty => (
        'ยังไม่มีรายการ',
        'เริ่มจดรายการแรก แล้วเราจะช่วยตามเงินให้',
        'เพิ่มรายการแรก',
      ),
      ViewStatus.error => (
        'คำนวณไม่สำเร็จ',
        'ข้อมูลยังอยู่ครบ ลองใหม่ได้เลย',
        'ลองอีกครั้ง',
      ),
      _ => ('', '', ''),
    };
    return _Page(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.info_outline, size: 68),
            const SizedBox(height: 18),
            Text(data.$1, style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(data.$2, textAlign: TextAlign.center),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: () => state.setViewStatus(ViewStatus.ready),
              child: Text(data.$3),
            ),
            if (state.viewStatus == ViewStatus.error)
              OutlinedButton(
                onPressed: () => state.setViewStatus(ViewStatus.ready),
                child: const Text('ย้อนกลับ'),
              ),
          ],
        ),
      ),
    );
  }
}

void _breakdown(BuildContext context, String title, List<String> rows) =>
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(row),
                ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('เข้าใจแล้ว'),
              ),
            ],
          ),
        ),
      ),
    );
String _money(Money value) {
  final whole = value.satang ~/ 100;
  final sign = whole < 0 ? '-' : '';
  final digits = whole.abs().toString();
  final grouped = digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => ',',
  );
  return '$sign฿$grouped';
}

class _InstallmentCard extends StatelessWidget {
  const _InstallmentCard({required this.progress, required this.onSetup});
  final InstallmentProgress? progress;
  final VoidCallback onSetup;
  @override
  Widget build(BuildContext context) {
    final value = progress;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: value == null
            ? onSetup
            : () => _breakdown(context, 'Installment Progress', [
                'Paid ${_money(value.paid)}',
                'Remaining ${_money(value.remaining)}',
                if (value.overpayment.satang > 0)
                  'Overpayment ${_money(value.overpayment)} — please review',
                'Estimated remaining payments ${value.estimatedRemainingPayments ?? 'unknown'}',
              ]),
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ผ่อนโทรศัพท์',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                value == null
                    ? 'ยังไม่ได้ตั้ง Total Payable'
                    : '${((value.progressRatio ?? 0) * 100).toStringAsFixed(0)}% complete',
              ),
              if (value != null) ...[
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: (value.progressRatio ?? 0).clamp(0, 1),
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(99),
                ),
                const SizedBox(height: 8),
                Text(
                  '${_money(value.remaining)} remaining • approximately ${value.estimatedRemainingPayments ?? '-'} payments',
                ),
              ] else
                const Text('แตะเพื่อตั้งยอดสัญญาจริง โดยแอปจะไม่เดายอดให้'),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _configureInstallment(BuildContext context, AppState state) async {
  final total = TextEditingController();
  final paid = TextEditingController();
  final regular = TextEditingController(text: '1000');
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('ตั้ง Installment Progress'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: total,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Total Payable (บาท)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: paid,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'ยอดที่จ่ายก่อนเริ่มติดตาม (บาท)',
                helperText: 'ใช้คำนวณความคืบหน้า ไม่หักเงินจริง',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: regular,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Regular Payment (บาท)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('บันทึก'),
        ),
      ],
    ),
  );
  if (confirmed == true && context.mounted) {
    final totalValue = int.tryParse(total.text);
    final paidValue = int.tryParse(paid.text) ?? 0;
    final regularValue = int.tryParse(regular.text);
    if (totalValue != null &&
        totalValue > 0 &&
        regularValue != null &&
        regularValue > 0) {
      await state.configurePhoneInstallment(
        total: Money.fromBaht(totalValue),
        paid: Money.fromBaht(paidValue),
        regular: Money.fromBaht(regularValue),
      );
    }
  }
  total.dispose();
  paid.dispose();
  regular.dispose();
}

class BankNotificationSetupScreen extends StatefulWidget {
  const BankNotificationSetupScreen({super.key});
  @override
  State<BankNotificationSetupScreen> createState() =>
      _BankNotificationSetupScreenState();
}

class _BankNotificationSetupScreenState
    extends State<BankNotificationSetupScreen> {
  static const channel = MethodChannel('ngoen_ku_pai_nai/bank_notifications');
  bool enabled = false;
  bool access = false;
  Future<void> refresh() async {
    final granted =
        await channel.invokeMethod<bool>('hasNotificationAccess') ?? false;
    if (mounted) setState(() => access = granted);
  }

  @override
  void initState() {
    super.initState();
    refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Bank Notification Capture')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'EXPERIMENTAL • Android only',
          style: TextStyle(
            color: AppColors.orange,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'แอปจะตรวจเฉพาะธนาคารที่รองรับ แปลงข้อมูลในเครื่อง และสร้าง Pending event ก่อนเสมอ ไม่มีการลงรายจ่ายอัตโนมัติ',
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('เปิดฟีเจอร์ทดลอง'),
          subtitle: const Text('ปิดโดยค่าเริ่มต้น • ยกเลิกได้ทุกเมื่อ'),
          value: enabled,
          onChanged: (value) => setState(() => enabled = value),
        ),
        ListTile(
          title: const Text('Notification Access'),
          subtitle: Text(
            access
                ? 'Granted • Listening (no real bank adapter configured)'
                : 'Permission missing',
          ),
          leading: Icon(
            access ? Icons.check_circle : Icons.warning_amber,
            color: access ? Colors.green : AppColors.orange,
          ),
        ),
        FilledButton(
          onPressed: enabled
              ? () async {
                  await channel.invokeMethod<void>('openNotificationAccess');
                }
              : null,
          child: const Text('เปิด Android Notification Access'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: refresh,
          child: const Text('ตรวจสิทธิ์อีกครั้ง'),
        ),
        const SizedBox(height: 20),
        const _Info(
          'ยังไม่รองรับธนาคารจริงจนกว่าจะมี package name และตัวอย่าง Notification ที่ปิดข้อมูลส่วนตัวแล้ว Raw notification จะไม่ถูกเก็บหรือส่งออกนอกเครื่อง',
        ),
      ],
    ),
  );
}
