import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/backend/report_error.dart';
import '../../../core/backend/reporting_gateway.dart';
import '../../../core/db/local_store.dart';
import '../../../core/insights/insight_repository.dart' show InsightFreshness;
import 'report_models.dart';
import 'report_period.dart';

/// A report as the screen sees it: the last summary on the phone, how old it is, and whether the latest attempt to
/// update it failed. Showing [summary] while [error] is set is deliberate: the last known report beats a blank.
class ReportSnapshot {
  const ReportSnapshot({
    this.summary,
    this.fetchedAt,
    required this.freshness,
    this.error,
    this.refreshing = false,
  });

  const ReportSnapshot.none() : this(freshness: InsightFreshness.none);

  final ReportSummary? summary;

  /// When this phone received the summary from the server.
  final DateTime? fetchedAt;
  final InsightFreshness freshness;
  final ReportError? error;
  final bool refreshing;

  bool get hasData => summary != null;
  bool get isOffline => error?.isOffline ?? false;

  ReportSnapshot copyWith({bool? refreshing}) => ReportSnapshot(
    summary: summary,
    fetchedAt: fetchedAt,
    freshness: freshness,
    error: error,
    refreshing: refreshing ?? this.refreshing,
  );
}

/// Reads report summaries from the reporting service and keeps the last one per period on the phone (in the existing
/// `insight_cache` table). The phone shows and caches the summary; every figure in it was calculated by the server.
class ReportRepository {
  ReportRepository({
    required LocalStore store,
    required ReportingGateway gateway,
    DateTime Function()? clock,
    this.freshFor = const Duration(minutes: 15),
  }) : _store = store,
       _gateway = gateway,
       _clock = clock ?? DateTime.now;

  final LocalStore _store;
  final ReportingGateway _gateway;
  final DateTime Function() _clock;

  /// How long a received summary counts as current before it is labelled as possibly out of date.
  final Duration freshFor;

  /// The saved summary for [request], without touching the network.
  Future<ReportSnapshot> cached(ReportRequest request) async {
    final saved = await _store.readInsight(request.cacheKey);
    if (saved == null) return const ReportSnapshot.none();
    try {
      final summary = ReportSummary.fromJson(
        Map<String, dynamic>.from(jsonDecode(saved.payload) as Map),
      );
      final age = _clock().difference(saved.fetchedAt);
      return ReportSnapshot(
        summary: summary,
        fetchedAt: saved.fetchedAt,
        freshness:
            age <= freshFor ? InsightFreshness.fresh : InsightFreshness.stale,
      );
    } on FormatException {
      return const ReportSnapshot.none();
    } on TypeError {
      return const ReportSnapshot.none();
    }
  }

  /// Asks the server again. On success the summary is saved and returned as fresh. On failure the saved one comes back
  /// unchanged with the error attached; nothing is erased.
  Future<ReportSnapshot> refresh(ReportRequest request) async {
    final problem = request.query.validate();
    if (problem != null) {
      final saved = await cached(request);
      return ReportSnapshot(
        summary: saved.summary,
        fetchedAt: saved.fetchedAt,
        freshness: saved.freshness,
        error: ReportError(ReportErrorKind.invalidRequest, problem),
      );
    }
    try {
      final json = await _gateway.summary(request.toParams());
      final ReportSummary summary;
      try {
        summary = ReportSummary.fromJson(json);
      } on FormatException {
        throw const ReportError(
          ReportErrorKind.badResponse,
          'The reporting service sent an answer the app could not read.',
        );
      }
      final now = _clock();
      await _store.writeInsight(request.cacheKey, jsonEncode(json), now);
      return ReportSnapshot(
        summary: summary,
        fetchedAt: now.toUtc(),
        freshness: InsightFreshness.fresh,
      );
    } on ReportError catch (e) {
      final saved = await cached(request);
      return ReportSnapshot(
        summary: saved.summary,
        fetchedAt: saved.fetchedAt,
        freshness: saved.freshness,
        error: e,
      );
    }
  }
}

final reportRepositoryProvider = Provider<ReportRepository>((ref) {
  return ReportRepository(
    store: ref.read(localStoreProvider),
    gateway: ref.read(reportingGatewayProvider),
  );
});

/// The period on the Reports screen.
final reportQueryProvider = StateProvider<ReportQuery>(
  (ref) => ReportQuery.current(ReportKind.monthly, DateTime.now()),
);

/// Whether the previous period is shown alongside.
final reportCompareProvider = StateProvider<bool>((ref) => false);

/// The period and comparison choice together.
final reportRequestProvider = Provider<ReportRequest>(
  (ref) => ReportRequest(
    ref.watch(reportQueryProvider),
    compare: ref.watch(reportCompareProvider),
  ),
);

/// One report summary: the saved one at once, then a newer one from the server when it is missing or out of date and the
/// phone is signed in. [ReportNotifier.refresh] asks again on demand. Offline, the saved summary stays and `error` says why.
final reportSummaryProvider =
    AsyncNotifierProvider.family<ReportNotifier, ReportSnapshot, ReportRequest>(
      ReportNotifier.new,
    );

class ReportNotifier
    extends FamilyAsyncNotifier<ReportSnapshot, ReportRequest> {
  bool _disposed = false;

  @override
  Future<ReportSnapshot> build(ReportRequest arg) async {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final repo = ref.read(reportRepositoryProvider);
    final saved = await repo.cached(arg);
    if (saved.freshness != InsightFreshness.fresh &&
        _signedIn &&
        arg.query.validate() == null &&
        !arg.query.startsAfter(DateTime.now())) {
      // Update in the background so the saved summary shows straight away.
      Future<void>.microtask(refresh);
    }
    return saved;
  }

  bool get _signedIn =>
      ref.read(sessionControllerProvider).phase == SessionPhase.ready;

  Future<void> refresh() async {
    final repo = ref.read(reportRepositoryProvider);
    final current = state.valueOrNull ?? const ReportSnapshot.none();
    if (current.refreshing) return;
    state = AsyncData(current.copyWith(refreshing: true));
    final next = await repo.refresh(arg);
    if (!_disposed) state = AsyncData(next);
  }
}
