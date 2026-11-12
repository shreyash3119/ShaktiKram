import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/auth/session_controller.dart';
import 'package:shaktikram/core/backend/backend_error.dart';
import 'package:shaktikram/core/insights/insight_providers.dart';
import 'package:shaktikram/core/insights/insight_repository.dart';
import 'package:shaktikram/features/progress/data/progress_insights.dart';

import 'support/fakes.dart';
import 'support/memory_local_store.dart';

void main() {
  group('InsightRepository', () {
    late MemoryLocalStore store;
    late FakeGateway gateway;
    late DateTime now;
    late InsightRepository repo;
    final spec = dailyBriefingSpec('2026-11-12');

    setUp(() {
      store = MemoryLocalStore();
      gateway = FakeGateway();
      now = DateTime.utc(2026, 11, 12, 8);
      repo = InsightRepository(store: store, gateway: gateway, clock: () => now);
    });

    test('nothing saved yet means nothing to show', () async {
      final snap = await repo.cached(spec);
      expect((snap.freshness, snap.data, snap.fetchedAt), (InsightFreshness.none, null, null));
    });

    test('a refresh saves the answer, which is then read back without the network', () async {
      gateway.insightAnswers['api_daily_briefing'] = {'date': '2026-11-12', 'plan': {'is_rest_day': true}};
      final fresh = await repo.refresh(spec);
      expect(fresh.freshness, InsightFreshness.fresh);
      expect(gateway.calls, ['insight:api_daily_briefing']);

      final again = await repo.cached(spec);
      expect((again.data as Map)['date'], '2026-11-12');
      expect(again.fetchedAt, now);
      expect(gateway.calls, hasLength(1));
    });

    test('an old answer is stale, not discarded', () async {
      gateway.insightAnswers['api_daily_briefing'] = {'date': '2026-11-12'};
      await repo.refresh(spec);
      now = now.add(const Duration(minutes: 16));
      expect((await repo.cached(spec)).freshness, InsightFreshness.stale);
      now = now.add(const Duration(days: 2));
      final old = await repo.cached(spec);
      expect((old.freshness, old.hasData), (InsightFreshness.stale, true));
    });

    test('offline: the last answer stays and the snapshot says it could not be updated', () async {
      gateway.insightAnswers['api_daily_briefing'] = {'date': '2026-11-12', 'streak': {'current_streak': 4}};
      await repo.refresh(spec);
      now = now.add(const Duration(hours: 3));

      gateway.insightError = const BackendError.unreachable();
      final snap = await repo.refresh(spec);
      expect(snap.isOffline, isTrue);
      expect(snap.freshness, InsightFreshness.stale);
      expect(((snap.data as Map)['streak'] as Map)['current_streak'], 4);
      expect((await repo.cached(spec)).hasData, isTrue);
    });

    test('offline with nothing saved gives no data and the error, never made-up values', () async {
      gateway.insightError = const BackendError.unreachable();
      final snap = await repo.refresh(spec);
      expect((snap.hasData, snap.freshness, snap.isOffline), (false, InsightFreshness.none, true));
    });

    test('a server refusal is kept apart from being offline', () async {
      gateway.insightError = const BackendError('forbidden', 'Not the owner');
      final snap = await repo.refresh(spec);
      expect((snap.isOffline, snap.error?.code), (false, 'forbidden'));
    });

    test('an unreadable saved answer is treated as missing', () async {
      await store.writeInsight(spec.key, '{not json', now);
      expect((await repo.cached(spec)).freshness, InsightFreshness.none);
    });

    test('views are cached as lists under their own keys', () async {
      gateway.viewRows['v_exercise_trends'] = [
        {'exercise_id': 'e1', 'signal': 'improving', 'change_pct': 4.5},
      ];
      await repo.refresh(exerciseTrendsSpec);
      final snap = await repo.cached(exerciseTrendsSpec);
      expect(snap.data, isA<List>());
      expect(gateway.calls, ['view:v_exercise_trends']);
    });
  });

  group('insightProvider', () {
    test('shows the saved answer at once and updates it in the background when it is stale', () async {
      final h = Harness.ready();
      final container = ProviderContainer(overrides: h.overrides);
      addTearDown(container.dispose);
      container.read(sessionControllerProvider);
      await pumpEventQueue();
      expect(container.read(sessionControllerProvider).phase, SessionPhase.ready);

      final spec = dailyBriefingSpec('2026-11-12');
      await h.local.writeInsight(spec.key, '{"date":"2026-11-12","streak":{"current_streak":1}}', DateTime.utc(2026, 11, 1));
      h.gateway.insightAnswers['api_daily_briefing'] = {'date': '2026-11-12', 'streak': {'current_streak': 5}};

      final first = await container.read(insightProvider(spec).future);
      expect(first.freshness, InsightFreshness.stale);
      expect(((first.data as Map)['streak'] as Map)['current_streak'], 1);

      await pumpEventQueue();
      final next = container.read(insightProvider(spec)).value!;
      expect(next.freshness, InsightFreshness.fresh);
      expect(((next.data as Map)['streak'] as Map)['current_streak'], 5);
      expect(h.gateway.calls.where((c) => c == 'insight:api_daily_briefing'), hasLength(1));
    });

    test('a fresh saved answer is not fetched again', () async {
      final h = Harness.ready();
      final container = ProviderContainer(overrides: h.overrides);
      addTearDown(container.dispose);
      container.read(sessionControllerProvider);
      await pumpEventQueue();

      final spec = dailyBriefingSpec('2026-11-12');
      await h.local.writeInsight(spec.key, '{"date":"2026-11-12"}', DateTime.now());
      await container.read(insightProvider(spec).future);
      await pumpEventQueue();
      expect(h.gateway.calls.where((c) => c.startsWith('insight:')), isEmpty);
    });

    test('nothing is asked of the server while signed out', () async {
      final h = Harness.signedOut();
      final container = ProviderContainer(overrides: h.overrides);
      addTearDown(container.dispose);
      container.read(sessionControllerProvider);
      await pumpEventQueue();

      final snap = await container.read(insightProvider(dailyBriefingSpec('2026-11-12')).future);
      await pumpEventQueue();
      expect(snap.freshness, InsightFreshness.none);
      expect(h.gateway.calls.where((c) => c.startsWith('insight:')), isEmpty);
    });

    test('refresh() offline leaves the saved answer and reports the error', () async {
      final h = Harness.ready();
      final container = ProviderContainer(overrides: h.overrides);
      addTearDown(container.dispose);
      container.read(sessionControllerProvider);
      await pumpEventQueue();

      final spec = dailyBriefingSpec('2026-11-12');
      await h.local.writeInsight(spec.key, '{"date":"2026-11-12"}', DateTime.now());
      await container.read(insightProvider(spec).future);
      h.gateway.insightError = const BackendError.unreachable();
      await container.read(insightProvider(spec).notifier).refresh();

      final snap = container.read(insightProvider(spec)).value!;
      expect((snap.hasData, snap.isOffline, snap.refreshing), (true, true, false));
    });
  });
}
