import 'package:flutter/material.dart';

import '../data/notification_capture_bridge.dart';
import '../domain/notification_capture.dart';
import 'app_state.dart';
import 'notification_rule_builder_screen.dart';
import 'slip_media_inbox_screen.dart';
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
  static const _supportedSources = <_SupportedNotificationSource>[
    _SupportedNotificationSource(
      displayName: 'SCB EASY',
      sourceKind: 'bank_app',
      packageName: 'com.scb.phone',
    ),
    _SupportedNotificationSource(
      displayName: 'TrueMoney',
      sourceKind: 'bank_app',
      packageName: 'th.co.truemoney.wallet',
    ),
    _SupportedNotificationSource(
      displayName: 'Google Wallet',
      sourceKind: 'other_android',
      packageName: 'com.google.android.apps.walletnfcrel',
    ),
  ];

  late final NotificationCaptureBridge _bridge;
  bool _hasListenerAccess = false;
  bool _hasAppNotificationPermission = false;
  bool _slipDetectionEnabled = false;
  String _slipPermissionState = 'denied';
  bool _loading = true;
  bool _refreshInProgress = false;
  List<NotificationSource> _configuredSources = const [];
  List<_SupportedNotificationSource> _installedSources = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _bridge = widget.bridge ?? NotificationCaptureBridge();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshInProgress) return;
    _refreshInProgress = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = widget.state.financeRepository;
      final configured = await repository.notificationSources();
      // Source rows are local data and should remain visible even if a native
      // permission/package probe is unavailable or temporarily fails.
      if (mounted) {
        setState(() => _configuredSources = configured);
      }
      final results = await Future.wait<Object?>([
        _bridge.hasAccess(),
        _bridge.hasPostNotificationsPermission(),
        repository.slipDetectionEnabled(),
        _bridge.slipImagePermissionState(),
        ..._supportedSources.map(_checkInstalled),
      ]);
      if (!mounted) return;
      setState(() {
        _configuredSources = configured;
        _hasListenerAccess = results[0] as bool;
        _hasAppNotificationPermission = results[1] as bool;
        _slipDetectionEnabled = results[2] as bool;
        _slipPermissionState = results[3] as String;
        _installedSources = results
            .skip(4)
            .whereType<_SupportedNotificationSource>()
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'ตรวจสถานะการแจ้งเตือนไม่สำเร็จ';
        });
      }
    } finally {
      _refreshInProgress = false;
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<_SupportedNotificationSource?> _checkInstalled(
    _SupportedNotificationSource source,
  ) async {
    final installed = await _bridge
        .isPackageInstalled(source.packageName)
        .timeout(const Duration(seconds: 2), onTimeout: () => false);
    return installed ? source : null;
  }

  Future<void> _addLine() => _addSource(
    const _SupportedNotificationSource(
      displayName: 'LINE',
      sourceKind: 'line',
      packageName: 'jp.naver.line.android',
    ),
  );

  Future<void> _addSource(_SupportedNotificationSource source) async {
    try {
      await widget.state.financeRepository.createNotificationSource(
        sourceKind: source.sourceKind,
        displayName: source.displayName,
        packageName: source.packageName,
      );
      widget.state.requestNotificationCaptureSync();
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'เพิ่มแหล่งแจ้งเตือนไม่สำเร็จ';
        });
      }
    }
  }

  Future<void> _toggle(NotificationSource source, bool enabled) async {
    try {
      await widget.state.financeRepository.setNotificationSourceEnabled(
        source.id,
        enabled,
      );
      widget.state.requestNotificationCaptureSync();
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'เปลี่ยนสถานะแหล่งแจ้งเตือนไม่สำเร็จ';
        });
      }
    }
  }

  Future<void> _toggleSlipDetection(bool enabled) async {
    if (!enabled) {
      await widget.state.setSlipDetectionEnabled(false);
      await _refresh();
      return;
    }
    var permission = await _bridge.slipImagePermissionState();
    if (permission == 'denied') {
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('อนุญาตเข้าถึงรูปภาพ?'),
          content: const Text(
            'แอปจะตรวจเฉพาะรูปใหม่เพื่อเตรียมรายการรอตรวจ ประมวลผลในเครื่อง ไม่อัปโหลดรูป และไม่สร้างธุรกรรมอัตโนมัติ',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('อนุญาต'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
      await _bridge.requestSlipImagePermission();
      permission = await _bridge.slipImagePermissionState();
    }
    if (permission != 'granted' && permission != 'limited') {
      if (mounted) {
        setState(() => _error = 'ยังไม่ได้รับสิทธิ์เข้าถึงรูปภาพ');
      }
      return;
    }
    await widget.state.setSlipDetectionEnabled(true);
    await _refresh();
  }

  bool _isConfigured(String packageName) =>
      _configuredSources.any((source) => source.packageName == packageName);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ตรวจจับจากการแจ้งเตือน')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: AppColors.red),
                title: Text(_error!),
                trailing: TextButton(
                  onPressed: _refresh,
                  child: const Text('ลองใหม่'),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
          _PermissionTile(
            title: 'สิทธิ์การแจ้งเตือน',
            enabled: _hasListenerAccess,
            enabledText: 'เปิดแล้ว',
            disabledText: 'ยังไม่ได้เปิด',
            actionLabel: 'เปิดการตั้งค่า',
            onPressed: () => _bridge.openAccessSettings(),
          ),
          const SizedBox(height: 12),
          _PermissionTile(
            title: 'แจ้งเตือนจากเงินกูไปไหน',
            enabled: _hasAppNotificationPermission,
            enabledText: 'อนุญาตแล้ว',
            disabledText: 'ยังไม่ได้อนุญาต',
            actionLabel: _hasAppNotificationPermission
                ? 'ตั้งค่าแจ้งเตือน'
                : 'อนุญาตการแจ้งเตือน',
            onPressed: _hasAppNotificationPermission
                ? () => _bridge.openAppNotificationSettings()
                : () => _bridge.requestPostNotifications(),
          ),
          const SizedBox(height: 24),
          Card(
            child: SwitchListTile(
              title: const Text('ตรวจจับสลิปจากรูปใหม่'),
              subtitle: Text(
                _slipDetectionEnabled
                    ? 'เปิดอยู่ • ${_slipPermissionLabel(_slipPermissionState)}'
                    : 'ปิดอยู่ • ตรวจเฉพาะรูปที่เพิ่มหลังเปิดฟีเจอร์',
              ),
              value: _slipDetectionEnabled,
              onChanged: _toggleSlipDetection,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _slipDetectionEnabled ? _scanSlipNow : null,
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('สแกนสลิปใหม่ตอนนี้'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _slipDetectionEnabled ? _addSlipFromDevice : null,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('เลือกสลิปจากเครื่อง'),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => SlipMediaInboxScreen(state: widget.state),
              ),
            ),
            icon: const Icon(Icons.fact_check_outlined),
            label: const Text('เปิดรายการสลิปรอตรวจ'),
          ),
          const SizedBox(height: 24),
          Text(
            'แหล่งที่ตรวจจับ',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            'เปิดเฉพาะแอปที่ต้องการ ข้อมูลจะผ่านหน้าให้ตรวจสอบก่อนเสมอ',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          for (final source in _configuredSources)
            Card(
              child: SwitchListTile(
                title: Text(source.displayName),
                subtitle: Text(source.enabled ? 'กำลังตรวจจับ' : 'ปิดอยู่'),
                value: source.enabled,
                onChanged: (enabled) => _toggle(source, enabled),
              ),
            ),
          for (final source in _installedSources)
            if (!_isConfigured(source.packageName))
              Card(
                child: ListTile(
                  title: Text(source.displayName),
                  subtitle: const Text('พบแอปแล้ว — ยังไม่ได้เปิดตรวจจับ'),
                  trailing: OutlinedButton(
                    onPressed: () => _addSource(source),
                    child: const Text('เพิ่ม'),
                  ),
                ),
              ),
          if (!_configuredSources.any((source) => source.sourceKind == 'line'))
            OutlinedButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่ม LINE เป็นแหล่งข้อมูล'),
            ),
          if (!_loading &&
              _configuredSources.isEmpty &&
              _installedSources.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('ยังไม่พบแอปที่รองรับในเครื่องนี้'),
              ),
            ),
          if (_configuredSources.any((source) => source.enabled)) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const Key('open-rule-builder'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      NotificationRuleBuilderScreen(state: widget.state),
                ),
              ),
              icon: const Icon(Icons.rule_outlined),
              label: const Text('กฎการตรวจจับ'),
            ),
          ],
          const SizedBox(height: 20),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'เก็บเฉพาะการแจ้งเตือนจากแอปที่เปิดไว้ ข้อมูลอยู่ในเครื่อง และจะไม่สร้างรายรับ–รายจ่ายอัตโนมัติ',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _scanSlipNow() async {
    final count = await widget.state.scanSlipMediaNow();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('พบรูปใหม่ $count รายการ — ยังไม่บันทึกเป็นรายจ่าย'),
      ),
    );
  }

  Future<void> _addSlipFromDevice() async {
    final count = await widget.state.addSlipFromDevice();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 1
              ? 'เพิ่มสลิปเข้าคิวตรวจแล้ว — ยังไม่บันทึกเป็นรายจ่าย'
              : 'ยังไม่ได้เลือกสลิป',
        ),
      ),
    );
  }

  String _slipPermissionLabel(String state) => switch (state) {
    'granted' => 'เข้าถึงรูปได้',
    'limited' => 'เข้าถึงเฉพาะรูปที่เลือก',
    'unsupported' => 'ไม่รองรับบนเครื่องนี้',
    _ => 'ต้องอนุญาตเข้าถึงรูป',
  };
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.title,
    required this.enabled,
    required this.enabledText,
    required this.disabledText,
    required this.actionLabel,
    required this.onPressed,
  });

  final String title;
  final bool enabled;
  final String enabledText;
  final String disabledText;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              leading: Icon(
                enabled ? Icons.check_circle : Icons.warning_amber_rounded,
                color: enabled ? Colors.green : AppColors.orange,
              ),
              title: Text(title),
              subtitle: Text(enabled ? enabledText : disabledText),
            ),
            FilledButton.tonal(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

final class _SupportedNotificationSource {
  const _SupportedNotificationSource({
    required this.displayName,
    required this.sourceKind,
    required this.packageName,
  });

  final String displayName;
  final String sourceKind;
  final String packageName;
}
