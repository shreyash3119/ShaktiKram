import 'dart:convert';

import '../backend/backend_error.dart';
import '../backend/backend_gateway.dart';
import '../db/local_store.dart';

/// How current a cached server calculation is.
enum InsightFreshness {
  /// Received recently enough to show as it is.
  fresh,

  /// Received a while ago: still shown, but labelled with its age.
  stale,

  /// Nothing has been received yet (or never successfully): there is nothing to show.
  none,
}

/// A server calculation as the screen sees it: the last answer on the phone, how old it is, and whether the latest
/// attempt to update it failed. Showing `data` while `error` is set is deliberate: the last known answer beats a blank.
class InsightSnapshot {
  const InsightSnapshot({this.data, this.fetchedAt, required this.freshness, this.error, this.refreshing = false});

  const InsightSnapshot.none() : this(freshness: InsightFreshness.none);

  /// Decoded server JSON (a map or a list), or null when [freshness] is none.
  final Object? data;
  final DateTime? fetchedAt;
  final InsightFreshness freshness;

  /// Set when the last refresh failed; `isOffline` tells a dropped connection from a server refusal.
  final BackendError? error;
  final bool refreshing;

  bool get hasData => data != null;
  bool get isOffline => error?.isUnreachable ?? false;

  InsightSnapshot copyWith({bool? refreshing}) =>
      InsightSnapshot(data: data, fetchedAt: fetchedAt, freshness: freshness, error: error, refreshing: refreshing ?? this.refreshing);
}

/// What to fetch for one cached insight: where it is stored, how it is fetched, and how long it counts as fresh.
class InsightSpec {
  const InsightSpec({required this.key, required this.fetch, this.freshFor = const Duration(minutes: 30)});

  /// Cache key, for example `daily_briefing:2026-11-12` or `view:v_goal_progress`.
  final String key;
  final Future<Object?> Function(BackendGateway gateway) fetch;
  final Duration freshFor;

  @override
  bool operator ==(Object other) => other is InsightSpec && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Keeps copies of the server's calculated answers on the phone (architecture: Flutter caches and displays, it does
/// not recalculate). Reading never needs a connection; refreshing does, and a failed refresh leaves the old answer.
class InsightRepository {
  InsightRepository({required LocalStore store, required BackendGateway gateway, DateTime Function()? clock})
      : _store = store,
        _gateway = gateway,
        _clock = clock ?? DateTime.now;

  final LocalStore _store;
  final BackendGateway _gateway;
  final DateTime Function() _clock;

  /// The saved answer for [spec], without touching the network.
  Future<InsightSnapshot> cached(InsightSpec spec) async {
    final saved = await _store.readInsight(spec.key);
    if (saved == null) return const InsightSnapshot.none();
    Object? data;
    try {
      data = jsonDecode(saved.payload);
    } on FormatException {
      return const InsightSnapshot.none();
    }
    final age = _clock().difference(saved.fetchedAt);
    return InsightSnapshot(data: data, fetchedAt: saved.fetchedAt, freshness: age <= spec.freshFor ? InsightFreshness.fresh : InsightFreshness.stale);
  }

  /// Asks the server again. On success the answer is saved and returned as fresh. On failure the saved answer comes
  /// back unchanged with the error attached; nothing is erased.
  Future<InsightSnapshot> refresh(InsightSpec spec) async {
    try {
      final data = await spec.fetch(_gateway);
      final now = _clock();
      await _store.writeInsight(spec.key, jsonEncode(data), now);
      return InsightSnapshot(data: data, fetchedAt: now.toUtc(), freshness: InsightFreshness.fresh);
    } on BackendError catch (e) {
      final saved = await cached(spec);
      return InsightSnapshot(data: saved.data, fetchedAt: saved.fetchedAt, freshness: saved.freshness, error: e);
    }
  }
}
