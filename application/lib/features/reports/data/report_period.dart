/// Report periods. The kinds, parameters and limits are the reporting service's (`shared/vocabulary/statuses.json`,
/// `shared/api_contracts/stage5_reports_backup.md`); this file only builds and checks the query. The service does the
/// calculation and has the last word: it answers 422 with a reason for anything it refuses.
library;

const _monthNames = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// The longest custom range the service accepts.
const maxCustomDays = 3660;

enum ReportKind {
  daily('daily', 'Day'),
  weekly('weekly', 'Week'),
  monthly('monthly', 'Month'),
  quarterly('quarterly', 'Quarter'),
  halfYearly('half_yearly', 'Half-year'),
  yearly('yearly', 'Year'),
  custom('custom', 'Custom'),
  complete('complete', 'All time');

  const ReportKind(this.wire, this.label);

  /// The value of the `period` parameter.
  final String wire;
  final String label;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

String ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _lastOfMonth(int year, int month) => DateTime(year, month + 1, 0);

/// One report period, with the parameters it is sent as.
class ReportQuery {
  const ReportQuery._(this.kind, {this.year, this.month, this.quarter, this.half, this.day, this.weekStart, this.dateFrom, this.dateTo});

  factory ReportQuery.daily(DateTime day) => ReportQuery._(ReportKind.daily, day: _day(day));

  /// Any date in the week; the week starts on Monday (as the service counts it).
  factory ReportQuery.weekly(DateTime anyDayInWeek) {
    final d = _day(anyDayInWeek);
    return ReportQuery._(ReportKind.weekly, weekStart: d.subtract(Duration(days: d.weekday - DateTime.monday)));
  }

  factory ReportQuery.monthly(int year, int month) => ReportQuery._(ReportKind.monthly, year: year, month: month);
  factory ReportQuery.quarterly(int year, int quarter) => ReportQuery._(ReportKind.quarterly, year: year, quarter: quarter);
  factory ReportQuery.halfYearly(int year, int half) => ReportQuery._(ReportKind.halfYearly, year: year, half: half);
  factory ReportQuery.yearly(int year) => ReportQuery._(ReportKind.yearly, year: year);
  factory ReportQuery.custom(DateTime from, DateTime to) => ReportQuery._(ReportKind.custom, dateFrom: _day(from), dateTo: _day(to));
  const ReportQuery.complete() : this._(ReportKind.complete);

  /// The period of [kind] that contains [now]. A custom range starts as the last 30 days.
  factory ReportQuery.current(ReportKind kind, DateTime now) {
    switch (kind) {
      case ReportKind.daily:
        return ReportQuery.daily(now);
      case ReportKind.weekly:
        return ReportQuery.weekly(now);
      case ReportKind.monthly:
        return ReportQuery.monthly(now.year, now.month);
      case ReportKind.quarterly:
        return ReportQuery.quarterly(now.year, (now.month - 1) ~/ 3 + 1);
      case ReportKind.halfYearly:
        return ReportQuery.halfYearly(now.year, now.month <= 6 ? 1 : 2);
      case ReportKind.yearly:
        return ReportQuery.yearly(now.year);
      case ReportKind.custom:
        final end = _day(now);
        return ReportQuery.custom(end.subtract(const Duration(days: 29)), end);
      case ReportKind.complete:
        return const ReportQuery.complete();
    }
  }

  final ReportKind kind;
  final int? year;
  final int? month;
  final int? quarter;
  final int? half;
  final DateTime? day;
  final DateTime? weekStart;
  final DateTime? dateFrom;
  final DateTime? dateTo;

  /// First and last day, or null for "all time" (the service works that out from the records).
  (DateTime, DateTime)? get range {
    switch (kind) {
      case ReportKind.daily:
        return day == null ? null : (day!, day!);
      case ReportKind.weekly:
        return weekStart == null ? null : (weekStart!, weekStart!.add(const Duration(days: 6)));
      case ReportKind.monthly:
        return (year == null || month == null) ? null : (DateTime(year!, month!, 1), _lastOfMonth(year!, month!));
      case ReportKind.quarterly:
        if (year == null || quarter == null) return null;
        final first = 3 * (quarter! - 1) + 1;
        return (DateTime(year!, first, 1), _lastOfMonth(year!, first + 2));
      case ReportKind.halfYearly:
        if (year == null || half == null) return null;
        final first = half == 1 ? 1 : 7;
        return (DateTime(year!, first, 1), _lastOfMonth(year!, first + 5));
      case ReportKind.yearly:
        return year == null ? null : (DateTime(year!, 1, 1), DateTime(year!, 12, 31));
      case ReportKind.custom:
        return (dateFrom == null || dateTo == null) ? null : (dateFrom!, dateTo!);
      case ReportKind.complete:
        return null;
    }
  }

  /// The same words the service puts on the report.
  String get label {
    final r = range;
    switch (kind) {
      case ReportKind.daily:
        return day == null ? 'Day' : ymd(day!);
      case ReportKind.weekly:
        return weekStart == null ? 'Week' : 'Week of ${ymd(weekStart!)}';
      case ReportKind.monthly:
        return (year == null || month == null || month! < 1 || month! > 12) ? 'Month' : '${_monthNames[month! - 1]} $year';
      case ReportKind.quarterly:
        return 'Q$quarter $year';
      case ReportKind.halfYearly:
        return 'H$half $year';
      case ReportKind.yearly:
        return '$year';
      case ReportKind.custom:
        return r == null ? 'Custom range' : '${ymd(r.$1)} to ${ymd(r.$2)}';
      case ReportKind.complete:
        return 'Complete history';
    }
  }

  /// Null when the period is acceptable, otherwise the reason (the service checks again and has the last word).
  String? validate() {
    final yearOk = year == null || (year! >= 1900 && year! <= 2200);
    if (!yearOk) return 'The year must be between 1900 and 2200.';
    switch (kind) {
      case ReportKind.daily:
        return day == null ? 'Choose a day.' : null;
      case ReportKind.weekly:
        return weekStart == null ? 'Choose a week.' : null;
      case ReportKind.monthly:
        if (year == null) return 'Choose a year.';
        return (month == null || month! < 1 || month! > 12) ? 'The month must be 1 to 12.' : null;
      case ReportKind.quarterly:
        if (year == null) return 'Choose a year.';
        return (quarter == null || quarter! < 1 || quarter! > 4) ? 'The quarter must be 1 to 4.' : null;
      case ReportKind.halfYearly:
        if (year == null) return 'Choose a year.';
        return (half != 1 && half != 2) ? 'The half must be 1 or 2.' : null;
      case ReportKind.yearly:
        return year == null ? 'Choose a year.' : null;
      case ReportKind.custom:
        if (dateFrom == null || dateTo == null) return 'Choose a first and a last day.';
        if (dateTo!.isBefore(dateFrom!)) return 'The last day must not be before the first day.';
        if (dateTo!.difference(dateFrom!).inDays + 1 > maxCustomDays) return 'A custom range can cover at most $maxCustomDays days.';
        return null;
      case ReportKind.complete:
        return null;
    }
  }

  /// The query parameters, named as the service names them.
  Map<String, String> toParams({bool compare = false}) => {
        'period': kind.wire,
        if (year != null && const {ReportKind.monthly, ReportKind.quarterly, ReportKind.halfYearly, ReportKind.yearly}.contains(kind)) 'year': '$year',
        if (kind == ReportKind.monthly && month != null) 'month': '$month',
        if (kind == ReportKind.quarterly && quarter != null) 'quarter': '$quarter',
        if (kind == ReportKind.halfYearly && half != null) 'half': '$half',
        if (kind == ReportKind.daily && day != null) 'day': ymd(day!),
        if (kind == ReportKind.weekly && weekStart != null) 'week_start': ymd(weekStart!),
        if (kind == ReportKind.custom && dateFrom != null) 'date_from': ymd(dateFrom!),
        if (kind == ReportKind.custom && dateTo != null) 'date_to': ymd(dateTo!),
        if (compare) 'compare': 'true',
      };

  /// Stable text for the same period (used as the cache key).
  String get cacheKey => toParams().entries.map((e) => '${e.key}=${e.value}').join('&');

  /// Whether stepping to the previous or next period makes sense (not for a custom range or all time).
  bool get canStep => kind != ReportKind.custom && kind != ReportKind.complete;

  /// The period [steps] before (negative) or after (positive) this one, of the same kind.
  ReportQuery shifted(int steps) {
    switch (kind) {
      case ReportKind.daily:
        return day == null ? this : ReportQuery.daily(day!.add(Duration(days: steps)));
      case ReportKind.weekly:
        return weekStart == null ? this : ReportQuery.weekly(weekStart!.add(Duration(days: 7 * steps)));
      case ReportKind.monthly:
        if (year == null || month == null) return this;
        final index = year! * 12 + (month! - 1) + steps;
        return ReportQuery.monthly(index ~/ 12, index % 12 + 1);
      case ReportKind.quarterly:
        if (year == null || quarter == null) return this;
        final index = year! * 4 + (quarter! - 1) + steps;
        return ReportQuery.quarterly(index ~/ 4, index % 4 + 1);
      case ReportKind.halfYearly:
        if (year == null || half == null) return this;
        final index = year! * 2 + (half! - 1) + steps;
        return ReportQuery.halfYearly(index ~/ 2, index % 2 + 1);
      case ReportKind.yearly:
        return year == null ? this : ReportQuery.yearly(year! + steps);
      case ReportKind.custom:
      case ReportKind.complete:
        return this;
    }
  }

  /// True when the period starts after [today], so it cannot hold any records yet.
  bool startsAfter(DateTime today) {
    final r = range;
    return r != null && r.$1.isAfter(_day(today));
  }

  @override
  bool operator ==(Object other) => other is ReportQuery && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}

/// A period plus whether the previous period is wanted too. One cached summary per request.
class ReportRequest {
  const ReportRequest(this.query, {this.compare = false});

  final ReportQuery query;
  final bool compare;

  Map<String, String> toParams() => query.toParams(compare: compare);

  String get cacheKey => 'report:summary:${query.toParams(compare: compare).entries.map((e) => '${e.key}=${e.value}').join('&')}';

  @override
  bool operator ==(Object other) => other is ReportRequest && other.cacheKey == cacheKey;

  @override
  int get hashCode => cacheKey.hashCode;
}
