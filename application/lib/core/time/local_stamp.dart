/// The three time fields the backend wants on an event record: when it happened (UTC), the local calendar day, and the
/// phone's offset from UTC. The server checks that the day matches the instant and the offset, so all three always
/// come from one [instant] (decision: `local_date` and `tz_offset_minutes` on every event).
class LocalStamp {
  const LocalStamp({required this.occurredAt, required this.localDate, required this.tzOffsetMinutes});

  /// UTC, ISO 8601.
  final String occurredAt;

  /// `YYYY-MM-DD` in the phone's time zone at that instant.
  final String localDate;
  final int tzOffsetMinutes;

  Map<String, dynamic> toPayload() => {
        'occurred_at': occurredAt,
        'local_date': localDate,
        'tz_offset_minutes': tzOffsetMinutes,
      };
}

LocalStamp localStampOf(DateTime instant) {
  final offset = instant.toLocal().timeZoneOffset;
  final shifted = instant.toUtc().add(offset);
  String two(int n) => n.toString().padLeft(2, '0');
  return LocalStamp(
    occurredAt: instant.toUtc().toIso8601String(),
    localDate: '${shifted.year.toString().padLeft(4, '0')}-${two(shifted.month)}-${two(shifted.day)}',
    tzOffsetMinutes: offset.inMinutes,
  );
}
