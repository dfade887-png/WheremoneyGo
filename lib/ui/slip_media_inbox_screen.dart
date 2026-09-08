import 'package:flutter/material.dart';

import '../data/notification_capture_bridge.dart';
import '../domain/slip_media.dart';
import '../domain/slip_parser.dart';
import 'app_state.dart';

/// Explicit, user-driven slip OCR. OCR text only exists while this page runs.
class SlipMediaInboxScreen extends StatefulWidget {
  const SlipMediaInboxScreen({required this.state, super.key});
  final AppState state;

  @override
  State<SlipMediaInboxScreen> createState() => _SlipMediaInboxScreenState();
}

class _SlipMediaInboxScreenState extends State<SlipMediaInboxScreen> {
  final _ocr = NotificationCaptureBridge();
  final _parsers = const SlipParserRegistry([SyntheticStructuredSlipParser()]);
  List<SlipMediaEvent> _events = const [];
  final Map<String, SlipParseRecord?> _records = {};
  String? _busy;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final events = await widget.state.financeRepository.slipMediaEvents();
    final records = <String, SlipParseRecord?>{};
    for (final event in events) {
      records[event.id] = await widget.state.financeRepository.slipParseRecord(
        event.id,
      );
    }
    if (mounted) {
      setState(() {
        _events = events;
        _records
          ..clear()
          ..addAll(records);
      });
    }
  }

  Future<void> _analyze(SlipMediaEvent event) async {
    setState(() => _busy = event.id);
    final ocr = await _ocr.recognizeSlipText(event.contentUri);
    if (!ocr.succeeded) {
      await widget.state.financeRepository.markSlipParseFailed(
        event.id,
        ocr.failureCode!,
      );
    } else {
      await widget.state.financeRepository.saveSlipParseResult(
        event.id,
        _parsers.parse(ocr),
      );
    }
    if (mounted) {
      await _reload();
      if (!mounted) return;
      setState(() => _busy = null);
    }
  }

  Future<void> _createCandidate(SlipMediaEvent event) async {
    setState(() => _busy = event.id);
    final candidate = await widget.state.financeRepository
        .createCandidateFromSlip(event.id);
    if (mounted) {
      await _reload();
      if (!mounted) return;
      setState(() => _busy = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            candidate == null
                ? 'ยังสร้างรายการรอตรวจไม่ได้'
                : 'สร้างรายการรอตรวจแล้ว',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('สลิปรอตรวจ')),
    body: _events.isEmpty
        ? const Center(child: Text('ยังไม่มีรูปสลิปรอตรวจ'))
        : RefreshIndicator(
            onRefresh: _reload,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _events.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _tile(_events[index]),
            ),
          ),
  );

  Widget _tile(SlipMediaEvent event) {
    final record = _records[event.id];
    final result = record?.result;
    final busy = _busy == event.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'รูปจาก ${event.ingestionSource == 'manual' ? 'เลือกเอง' : 'รูปใหม่'}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('พบเมื่อ ${event.discoveredAt.toLocal()} • ${event.status}'),
            if (result != null) ...[
              const Divider(),
              Text(
                result.isFinancialSlip
                    ? 'พบข้อมูลการเงิน'
                    : 'ยังไม่ใช่รูปแบบสลิปที่รองรับ',
              ),
              if (result.amountSatang != null)
                Text(
                  'จำนวน: ฿${(result.amountSatang! / 100).toStringAsFixed(2)}',
                ),
              if (result.occurredAt != null)
                Text('วันที่/เวลา: ${result.occurredAt}'),
              if (result.direction != null)
                Text(
                  'ประเภท: ${result.direction == SlipDirection.outgoing ? 'เงินออก' : 'เงินเข้า'}',
                ),
              Text('ความมั่นใจ: ${(result.confidence * 100).round()}%'),
            ],
            if (record?.failureCode != null) ...[
              const Divider(),
              Text('อ่านรูปไม่สำเร็จ: ${record!.failureCode}'),
              const Text('ลองใหม่ได้ โดยไม่มีการสร้างรายการการเงิน'),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _analyze(event),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('วิเคราะห์สลิป'),
                ),
                if (result?.isHighConfidence == true &&
                    record?.candidateId == null)
                  FilledButton(
                    onPressed: busy ? null : () => _createCandidate(event),
                    child: const Text('สร้างรายการรอตรวจ'),
                  ),
                if (record?.candidateId != null)
                  const Chip(label: Text('สร้างรายการรอตรวจแล้ว')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
