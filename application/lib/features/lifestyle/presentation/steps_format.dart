/// Small date and number helpers shared by the Steps card and the Steps History screen.
/// Dates travel as `yyyy-MM-dd` strings, the same form the database uses for `local_date`.

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const weekdayNames = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
];

/// 12345 -> "12,345".
String formatSteps(int n) {
  final s = n.abs().toString();
  final b = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return b.toString();
}

String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseDateKey(String key) {
  final p = key.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

/// Calendar-day arithmetic that is safe across daylight-saving changes.
DateTime addDays(DateTime d, int days) => DateTime(d.year, d.month, d.day + days);

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// The Monday of the week that holds [d].
DateTime mondayOf(DateTime d) => addDays(d, -(d.weekday - DateTime.monday));

/// "Sunday, November 15".
String longDay(DateTime d) =>
    '${weekdayNames[d.weekday - 1]}, ${monthNames[d.month - 1]} ${d.day}';

/// "Nov 15".
String shortDay(DateTime d) => '${monthNames[d.month - 1].substring(0, 3)} ${d.day}';

/// "M", "T", "W" ... for the tiny chart under the Steps card.
String dayInitial(DateTime d) => 'MTWTFSS'[d.weekday - 1];
