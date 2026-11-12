import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/auth/session_controller.dart';
import 'package:shaktikram/core/sync/change_writer.dart';
import 'package:shaktikram/core/sync/sync_status.dart';
import 'package:shaktikram/core/time/local_stamp.dart';
import 'package:shaktikram/features/lifestyle/data/lifestyle_repository.dart';
import 'package:shaktikram/features/lifestyle/data/lifestyle_service.dart';

import 'support/fake_server.dart';
import 'support/fakes.dart';
import 'support/store_contract.dart';

DateTime _clock = DateTime.utc(2026, 11, 10, 7);

final _writerProvider = Provider<ChangeWriter>(
  (ref) => ChangeWriter(ref, clock: () => _clock),
);

final _knee = uid(1);
final _shoulder = uid(2);

class _World {
  _World() {
    _clock = DateTime.utc(2026, 11, 10, 7);
    server = FakeServer();
    harness = Harness.ready();
    container = ProviderContainer(overrides: harness.overridesWith(server));
  }

  late final FakeServer server;
  late final Harness harness;
  late final ProviderContainer container;

  String get today => localStampOf(_clock).localDate;
  LifestyleRepository get repo => LifestyleRepository(harness.local);
  late final LifestyleService service = LifestyleService(
    writer: container.read(_writerProvider),
    repository: repo,
    clock: () => _clock,
  );

  Future<void> start() async {
    await server.registerDevice(
      id: 'device-1',
      label: 'Test phone',
      platform: 'mobile',
    );
    container.read(sessionControllerProvider);
    await pumpEventQueue();
    expect(container.read(sessionControllerProvider).phase, SessionPhase.ready);
    server.seed('body_regions', {'id': _knee, 'name': 'Knee'});
    server.seed('body_regions', {'id': _shoulder, 'name': 'Shoulder'});
    await sync();
  }

  Future<void> sync() => container.read(syncStatusProvider.notifier).syncNow();
  int pending() => container.read(syncStatusProvider).pendingCount;

  Future<void> expectCleanSync() async {
    await sync();
    expect(pending(), 0);
    expect(
      await harness.local.issueCount(),
      0,
      reason: (await harness.local.issues())
          .map((i) => '${i.entity}: ${i.errorCode} ${i.message}')
          .join('; '),
    );
  }
}

Future<_World> _ready() async {
  final w = _World();
  addTearDown(w.container.dispose);
  await w.start();
  return w;
}

/// The call must be refused with an [ArgumentError], whether it throws at once or through its Future.
Future<void> _refused(Object? Function() call) async {
  try {
    final result = call();
    if (result is Future) {
      await result;
    }
  } on ArgumentError {
    return;
  }
  fail('expected the call to be refused');
}

void main() {
  group('daily records', () {
    test('check-in and steps are one per day: saving again edits', () async {
      final w = await _ready();
      w.server.offline = true;
      final svc = w.service;

      final a = await svc.saveCheckin(energy: 4, soreness: 2);
      final b = await svc.saveCheckin(
        energy: 5,
        soreness: 2,
        notes: 'Slept well',
      );
      expect(b, a);
      expect((await w.repo.checkinFor(w.today))!.energy, 5);
      final s1 = await svc.setSteps(4000);
      final s2 = await svc.setSteps(9500, targetSteps: 10000);
      expect(s2, s1);
      expect((await w.repo.stepsFor(w.today))!.steps, 9500);

      w.server.offline = false;
      await w.expectCleanSync();
      expect(w.server.tables['daily_checkins']!.length, 1);
      expect(w.server.tables['daily_steps']!.length, 1);
    });

    test(
      'sleep, water and cardio are saved with the right day and sync cleanly',
      () async {
        final w = await _ready();
        final svc = w.service;

        final wake = _clock;
        await svc.logSleep(
          sleepAt: wake.subtract(const Duration(hours: 7, minutes: 30)),
          wakeAt: wake,
          quality: 4,
        );
        await svc.logSleep(durationSeconds: 1200, isNap: true);
        final sleep = await w.repo.sleepFor(localStampOf(wake).localDate);
        expect(sleep.firstWhere((s) => !s.isNap).hours, 7.5);

        await svc.addWater(250);
        await svc.addWater(500);
        await svc.logCardio(
          activity: 'running',
          durationSeconds: 1800,
          distanceM: 5000,
          intensity: 'moderate',
        );
        await svc.logCardio(
          activity: 'custom',
          customActivity: 'Rowing',
          durationSeconds: 600,
        );

        final summary = await w.repo.daySummary(w.today);
        expect(summary.waterMl, 750);
        expect(summary.cardioSeconds, 2400);
        expect(summary.sleepSeconds, 27000);

        await w.expectCleanSync();
        expect(w.server.tables['water_logs']!.length, 2);
        expect(w.server.tables['cardio_sessions']!.length, 2);
      },
    );

    test(
      'values the database would refuse are refused before saving',
      () async {
        final w = await _ready();
        final svc = w.service;
        await _refused(() => svc.saveCheckin(energy: 6));
        await _refused(() => svc.setSteps(-1));
        await _refused(() => svc.addWater(0));
        await _refused(
          () => svc.logSleep(
            sleepAt: DateTime.utc(2026, 11, 10, 8),
            wakeAt: DateTime.utc(2026, 11, 10, 7),
          ),
        );
        await _refused(
          () => svc.logCardio(activity: 'custom', durationSeconds: 60),
        );
        await _refused(() => svc.logMeasurement(type: 'body_fat', value: 18));
        await _refused(() => svc.logPain(bodyRegionId: _knee, level: 11));
        expect(w.pending(), 0);
      },
    );
  });

  group('injuries, pain and restrictions', () {
    test('an injury is updated, resolved and kept in the record', () async {
      final w = await _ready();
      final svc = w.service;

      final id = await svc.addInjury(
        name: 'Sore knee',
        bodyRegionId: _knee,
        side: 'left',
        severity: 'mild',
      );
      await svc.logPain(
        bodyRegionId: _knee,
        level: 3,
        side: 'left',
        injuryId: id,
        effectOnTraining: 'minor',
      );
      await svc.addRestriction(
        kind: 'avoid',
        movement: 'deep squat',
        injuryId: id,
      );
      await svc.updateInjury(
        id,
        note: 'Better after rest',
        status: 'recovering',
      );
      expect((await w.repo.injuries()).single.status, 'recovering');

      _clock = DateTime.utc(2026, 11, 20, 7);
      await svc.updateInjury(id, status: 'resolved');
      expect(await w.repo.injuries(), isEmpty);
      final all = await w.repo.injuries(includeResolved: true);
      expect(
        (all.single.status, all.single.resolvedOn),
        ('resolved', '2026-11-20'),
      );
      expect(await w.repo.recentPain(), hasLength(1));

      await w.expectCleanSync();
      expect(w.server.tables['injury_updates']!.length, 2);
    });

    test('an injury cannot be resolved before it started', () async {
      final w = await _ready();
      final id = await w.service.addInjury(
        name: 'Elbow',
        bodyRegionId: _shoulder,
        startDate: '2026-11-10',
      );
      await _refused(
        () => w.service.updateInjury(
          id,
          status: 'resolved',
          resolvedOn: '2026-11-01',
        ),
      );
    });
  });

  group('supplements, meals and targets', () {
    test(
      'a supplement has a phase, a dose change opens a new version, and logs point at the current phase',
      () async {
        final w = await _ready();
        final svc = w.service;

        final id = await svc.addSupplement(
          name: 'Creatine',
          doseAmount: 5,
          doseUnit: 'g',
        );
        expect((await w.repo.currentPhase(id))!.version, 1);
        await _refused(() => svc.addSupplement(name: 'creatine'));
        await svc.logSupplement(id);
        await w.expectCleanSync();

        _clock = DateTime.utc(2026, 11, 12, 7);
        await svc.changeSupplementPhase(
          id,
          doseAmount: 3,
          reason: 'lower dose',
        );
        final phase = (await w.repo.currentPhase(id))!;
        expect(
          (phase.version, phase.doseAmount, phase.doseUnit),
          (2, 3.0, 'g'),
        );
        await svc.logSupplement(id, outcome: 'missed');
        await w.expectCleanSync();
        expect(w.server.tables['supplement_phases']!.length, 2);
        expect(w.server.tables['supplement_logs']!.length, 2);
      },
    );

    test('meals can be planned, eaten and replaced', () async {
      final w = await _ready();
      final svc = w.service;
      final oats = await svc.saveMeal(
        title: 'Oats',
        category: 'breakfast',
        caloriesKcal: 350,
        proteinG: 12,
      );
      final eggs = await svc.saveMeal(
        title: 'Eggs',
        category: 'breakfast',
        proteinG: 18,
        isEstimate: true,
      );
      final lunch = await svc.saveMeal(title: 'Rice bowl', category: 'lunch');

      final planned = await svc.planMeal(slot: 'breakfast', mealId: oats);
      final other = await svc.planMeal(slot: 'lunch', mealId: lunch);
      await svc.setMealStatus(
        planned,
        status: 'replaced',
        replacedByMealId: eggs,
      );
      await svc.setMealStatus(other, status: 'eaten');
      await _refused(() => svc.setMealStatus(planned, status: 'replaced'));
      await svc.logMealEaten(slot: 'snack', mealId: oats);

      final day = await w.repo.daySummary(w.today);
      expect((day.mealsPlanned, day.mealsEaten), (3, 3));
      expect((await w.repo.mealPlanFor(w.today)).map((e) => e.slot), [
        'breakfast',
        'lunch',
        'snack',
      ]);
      await w.expectCleanSync();
    });

    test('new targets keep the earlier values that were not changed', () async {
      final w = await _ready();
      final svc = w.service;
      await svc.setTargets(
        proteinG: 150,
        caloriesKcal: 2600,
        waterMl: 3000,
        stepTarget: 10000,
      );
      await w.expectCleanSync();
      _clock = DateTime.utc(2026, 11, 15, 7);
      await svc.setTargets(proteinG: 160);
      final t = (await w.repo.currentTargets())!;
      expect(
        (t.version, t.proteinG, t.caloriesKcal, t.waterMl, t.stepTarget),
        (2, 160.0, 2600.0, 3000, 10000),
      );
      await w.expectCleanSync();
      expect(w.server.tables['personal_targets']!.length, 2);
    });
  });
}
