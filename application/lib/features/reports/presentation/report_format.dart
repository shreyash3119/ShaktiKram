import '../data/report_period.dart' show ymd;

/// `upper_chest` becomes `Upper chest`.
String prettyKey(String key) {
  if (key.isEmpty) return '';
  final text = key.replaceAll('_', ' ');
  return text[0].toUpperCase() + text.substring(1);
}

/// 12.0 becomes `12`, 12.34 becomes `12.3`. A missing value is a dash.
String fmtNum(double? v, {int decimals = 1}) {
  if (v == null) return '—';
  final fixed = v.toStringAsFixed(decimals);
  if (!fixed.contains('.')) return _group(fixed);
  var t = fixed;
  while (t.endsWith('0')) {
    t = t.substring(0, t.length - 1);
  }
  if (t.endsWith('.')) t = t.substring(0, t.length - 1);
  return _group(t);
}

String _group(String s) {
  final parts = s.split('.');
  final digits = parts[0];
  final neg = digits.startsWith('-');
  final body = neg ? digits.substring(1) : digits;
  final buf = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    if (i > 0 && (body.length - i) % 3 == 0) buf.write(',');
    buf.write(body[i]);
  }
  return '${neg ? '-' : ''}$buf${parts.length > 1 ? '.${parts[1]}' : ''}';
}

String fmtKg(double? v) => v == null ? '—' : '${fmtNum(v, decimals: 1)} kg';
String fmtPct(double? v) => v == null ? '—' : '${fmtNum(v, decimals: 0)}%';
String fmtDate(DateTime? d) => d == null ? '—' : ymd(d);

/// `+4.5%` or `-2%`; a dash when the server gave no change.
String fmtChange(double? pct) {
  if (pct == null) return '—';
  final t = fmtNum(pct, decimals: 1);
  return pct > 0 ? '+$t%' : '$t%';
}

String fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// Names for the headline figures the service compares between two periods.
String comparisonLabel(String key) {
  switch (key) {
    case 'sessions':
      return 'Workouts';
    case 'volume_kg':
      return 'Volume (kg)';
    case 'consistency_pct':
      return 'Consistency (%)';
    case 'avg_sleep_hours':
      return 'Average sleep (h)';
    case 'avg_steps':
      return 'Average steps';
    case 'personal_records':
      return 'Personal records';
    default:
      return prettyKey(key);
  }
}

/// Names for the kinds of personal record.
String recordKindLabel(String kind) => prettyKey(kind);

/// What a goal's progress status means, in plain words.
String progressStatusLabel(String? status) {
  switch (status) {
    case 'on_track':
      return 'On track';
    case 'behind':
      return 'Behind';
    case 'achieved':
      return 'Achieved';
    case 'insufficient_data':
      return 'Not enough data yet';
    default:
      return status == null ? '' : prettyKey(status);
  }
}

String ratingChangeLabel(String change) {
  switch (change) {
    case 'higher_rating':
      return 'rated higher';
    case 'lower_rating':
      return 'rated lower';
    default:
      return 'rating unchanged';
  }
}

/// Wording for the label under a block of figures (`value_kind` from the service).
String? valueKindNote(String kind) {
  switch (kind) {
    case 'estimated':
      return 'Estimated values: calculated from your records, not direct measurements.';
    case 'user_assessment':
      return 'Your own ratings. They show how you judged each muscle, not measured growth.';
    default:
      return null;
  }
}
