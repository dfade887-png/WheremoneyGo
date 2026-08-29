import 'package:flutter/material.dart';

import 'app_state.dart';
import 'candidate_inbox_screen.dart';
import 'daily_driver_screen.dart';
import 'finance_app.dart';
import 'financial_calendar_screen.dart';
import 'notification_capture_screen.dart';
import 'notification_rule_builder_screen.dart';
import 'theme/app_theme.dart';

class ProductionShell extends StatefulWidget {
  const ProductionShell({
    required this.state,
    this.initialIndex = 0,
    super.key,
  });
  final AppState state;
  final int initialIndex;

  @override
  State<ProductionShell> createState() => _ProductionShellState();
}

class _ProductionShellState extends State<ProductionShell> {
  late int index = widget.initialIndex;

  void select(int value) {
    if (value == 2) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DailyQuickAdd(state: widget.state),
      );
      return;
    }
    setState(() => index = value);
  }

  @override
  Widget build(BuildContext context) {
    final page = switch (index) {
      1 => FinancialCalendarScreen(state: widget.state, embedded: true),
      3 => CandidateInboxScreen(state: widget.state, embedded: true),
      4 => _MoreScreen(state: widget.state),
      _ => DashboardScreen(
        state: widget.state,
        embedded: true,
        onNavigate: select,
      ),
    };
    return Scaffold(
      body: page,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.space_dashboard_outlined),
            selectedIcon: Icon(Icons.space_dashboard),
            label: 'หน้าหลัก',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'ปฏิทิน',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline, size: 32),
            selectedIcon: Icon(Icons.add_circle, size: 34),
            label: 'เพิ่ม',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'รอตรวจ',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            label: 'เพิ่มเติม',
          ),
        ],
      ),
    );
  }
}

class _MoreScreen extends StatelessWidget {
  const _MoreScreen({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('เพิ่มเติม')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'จัดการเงิน',
          style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: const Text('บัญชี รายการ และหมวดหมู่'),
          subtitle: const Text('ดูเงินจริง แก้บัญชี และประวัติทั้งหมด'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => DailyDriverScreen(state: state)),
          ),
        ),
        const Divider(),
        const Text(
          'การตรวจจับรายการ',
          style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        ListTile(
          leading: const Icon(Icons.notifications_active_outlined),
          title: const Text('LINE และการอนุญาตแจ้งเตือน'),
          subtitle: const Text('เปิดใช้งานและดูรายการที่จับได้ล่าสุด'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationCaptureScreen(state: state),
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.rule_outlined),
          title: const Text('กฎการตรวจจับ'),
          subtitle: const Text('กำหนดว่าข้อความแบบไหนเป็นรายรับหรือรายจ่าย'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NotificationRuleBuilderScreen(state: state),
            ),
          ),
        ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.file_download_outlined),
          title: const Text('นำเข้า Statement'),
          subtitle: const Text('ตรวจ Preview ก่อนบันทึกทุกครั้ง'),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const StatementPreviewScreen()),
          ),
        ),
      ],
    ),
  );
}
