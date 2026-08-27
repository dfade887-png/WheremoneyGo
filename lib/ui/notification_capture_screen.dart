import 'package:flutter/material.dart';

import '../data/notification_capture_bridge.dart';
import '../domain/notification_capture.dart';
import 'app_state.dart';
import 'theme/app_theme.dart';

class NotificationCaptureScreen extends StatefulWidget {
  const NotificationCaptureScreen({
    required this.state,
    this.bridge,
    super.key,
  });
  final AppState state;
  final NotificationCaptureBridge? bridge;

  @override
  State<NotificationCaptureScreen> createState() =>
      _NotificationCaptureScreenState();
}

class _NotificationCaptureScreenState extends State<NotificationCaptureScreen>
    with WidgetsBindingObserver {
  late final bridge = widget.bridge ?? NotificationCaptureBridge();
  bool access = false;
  bool loading = true;
  List<NotificationSource> sources = const [];
  String? error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refresh();
  }

  Future<void> refresh() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repository = widget.state.financeRepository;
      final configured = await repository.notificationSources();
      final granted = await bridge.hasAccess();
      await NotificationCaptureCoordinator(
        repository,
        bridge,
        () => repository.activeProfileId,
      ).synchronizeAndDrain();
      if (mounted) {
        setState(() {
          access = granted;
          sources = configured;
        });
      }
    } catch (_) {
      if (mounted) error = 'ตรวจสถานะการแจ้งเตือนไม่สำเร็จ';
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> addLine() async {
    await widget.state.financeRepository.createNotificationSource(
      sourceKind: 'line',
      displayName: 'LINE',
      packageName: 'jp.naver.line.android',
    );
    await refresh();
  }

  Future<void> toggle(NotificationSource source, bool enabled) async {
    await widget.state.financeRepository.setNotificationSourceEnabled(
      source.id,
      enabled,
    );
    await refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('ตรวจจับจากการแจ้งเตือน')),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (error != null)
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.error_outline,
                      color: AppColors.red,
                    ),
                    title: Text(error!),
                    trailing: TextButton(
                      onPressed: refresh,
                      child: const Text('ลองใหม่'),
                    ),
                  ),
                ),
              ListTile(
                leading: Icon(
                  access ? Icons.check_circle : Icons.warning_amber_rounded,
                  color: access ? Colors.green : AppColors.orange,
                ),
                title: const Text('สิทธิ์การแจ้งเตือน'),
                subtitle: Text(
                  access
                      ? 'เปิดแล้ว'
                      : 'ยังไม่ได้เปิด\nเปิดสิทธิ์เพื่อให้แอปตรวจจับรายการจากแหล่งที่เลือก',
                ),
              ),
              FilledButton(
                onPressed: bridge.openAccessSettings,
                child: const Text('เปิดการตั้งค่า'),
              ),
              const SizedBox(height: 20),
              Text(
                'แหล่งที่ตรวจจับ',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              for (final source in sources)
                SwitchListTile(
                  title: Text(source.displayName),
                  subtitle: Text(source.enabled ? 'เปิด' : 'ปิด'),
                  value: source.enabled,
                  onChanged: (value) => toggle(source, value),
                ),
              if (!sources.any((source) => source.sourceKind == 'line'))
                OutlinedButton.icon(
                  onPressed: addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่ม LINE เป็นแหล่งข้อมูล'),
                ),
              const SizedBox(height: 20),
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'เก็บเฉพาะการแจ้งเตือนจากแอปที่เปิดไว้ ข้อมูลอยู่ในเครื่อง ไม่สร้างรายรับ–รายจ่าย และไม่แสดงเนื้อหาข้อความในหน้านี้',
                  ),
                ),
              ),
            ],
          ),
  );
}
