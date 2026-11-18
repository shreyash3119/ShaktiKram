import 'lifestyle_repository.dart';
import 'lifestyle_service.dart';
import 'step_source.dart';

class StepImportResult {
  const StepImportResult({this.daysChecked = 0, this.daysWritten = 0, this.daysKeptManual = 0, this.todaySteps});

  final int daysChecked;
  final int daysWritten;

  /// Days left alone because the owner entered them by hand.
  final int daysKeptManual;

  /// Today's total as read from the source, or null when the source gave none.
  final int? todaySteps;
}

String _day(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Copies daily step totals from a [StepSource] into `daily_steps` (source `device_import`) through the normal
/// local-first write path, so it works offline and syncs like any other entry.
///
/// Rules:
///  - An imported total replaces an earlier imported total for the same day.
///  - A day the owner entered by hand (source `manual`) is never overwritten.
///  - A value that did not change is not written again, so nothing is queued for no reason.
///  - A day with no steps and no record gets no row.
class StepImportService {
  StepImportService({required this.source, required this.lifestyle, required this.repository, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  final StepSource source;
  final LifestyleService lifestyle;
  final LifestyleRepository repository;
  final DateTime Function() _clock;

  /// Reads today and the [days] - 1 days before it.
  Future<StepImportResult> importRecent({int days = 7}) async {
    final now = _clock();
    var checked = 0;
    var written = 0;
    var kept = 0;
    int? today;
    for (var i = 0; i < days; i++) {
      final start = DateTime(now.year, now.month, now.day - i);
      final end = i == 0 ? now : DateTime(now.year, now.month, now.day - i + 1);
      final total = await source.totalSteps(start, end);
      if (i == 0) today = total;
      if (total == null) continue;
      checked++;
      final date = _day(start);
      final existing = await repository.stepsFor(date);
      if (existing != null && existing.source == 'manual') {
        kept++;
        continue;
      }
      if (existing != null && existing.steps == total) continue;
      if (existing == null && total == 0) continue;
      await lifestyle.setSteps(total, localDate: date, source: 'device_import');
      written++;
    }
    return StepImportResult(daysChecked: checked, daysWritten: written, daysKeptManual: kept, todaySteps: today);
  }
}
