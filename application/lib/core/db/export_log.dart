import 'dart:convert';

/// What kind of file the phone saved.
enum ExportKind {
  reportXlsx('report_xlsx', 'Excel report'),
  reportPdf('report_pdf', 'PDF report'),
  backupZip('backup_zip', 'Full backup'),
  dataCsv('data_csv', 'CSV data export');

  const ExportKind(this.wire, this.label);
  final String wire;
  final String label;

  static ExportKind? fromWire(String? v) {
    for (final k in values) {
      if (k.wire == v) return k;
    }
    return null;
  }

  bool get isReport => this == reportXlsx || this == reportPdf;
}

/// One file saved on this phone by a report export or a backup. Kept only on the phone (never synced). The record
/// stays even if the file is deleted outside the app; the app checks whether the file still exists when it is shown.
class ExportLogEntry {
  const ExportLogEntry({
    this.id,
    required this.kind,
    required this.label,
    required this.path,
    required this.sizeBytes,
    required this.createdAt,
    this.detail = const {},
  });

  /// Set by the store.
  final int? id;
  final ExportKind kind;

  /// What the person sees, for example the report period ("November 2026") or "Full backup".
  final String label;
  final String path;
  final int sizeBytes;
  final DateTime createdAt;

  /// Small extra facts, for example `{"period": "monthly", "compare": true}` or `{"include_media": false}`.
  final Map<String, Object?> detail;

  String get fileName => path.split(RegExp(r'[\\/]')).last;

  ExportLogEntry withId(int newId) => ExportLogEntry(
    id: newId,
    kind: kind,
    label: label,
    path: path,
    sizeBytes: sizeBytes,
    createdAt: createdAt,
    detail: detail,
  );

  String detailJson() => jsonEncode(detail);

  static Map<String, Object?> detailFromJson(Object? v) {
    if (v is! String || v.isEmpty) return const {};
    try {
      final d = jsonDecode(v);
      return d is Map ? Map<String, Object?>.from(d) : const {};
    } on FormatException {
      return const {};
    }
  }
}
