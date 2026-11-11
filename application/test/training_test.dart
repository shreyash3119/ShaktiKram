import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/auth/session_controller.dart';
import 'package:shaktikram/core/sync/change_writer.dart';
import 'package:shaktikram/core/sync/sync_status.dart';
import 'package:shaktikram/core/time/local_stamp.dart';
import 'package:shaktikram/features/training/data/training_repository.dart';
import 'package:shaktikram/features/training/data/workout_session_service.dart';

import 'support/fake_server.dart';
import 'support/fakes.dart';
import 'support/store_contract.dart';

DateTime _clock = DateTime.utc(2026, 11, 10, 7);

final _writerProvider = Provider<ChangeWriter>((ref) => ChangeWriter(ref, clock: () => _clock));

final _bench = uid(1);
final _fly = uid(2);
final _tpl = uid(10);
final _tv1 = uid(11);
final _te1 = uid(12);
final _te2 = uid(13);
final _split = uid(20);
final _sv = uid(21);
final _sd1 = uid(22);
final _sd2 = uid(23);
final _schedule = uid(30);

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
  TrainingRepository get repo => TrainingRepository(harness.local);
  late final WorkoutSessionService service = WorkoutSessionService(
    writer: container.read(_writerProvider),
    repository: repo,
    clock: () => _clock,
  );

  Future<void> start() async {
    await server.registerDevice(id: 'device-1', label: 'Test phone', platform: 'mobile');
    container.read(sessionControllerProvider);
    await pumpEventQueue();
    expect(container.read(sessionControllerProvider).phase, SessionPhase.ready);
  }

  /// A plan as it would already be on the server: two exercises, a template, an active split and today's schedule.
  void seedPlan() {
    server.seed('exercises', {'id': _bench, 'name': 'Bench press', 'category': 'compound', 'is_custom': true});
    server.seed('exercises', {'id': _fly, 'name': 'Cable fly', 'category': 'isolation', 'is_custom': true});
    server.seed('workout_templates', {'id': _tpl});
    server.seed('template_versions', {
      'id': _tv1, 'entity_id': _tpl, 'version': 1, 'name': 'Chest day', 'effective_from': '2026-10-01T00:00:00Z', 'effective_to': null,
    });
    server.seed('template_exercises', {
      'id': _te1, 'template_version_id': _tv1, 'exercise_id': _bench, 'position': 1, 'target_sets': 3, 'rep_min': 10, 'rep_max': 12, 'start_weight_kg': 60,
    });
    server.seed('template_exercises', {
      'id': _te2, 'template_version_id': _tv1, 'exercise_id': _fly, 'position': 2, 'target_sets': 3, 'rep_min': 12, 'rep_max': 15,
    });
    server.seed('splits', {'id': _split, 'status': 'active'});
    server.seed('split_versions', {
      'id': _sv, 'entity_id': _split, 'version': 1, 'name': '4 day', 'pattern': 'fixed_weekly', 'effective_from': '2026-10-01T00:00:00Z', 'effective_to': null,
    });
    server.seed('split_days', {'id': _sd2, 'split_version_id': _sv, 'position': 2, 'label': 'Rest', 'is_rest': true});
    server.seed('split_days', {'id': _sd1, 'split_version_id': _sv, 'position': 1, 'label': 'Chest', 'is_rest': false, 'template_id': _tpl});
    server.seed('schedule_entries', {
      'id': _schedule, 'local_date': today, 'is_rest_day': false, 'split_version_id': _sv, 'split_day_id': _sd1, 'template_version_id': _tv1, 'status': 'planned',
    });
  }

  Future<void> sync() => container.read(syncStatusProvider.notifier).syncNow();

  int pending() => container.read(syncStatusProvider).pendingCount;
}

Future<_World> _ready({bool plan = true}) async {
  final w = _World();
  addTearDown(w.container.dispose);
  await w.start();
  if (plan) {
    w.seedPlan();
    await w.sync();
  }
  return w;
}

void main() {
  group('reading the plan from the phone', () {
    test('exercises, templates, split and schedule come from the local copy', () async {
      final w = await _ready();
      final repo = w.repo;

      expect((await repo.exercises()).map((e) => e.name), ['Bench press', 'Cable fly']);
      expect((await repo.currentTemplateVersions()).single.name, 'Chest day');
      expect((await repo.templateExercises(_tv1)).map((e) => e.exerciseId), [_bench, _fly]);
      final first = (await repo.templateExercises(_tv1)).first;
      expect((first.targetSets, first.repMin, first.repMax, first.startWeightKg), (3, 10, 12, 60.0));

      final split = (await repo.activeSplit())!;
      expect(split.name, '4 day');
      expect(split.days.map((d) => d.label), ['Chest', 'Rest']);
      expect(split.days.first.templateId, _tpl);
      expect((await repo.currentVersionOfTemplate(_tpl))!.id, _tv1);

      final entry = (await repo.scheduleFor(w.today))!;
      expect((entry.status, entry.templateVersionId), ('planned', _tv1));
      expect(await repo.scheduleFor('1999-01-01'), isNull);
    });

    test('nothing is shown for an empty phone', () async {
      final w = await _ready(plan: false);
      expect(await w.repo.exercises(), isEmpty);
      expect(await w.repo.activeSplit(), isNull);
      expect(await w.repo.activeSession(), isNull);
      expect(await w.repo.sessions(), isEmpty);
    });
  });

  group('a workout from start to finish', () {
    test('start from the plan, log sets, skip, pause, complete: works offline and syncs cleanly', () async {
      final w = await _ready();
      w.server.offline = true;
      final svc = w.service;

      final sessionId = await svc.startSession(
        name: 'Chest day',
        scheduleEntryId: _schedule,
        splitVersionId: _sv,
        splitDayId: _sd1,
        templateVersionId: _tv1,
      );
      final active = (await w.repo.activeSession())!;
      expect((active.id, active.status), (sessionId, 'in_progress'));
      final exercises = await w.repo.sessionExercises(sessionId);
      expect(exercises.map((e) => (e.exerciseId, e.position)), [(_bench, 1), (_fly, 2)]);
      await expectLater(svc.startSession(), throwsA(isA<SessionAlreadyActive>()));

      _clock = DateTime.utc(2026, 11, 10, 7, 5);
      final benchEx = exercises[0].id;
      await svc.logSet(benchEx, weightKg: 40, reps: 10, setType: 'warmup');
      await svc.logSet(benchEx, weightKg: 60, reps: 10, rir: 2, rpe: 8);
      await svc.logSet(benchEx, weightKg: 60, reps: 10);
      await svc.logSet(benchEx, weightKg: 60, reps: 8);
      await svc.skipExercise(exercises[1].id, reason: 'machine busy');

      _clock = DateTime.utc(2026, 11, 10, 7, 20);
      await svc.setPaused(sessionId, paused: true);
      expect((await w.repo.activeSession())!.status, 'paused');
      _clock = DateTime.utc(2026, 11, 10, 7, 25);
      await svc.setPaused(sessionId, paused: false, addPausedSeconds: 300);

      _clock = DateTime.utc(2026, 11, 10, 7, 55);
      await svc.completeSession(sessionId, postNotes: 'Felt strong');
      expect(await w.repo.activeSession(), isNull);

      final sets = await w.repo.sets(benchEx);
      expect(sets.map((s) => (s.setType, s.setNumber)), [('warmup', 1), ('working', 1), ('working', 2), ('working', 3)]);
      final summary = await w.repo.summary(sessionId);
      expect((summary.workingSets, summary.totalReps, summary.volumeKg), (3, 28, 1680.0));
      expect((summary.exercisesDone, summary.exercisesSkipped), (1, 1));
      expect(summary.durationSeconds, 55 * 60 - 300);
      expect(w.pending(), greaterThan(0));

      // The connection comes back.
      w.server.offline = false;
      await w.sync();
      expect(w.pending(), 0);
      expect(await w.harness.local.issueCount(), 0, reason: (await w.harness.local.issues()).map((i) => '${i.entity}: ${i.errorCode} ${i.message}').join('; '));

      final session = w.server.row('workout_sessions', sessionId)!;
      expect(session['status'], 'completed');
      expect(session['ended_at'], _clock.toIso8601String());
      expect(session['paused_seconds'], 300);
      expect(session['post_notes'], 'Felt strong');
      expect(w.server.tables['sets']!.length, 4);
      expect(w.server.tables['session_exercises']!.length, 2);
      expect(w.server.row('session_exercises', exercises[1].id)!['skip_reason'], 'machine busy');
      final entry = w.server.row('schedule_entries', _schedule)!;
      expect((entry['status'], entry['session_id']), ('completed', sessionId));

      // Reading back after the server's copy has been pulled gives the same totals.
      final again = await w.repo.summary(sessionId);
      expect((again.workingSets, again.totalReps, again.volumeKg), (3, 28, 1680.0));
      expect((await w.repo.sessionDetail(sessionId))!.exercises.first.exercise.prescription, isNotNull,
          reason: 'the server copies the prescription when the exercise comes from a template');
    });

    test('sets can be corrected and deleted, and a freed set number can be used again', () async {
      final w = await _ready();
      final id = await w.service.startSession(templateVersionId: _tv1);
      final ex = (await w.repo.sessionExercises(id)).first.id;
      final a = await w.service.logSet(ex, weightKg: 60, reps: 10);
      final b = await w.service.logSet(ex, weightKg: 60, reps: 9);
      await w.sync();
      expect(w.pending(), 0);

      await w.service.editSet(a, reps: 11);
      await w.service.deleteSet(b);
      await w.service.logSet(ex, weightKg: 62.5, reps: 8);
      await w.sync();
      expect(await w.harness.local.issueCount(), 0, reason: (await w.harness.local.issues()).map((i) => '${i.errorCode} ${i.message}').join('; '));
      expect(w.server.row('sets', a)!['reps'], 11);
      expect(w.server.row('sets', b)!['deleted_at'], isNotNull);
      final shown = await w.repo.sets(ex);
      expect(shown.map((s) => (s.setNumber, s.weightKg)), [(1, 60.0), (2, 62.5)], reason: 'the deleted set 2 frees its number, and the server accepts that');
    });

    test('correcting a set before it has reached the server still works', () async {
      final w = await _ready();
      w.server.offline = true;
      final id = await w.service.startSession(templateVersionId: _tv1);
      final ex = (await w.repo.sessionExercises(id)).first.id;
      final set = await w.service.logSet(ex, weightKg: 60, reps: 10);
      await w.service.editSet(set, reps: 12);
      w.server.offline = false;
      await w.sync();
      expect(await w.harness.local.issueCount(), 0);
      expect(w.server.row('sets', set)!['reps'], 12);
    });

    test('exercises can be added, skipped, restored and removed', () async {
      final w = await _ready();
      final id = await w.service.startSession();
      final added = await w.service.addExercise(id, _fly);
      await w.service.logSet(added, weightKg: 20, reps: 12);
      await w.service.skipExercise(added, reason: 'tired');
      expect((await w.repo.sessionExerciseById(added))!.isSkipped, isTrue);
      await w.service.restoreExercise(added);
      expect((await w.repo.sessionExerciseById(added))!.status, 'added');
      await w.sync();
      expect(w.server.row('session_exercises', added)!['skip_reason'], isNull);

      await w.service.removeExercise(added);
      expect(await w.repo.sessionExercises(id), isEmpty);
      await w.sync();
      expect(await w.harness.local.issueCount(), 0);
      expect(w.server.row('session_exercises', added)!['deleted_at'], isNotNull);
    });

    test('completing marks exercises with no sets as not done', () async {
      final w = await _ready();
      final id = await w.service.startSession(templateVersionId: _tv1);
      final ex = await w.repo.sessionExercises(id);
      await w.service.logSet(ex.first.id, weightKg: 60, reps: 10);
      _clock = DateTime.utc(2026, 11, 10, 8);
      await w.service.completeSession(id);
      final after = await w.repo.sessionExercises(id);
      expect(after.map((e) => e.status), ['done', 'skipped']);
      expect(after.last.skipReason, 'Not done');
      await w.sync();
      expect(await w.harness.local.issueCount(), 0);
    });

    test('discarding removes the workout, its exercises and sets', () async {
      final w = await _ready();
      final id = await w.service.startSession(templateVersionId: _tv1);
      final ex = (await w.repo.sessionExercises(id)).first.id;
      final set = await w.service.logSet(ex, weightKg: 60, reps: 10);
      await w.sync();
      await w.service.discardSession(id);
      expect(await w.repo.activeSession(), isNull);
      expect(await w.repo.sessions(), isEmpty);
      await w.sync();
      expect(await w.harness.local.issueCount(), 0);
      expect(w.server.row('workout_sessions', id)!['deleted_at'], isNotNull);
      expect(w.server.row('sets', set)!['deleted_at'], isNotNull);
    });

    test('values the database would refuse are caught before anything is saved', () async {
      final w = await _ready();
      final id = await w.service.startSession(templateVersionId: _tv1);
      final ex = (await w.repo.sessionExercises(id)).first.id;
      await expectLater(w.service.logSet(ex, weightKg: 60, reps: 10, rpe: 7.3), throwsArgumentError);
      await expectLater(w.service.logSet(ex, weightKg: -1, reps: 10), throwsArgumentError);
      await expectLater(w.service.logSet(ex, weightKg: 60, reps: -2), throwsArgumentError);
      await expectLater(w.service.logSet(ex, weightKg: 60, reps: 10, rir: 11), throwsArgumentError);
      await expectLater(w.service.logSet(ex, weightKg: 60, reps: 10, setType: 'drop'), throwsArgumentError);
      expect(await w.repo.sets(ex), isEmpty);
    });
  });

  group('history', () {
    test('sessions are newest first and the previous performance of an exercise is found', () async {
      final w = await _ready();
      final first = await w.service.startSession(templateVersionId: _tv1);
      final firstEx = (await w.repo.sessionExercises(first)).first.id;
      await w.service.logSet(firstEx, weightKg: 60, reps: 10);
      await w.service.logSet(firstEx, weightKg: 60, reps: 9);
      _clock = DateTime.utc(2026, 11, 10, 8);
      await w.service.completeSession(first);

      _clock = DateTime.utc(2026, 11, 12, 7);
      final second = await w.service.startSession(templateVersionId: _tv1);
      final previous = (await w.repo.previousPerformance(_bench, beforeSessionId: second))!;
      expect(previous.sessionId, first);
      expect(previous.workingSets.map((s) => s.reps), [10, 9]);
      expect(await w.repo.previousPerformance(_fly, beforeSessionId: second), isNull, reason: 'the fly was not done (marked not done)');
      expect(await w.repo.previousPerformance(_bench, beforeSessionId: first), isNull);

      _clock = DateTime.utc(2026, 11, 12, 8);
      await w.service.completeSession(second);
      expect((await w.repo.sessions()).map((s) => s.id), [second, first]);
      expect((await w.repo.sessions(limit: 1)).single.id, second);
      expect((await w.repo.sessionDetail(first))!.summary.volumeKg, 1140.0);
      await w.sync();
      expect(await w.harness.local.issueCount(), 0);
    });
  });
}
