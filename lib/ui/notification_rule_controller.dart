import 'package:flutter/foundation.dart';

import '../data/repositories/sqlite_finance_repository.dart';
import '../domain/notification_capture.dart';
import '../domain/notification_rule_parser.dart';

final class NotificationRuleController extends ChangeNotifier {
  NotificationRuleController(this.repository);
  final SqliteFinanceRepository repository;

  List<NotificationSource> sources = const [];
  List<NotificationRule> rules = const [];
  List<RawNotificationSample> samples = const [];
  NotificationSource? selectedSource;
  RawNotificationSample? selectedSample;
  RulePreviewResult? preview;
  NotificationReprocessSummary? reprocessSummary;
  bool loading = false, saving = false, reprocessing = false;
  String? error;

  Future<void> load({String? sourceId}) async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      sources = (await repository.notificationSources())
          .where((source) => source.enabled)
          .toList(growable: false);
      if (sources.isEmpty) {
        selectedSource = null;
        rules = const [];
        samples = const [];
        return;
      }
      selectedSource = sources.firstWhere(
        (source) => source.id == (sourceId ?? selectedSource?.id),
        orElse: () => sources.first,
      );
      await _loadSelected();
    } catch (_) {
      error = 'โหลดกฎการตรวจจับไม่สำเร็จ';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectSource(String id) async {
    selectedSource = sources.firstWhere((source) => source.id == id);
    selectedSample = null;
    preview = null;
    reprocessSummary = null;
    loading = true;
    notifyListeners();
    try {
      await _loadSelected();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadSelected() async {
    final source = selectedSource!;
    rules = await repository.notificationRules(source.id);
    samples = await repository.recentRawNotificationSamples(source.id);
  }

  void selectSample(RawNotificationSample? sample) {
    selectedSample = sample;
    preview = null;
    notifyListeners();
  }

  Future<RulePreviewResult?> previewRule(NotificationRule rule) async {
    final sample = selectedSample;
    if (sample == null || selectedSource == null) {
      error = 'กรุณาเลือกการแจ้งเตือนตัวอย่าง';
      notifyListeners();
      return null;
    }
    error = null;
    preview = await repository.previewNotificationRule(
      rule,
      NotificationRuleSample(
        packageName: selectedSource!.packageName,
        capturedAt: sample.capturedAt,
        title: sample.title,
        body: sample.body,
        senderOrChat: sample.senderOrChat,
      ),
    );
    notifyListeners();
    return preview;
  }

  Future<bool> saveRule(NotificationRule rule, {required bool isNew}) async {
    saving = true;
    error = null;
    notifyListeners();
    try {
      if (isNew) {
        final id = await repository.createNotificationRule(
          notificationSourceId: rule.notificationSourceId,
          name: rule.name,
          bodyPattern: rule.bodyPattern,
          parserKind: rule.parserKind,
          directionRule: rule.directionRule,
          senderOrChatPattern: rule.senderOrChatPattern,
          titlePattern: rule.titlePattern,
          accountId: rule.accountId,
          categoryId: rule.categoryId,
          priority: rule.priority,
        );
        if (!rule.enabled) {
          await repository.setNotificationRuleEnabled(id, false);
        }
      } else {
        await repository.updateNotificationRule(rule);
      }
      await _loadSelected();
      return true;
    } catch (exception) {
      error = _friendly(exception);
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<void> toggle(NotificationRule rule, bool enabled) async {
    try {
      await repository.setNotificationRuleEnabled(rule.id, enabled);
      await _loadSelected();
    } catch (exception) {
      error = _friendly(exception);
    }
    notifyListeners();
  }

  Future<void> reprocess() async {
    final source = selectedSource;
    if (source == null || reprocessing) return;
    reprocessing = true;
    error = null;
    notifyListeners();
    try {
      reprocessSummary = await repository.reprocessRawNotifications(source.id);
      await _loadSelected();
    } catch (exception) {
      error = _friendly(exception);
    } finally {
      reprocessing = false;
      notifyListeners();
    }
  }

  static String _friendly(Object exception) {
    final text = exception.toString();
    if (text.contains('Rule name')) return 'กรุณาตั้งชื่อกฎ';
    if (text.contains('Body pattern')) return 'กรุณาระบุรูปแบบข้อความ';
    if (text.contains('{amount}')) return 'รูปแบบข้อความต้องมี {amount}';
    if (text.contains('regular expression')) return 'รูปแบบ Regex ไม่ถูกต้อง';
    if (text.contains('account')) return 'กรุณาเลือกบัญชีที่ใช้งานได้';
    if (text.contains('category')) return 'หมวดหมู่ไม่ตรงกับประเภทรายการ';
    return 'ดำเนินการไม่สำเร็จ กรุณาตรวจข้อมูลอีกครั้ง';
  }
}
