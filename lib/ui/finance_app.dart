import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/money.dart';
import '../domain/models/financial_models.dart';
import '../domain/payday_calendar.dart';
import '../domain/financial_calendar.dart';
import '../domain/spending_gauge.dart';
import '../domain/spending_gauge_ranking.dart';
import 'app_state.dart';
import 'theme/app_theme.dart';
import 'daily_driver_screen.dart';
import 'finance_components.dart';
import 'local_finance_store.dart';
import 'production_shell.dart';

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
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: state,
    builder: (context, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'เงินกูไปไหน',
      theme: AppTheme.lightFor(state.appAccent),
      darkTheme: AppTheme.darkFor(state.appAccent),
      themeMode: state.appearanceMode,
      home: _AppRouter(state: state),
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
      AppStep.dashboard => ProductionShell(
        state: state,
        initialIndex: state.notificationLaunchCandidateId == null ? 0 : 3,
      ),
      AppStep.calendar => ProductionShell(state: state, initialIndex: 1),
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
    final policy = switch (widget.state.holidayRule) {
      'after' => PaydayHolidayPolicy.after,
      'same' => PaydayHolidayPolicy.exact,
      _ => PaydayHolidayPolicy.before,
    };
    final now = DateTime.now();
    final preview = day == null || day < 1 || day > 31
        ? null
        : PaydayCalendar.resolve(
            year: now.year,
            month: now.month + 1,
            payday: day,
            policy: policy,
          );
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
        _Info(
          preview == null
              ? 'กรอกวันที่ 1–31 เพื่อคำนวณรอบเงินเดือน'
              : 'รอบถัดไปเริ่ม ${preview.day}/${preview.month}/${preview.year} • เดือนที่ไม่มีวันที่นี้จะใช้วันสุดท้ายของเดือน',
        ),
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
  const DashboardScreen({
    required this.state,
    this.embedded = false,
    this.onNavigate,
    super.key,
  });
  final AppState state;
  final bool embedded;
  final ValueChanged<int>? onNavigate;
  @override
  Widget build(BuildContext context) {
    final data = state.snapshot;
    final projection = state.projectionSnapshot;
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: SafeArea(
        child: ListView(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.ink,
                    Color.lerp(AppColors.ink, accent, .45)!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(30),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _DataPill(),
                        ),
                      ),
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
                  const SizedBox(height: 12),
                  const Text(
                    'เงินจริงที่มี',
                    style: TextStyle(
                      color: Color(0xFFAAB8BD),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  FinanceAmountText(
                    satang: data.currentCash.satang,
                    color: Colors.white,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'ใช้ได้วันนี้ ${_money(data.dailyAllowance)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'อีก ${projection?.daysRemaining ?? 1} วันถึงรอบเงินเดือน',
                        style: const TextStyle(color: Color(0xFFAAB8BD)),
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
                  _CompactSpendingSummary(
                    state: state,
                    onOpenAll: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SpendingStatusScreen(state: state),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _UpcomingPanel(
                    events: state.dashboardUpcoming,
                    onOpen: () {
                      if (onNavigate != null) {
                        onNavigate!(1);
                      } else {
                        state.go(AppStep.calendar);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  _RecentActivity(
                    rows: state.activities.take(3).toList(growable: false),
                    onOpen: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DailyDriverScreen(state: state),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    key: const Key('dashboard-quick-add'),
                    onPressed: () async {
                      await showModalBottomSheet<void>(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        builder: (_) => DailyQuickAdd(state: state),
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มรายการ'),
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

class _CompactSpendingSummary extends StatelessWidget {
  const _CompactSpendingSummary({required this.state, required this.onOpenAll});
  final AppState state;
  final VoidCallback onOpenAll;

  @override
  Widget build(BuildContext context) {
    final gauges = rankHomeSpendingGauges(state.spendingGauges);
    return Card(
      key: const Key('dashboard-budget-summary'),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'สถานะงบเดือนนี้',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: onOpenAll,
                  child: const Text('ดูทั้งหมด'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (gauges.isEmpty)
              _CompactEmptyBudget(onOpenAll: onOpenAll)
            else
              for (final gauge in gauges) ...[
                KeyedSubtree(
                  key: Key('dashboard-gauge-${gauge.categoryId}'),
                  child: _GaugeRow(
                    gauge: gauge,
                    onSetBudget: onOpenAll,
                    showAction: false,
                  ),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class SpendingStatusScreen extends StatelessWidget {
  const SpendingStatusScreen({required this.state, super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final gauges = _allExpenseGauges(state);
    return Scaffold(
      appBar: AppBar(title: const Text('สถานะงบเดือนนี้')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'งบเป็นแผนการใช้เงิน ไม่เปลี่ยนเงินจริงในบัญชี',
            style: TextStyle(color: AppColors.muted),
          ),
          const SizedBox(height: 12),
          if (gauges.isEmpty)
            const Text('ยังไม่มีหมวดรายจ่ายให้ตั้งงบ')
          else
            for (final gauge in gauges) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: _GaugeRow(
                    gauge: gauge,
                    onSetBudget: () =>
                        _editCategoryBudget(context, state, gauge),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _CompactEmptyBudget extends StatelessWidget {
  const _CompactEmptyBudget({required this.onOpenAll});
  final VoidCallback onOpenAll;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      const Expanded(
        child: Text(
          'ยังไม่ได้ตั้งงบรายหมวด',
          style: TextStyle(color: AppColors.muted),
        ),
      ),
      TextButton(onPressed: onOpenAll, child: const Text('ตั้งงบ')),
    ],
  );
}

List<SpendingGauge> _allExpenseGauges(AppState state) {
  final recorded = {
    for (final gauge in state.spendingGauges) gauge.categoryId: gauge,
  };
  final gauges = state.categories
      .where(
        (category) =>
            category['category_type'] == 'expense' &&
            category['is_archived'] != 1,
      )
      .map((category) {
        final id = category['id'] as String;
        return recorded[id] ??
            SpendingGauge(
              categoryId: id,
              name: category['name'] as String,
              iconKey: category['icon_key'] as String?,
              usedSatang: 0,
              budgetSatang: 0,
            );
      })
      .toList();
  return rankHomeSpendingGauges(gauges, limit: gauges.length) +
      (gauges.where((gauge) => !gauge.hasBudget).toList()
        ..sort((left, right) => left.name.compareTo(right.name)));
}

Future<void> _editCategoryBudget(
  BuildContext context,
  AppState state,
  SpendingGauge gauge,
) async {
  final controller = TextEditingController(
    text: gauge.hasBudget ? (gauge.budgetSatang / 100).toStringAsFixed(0) : '',
  );
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('ตั้งงบ ${gauge.name} ต่อเดือน'),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(
          labelText: 'จำนวนเงิน',
          prefixText: '฿',
        ),
      ),
      actions: [
        if (gauge.hasBudget)
          TextButton(
            onPressed: () => Navigator.pop(context, 'remove'),
            child: const Text('ลบงบ'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('บันทึก'),
        ),
      ],
    ),
  );
  if (result == null) return;
  if (result == 'remove') {
    await state.removeCategoryMonthlyBudget(gauge.categoryId);
    return;
  }
  final amount = double.tryParse(result.replaceAll(',', ''));
  if (amount == null || amount <= 0) return;
  await state.setCategoryMonthlyBudget(
    gauge.categoryId,
    (amount * 100).round(),
  );
}

class _GaugeRow extends StatelessWidget {
  const _GaugeRow({
    required this.gauge,
    required this.onSetBudget,
    this.showAction = true,
  });
  final SpendingGauge gauge;
  final VoidCallback onSetBudget;
  final bool showAction;
  @override
  Widget build(BuildContext context) {
    final ratio = gauge.usageRatio;
    final color = switch (gauge.state) {
      SpendingGaugeState.safe => FinancialColors.safe,
      SpendingGaugeState.warning => FinancialColors.warning,
      SpendingGaugeState.critical => FinancialColors.critical,
      SpendingGaugeState.over => FinancialColors.overBudget,
      SpendingGaugeState.unbudgeted => AppColors.muted,
    };
    final categoryColor = CategoryAccentPalette.resolve(
      stableKey: gauge.categoryId,
      storedValue: gauge.colorValue,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: categoryColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                gauge.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            if (showAction)
              TextButton(
                onPressed: onSetBudget,
                child: Text(gauge.hasBudget ? 'แก้งบ' : 'ตั้งงบ'),
              ),
          ],
        ),
        if (ratio != null)
          LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            color: color,
            backgroundColor: AppColors.line,
          ),
        const SizedBox(height: 4),
        Text(
          gauge.hasBudget
              ? '${_money(Money.fromSatang(gauge.usedSatang))} / ${_money(Money.fromSatang(gauge.budgetSatang))} • ${gauge.usagePercent}%'
              : 'ใช้ไป ${_money(Money.fromSatang(gauge.usedSatang))} • ยังไม่ได้ตั้งงบ',
        ),
        if (gauge.hasBudget)
          Text(
            gauge.overBudgetSatang > 0
                ? 'เกินงบ ${_money(Money.fromSatang(gauge.overBudgetSatang))}'
                : 'เหลือ ${_money(Money.fromSatang(gauge.remainingSatang))}',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
      ],
    );
  }
}

// Kept for a later account-detail drill-down; UI-R5 removes it from Home.
// ignore: unused_element
class _AccountDistribution extends StatelessWidget {
  const _AccountDistribution({required this.accounts, required this.onOpen});
  final List<Map<String, Object?>> accounts;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final active = accounts.where((row) => row['is_active'] == 1).take(4);
    return Container(
      key: const Key('dashboard-account-distribution'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'เงินอยู่ที่ไหน',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              TextButton(
                onPressed: onOpen,
                child: const Text('ดูบัญชีทั้งหมด'),
              ),
            ],
          ),
          if (active.isEmpty)
            const Text(
              'ยังไม่มีบัญชี',
              style: TextStyle(color: AppColors.muted),
            )
          else
            for (final account in active)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Icon(
                      account['account_type'] == 'cash'
                          ? Icons.payments_outlined
                          : Icons.account_balance_outlined,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        account['name'] as String,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: FinanceAmountText(
                        satang: account['balance_satang'] as int,
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _UpcomingPanel extends StatelessWidget {
  const _UpcomingPanel({required this.events, required this.onOpen});
  final List<FinancialCalendarEvent> events;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => Container(
    key: const Key('dashboard-upcoming'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'กำลังจะถึง',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            TextButton(onPressed: onOpen, child: const Text('ปฏิทิน')),
          ],
        ),
        if (events.isEmpty)
          const Text(
            'ยังไม่มีรายการที่กำลังจะถึง',
            style: TextStyle(color: AppColors.muted),
          )
        else
          for (final event in events)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                child: Text('${event.dateTime.toLocal().day}'),
              ),
              title: Text(
                event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                event.displayStatus == FinancialCalendarDisplayStatus.due
                    ? 'ถึงกำหนด • ต้องตรวจ'
                    : 'รายการล่วงหน้า',
              ),
              trailing: SizedBox(
                width: 125,
                child: FinanceAmountText(
                  satang: event.direction == FinancialCalendarDirection.outgoing
                      ? -event.amountSatang
                      : event.amountSatang,
                  signed:
                      event.direction != FinancialCalendarDirection.transfer,
                  textAlign: TextAlign.end,
                  color: event.direction == FinancialCalendarDirection.outgoing
                      ? FinancialColors.expense
                      : event.direction == FinancialCalendarDirection.transfer
                      ? FinancialColors.transfer
                      : FinancialColors.income,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
      ],
    ),
  );
}

// Candidate review remains a primary navigation destination, not Home content.
// ignore: unused_element
class _CandidateSignal extends StatelessWidget {
  const _CandidateSignal({required this.count, required this.onOpen});
  final int count;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFE8F3),
    borderRadius: BorderRadius.circular(18),
    child: ListTile(
      key: const Key('dashboard-candidate-signal'),
      onTap: onOpen,
      leading: const Icon(Icons.fact_check_outlined, color: AppColors.violet),
      title: Text(
        'มี $count รายการรอตรวจ',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      subtitle: const Text('ตรวจให้ชัวร์ก่อนเงินจะเข้า Ledger'),
      trailing: const Icon(Icons.chevron_right),
    ),
  );
}

class _RecentActivity extends StatelessWidget {
  const _RecentActivity({required this.rows, required this.onOpen});
  final List<Map<String, Object?>> rows;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Container(
    key: const Key('dashboard-recent-activity'),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'ล่าสุด',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            TextButton(onPressed: onOpen, child: const Text('ดูรายการทั้งหมด')),
          ],
        ),
        if (rows.isEmpty)
          const Text(
            'ยังไม่มีรายการล่าสุด',
            style: TextStyle(color: AppColors.muted),
          )
        else
          for (final row in rows)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(_activityIcon(row['type'] as String)),
              title: Text(
                (row['category_name'] as String?) ??
                    _activityLabel(row['type'] as String),
              ),
              subtitle: Text(
                row['account_name'] as String? ?? 'บัญชีไม่ทราบชื่อ',
              ),
              trailing: SizedBox(
                width: 125,
                child: FinanceAmountText(
                  satang: _activitySigned(row),
                  signed: !_isTransfer(row['type'] as String),
                  textAlign: TextAlign.end,
                  color: _activityColor(row),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
      ],
    ),
  );
}

bool _isTransfer(String type) =>
    type == 'transfer_in' || type == 'transfer_out';
Color? _activityColor(Map<String, Object?> row) {
  final type = row['type'] as String;
  if (_isTransfer(type)) return FinancialColors.transfer;
  if (type == 'refund') return FinancialColors.refund;
  return _activitySigned(row) < 0 ? FinancialColors.expense : FinancialColors.income;
}
int _activitySigned(Map<String, Object?> row) {
  final type = row['type'] as String;
  final amount = row['amount_satang'] as int;
  if (_isTransfer(type)) return amount;
  return type == 'income' || type == 'refund' ? amount : -amount;
}

String _activityLabel(String type) => switch (type) {
  'income' => 'รายรับ',
  'expense' => 'รายจ่าย',
  'refund' => 'เงินคืน',
  'transfer_in' || 'transfer_out' => 'โอนระหว่างบัญชี',
  _ => 'ปรับยอดบัญชี',
};
IconData _activityIcon(String type) => switch (type) {
  'income' => Icons.south_west_rounded,
  'expense' => Icons.north_east_rounded,
  'refund' => Icons.replay_rounded,
  'transfer_in' || 'transfer_out' => Icons.swap_horiz_rounded,
  _ => Icons.tune_rounded,
};

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

// Reused by a future analytics drill-down; intentionally not part of Home.
// ignore: unused_element
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.note,
    required this.onTap,
    // ignore: unused_element_parameter
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
        constraints: const BoxConstraints(minHeight: 148),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 18),
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
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
String _money(Money value) => FinanceMoneyFormat.money(value);

// Installment details remain available through their dedicated flow.
// ignore: unused_element
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
            : () => _breakdown(context, 'ความคืบหน้าการผ่อน', [
                'จ่ายแล้ว ${_money(value.paid)}',
                'คงเหลือ ${_money(value.remaining)}',
                if (value.overpayment.satang > 0)
                  'จ่ายเกิน ${_money(value.overpayment)} — กรุณาตรวจสอบ',
                'คาดว่าเหลือ ${value.estimatedRemainingPayments ?? 'ไม่ทราบ'} งวด',
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
                    ? 'ยังไม่ได้ตั้งยอดที่ต้องจ่ายทั้งหมด'
                    : 'จ่ายแล้ว ${((value.progressRatio ?? 0) * 100).toStringAsFixed(0)}%',
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
                  'คงเหลือ ${_money(value.remaining)} • ประมาณ ${value.estimatedRemainingPayments ?? '-'} งวด',
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

// ignore: unused_element
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
