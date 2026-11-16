import '../../../core/time/local_stamp.dart';

const monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

String todayDate() => localStampOf(DateTime.now()).localDate;

String _two(int n) => n.toString().padLeft(2, '0');
String _fmt(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

/// Monday of the week that contains [localDate].
String mondayOf(String localDate) {
  final d = DateTime.parse(localDate);
  return _fmt(DateTime.utc(d.year, d.month, d.day - (d.weekday - 1)));
}

String datePlus(String localDate, int days) {
  final d = DateTime.parse(localDate);
  return _fmt(DateTime.utc(d.year, d.month, d.day + days));
}

/// `Sat, Nov 14`.
String dateText(String localDate) {
  final d = DateTime.tryParse(localDate);
  return d == null
      ? localDate
      : '${weekdayNames[d.weekday - 1]}, ${monthNames[d.month - 1]} ${d.day}';
}

/// `Nov 9 – 15`, or `Nov 30 – Dec 6` when the week crosses a month.
String weekRangeText(String monday) {
  final a = DateTime.parse(monday);
  final b = DateTime.parse(datePlus(monday, 6));
  final start = '${monthNames[a.month - 1]} ${a.day}';
  return a.month == b.month
      ? '$start – ${b.day}'
      : '$start – ${monthNames[b.month - 1]} ${b.day}';
}

/// "42 min", "under 1 min", or nothing when the length is unknown.
String minutesText(int? seconds) {
  if (seconds == null) return '';
  if (seconds < 60) return 'under 1 min';
  return '${(seconds / 60).round()} min';
}

/// 6420 becomes `6,420`; 12.5 becomes `12.5`.
String kgText(double v) {
  final whole = v == v.roundToDouble();
  final s = whole ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  final parts = s.split('.');
  final digits = parts[0];
  final buf = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0 && digits[i - 1] != '-'){
      buf.write(',');
    buf.write(digits[i]);
  }}
  return parts.length > 1 ? '$buf.${parts[1]}' : '$buf';
}

/// Consecutive weeks (Monday to Sunday) that each hold at least one counted workout, ending with the current week.
/// The current week not having a workout yet does not break the streak: it counts back from last week then.
int weekStreak(Iterable<String> countedDates, String today) {
  final weeks = {for (final d in countedDates) mondayOf(d)};
  var cursor = mondayOf(today);
  if (!weeks.contains(cursor)) cursor = datePlus(cursor, -7);
  var n = 0;
  while (weeks.contains(cursor)) {
    n++;
    cursor = datePlus(cursor, -7);
  }
  return n;
}
