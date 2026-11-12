/// One cached answer from the server's calculation functions or views, as stored on the phone.
class CachedInsight {
  const CachedInsight({required this.key, required this.payload, required this.fetchedAt});

  final String key;

  /// The server's JSON, as text.
  final String payload;

  /// When this phone received it.
  final DateTime fetchedAt;
}
