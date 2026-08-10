import 'dart:typed_data';

import '../models/financial_models.dart';

abstract interface class StatementAdapter {
  String get institution;
  String get version;
  bool supports({required String fileName, required Uint8List header});
  Future<ParsedStatement> parse(Uint8List bytes, {required String fileName});
}

final class StatementAdapterRegistry {
  StatementAdapterRegistry(this.adapters);
  final List<StatementAdapter> adapters;

  StatementAdapter resolve({required String fileName, required Uint8List header}) => adapters.firstWhere(
        (adapter) => adapter.supports(fileName: fileName, header: header),
        orElse: () => throw UnsupportedError('No statement adapter supports $fileName'),
      );
}
