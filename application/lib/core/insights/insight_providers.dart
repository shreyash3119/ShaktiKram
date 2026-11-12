import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import '../backend/backend_gateway.dart';
import '../db/local_store.dart';
import 'insight_repository.dart';

final insightRepositoryProvider = Provider<InsightRepository>((ref) {
  return InsightRepository(store: ref.read(localStoreProvider), gateway: ref.read(backendGatewayProvider));
});

/// One cached server calculation. It shows the saved answer at once, then asks the server for a newer one when the
/// answer is missing or stale and the phone is signed in. `refresh()` asks again on demand (pull to refresh, retry).
/// Without a connection the saved answer stays and `error` says why it could not be updated.
final insightProvider = AsyncNotifierProvider.family<InsightNotifier, InsightSnapshot, InsightSpec>(InsightNotifier.new);

class InsightNotifier extends FamilyAsyncNotifier<InsightSnapshot, InsightSpec> {
  bool _disposed = false;

  @override
  Future<InsightSnapshot> build(InsightSpec arg) async {
    _disposed = false;
    ref.onDispose(() => _disposed = true);
    final repo = ref.read(insightRepositoryProvider);
    final saved = await repo.cached(arg);
    if (saved.freshness != InsightFreshness.fresh && _signedIn) {
      // Update in the background so the saved answer shows straight away.
      Future<void>.microtask(refresh);
    }
    return saved;
  }

  bool get _signedIn => ref.read(sessionControllerProvider).phase == SessionPhase.ready;

  Future<void> refresh() async {
    final repo = ref.read(insightRepositoryProvider);
    final current = state.valueOrNull ?? const InsightSnapshot.none();
    if (current.refreshing) return;
    state = AsyncData(current.copyWith(refreshing: true));
    final next = await repo.refresh(arg);
    if (!_disposed) state = AsyncData(next);
  }
}
