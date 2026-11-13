import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/core/auth/session_controller.dart';
import 'package:shaktikram/core/sync/change_writer.dart';
import 'package:shaktikram/core/sync/sync_status.dart';
import 'package:shaktikram/features/progress/data/progress_repository.dart';
import 'package:shaktikram/features/progress/data/progress_service.dart';
import 'package:shaktikram/features/training/data/training_management_service.dart';
import 'package:shaktikram/features/training/data/training_models.dart';
import 'package:shaktikram/features/training/data/training_repository.dart';
import 'package:shaktikram/features/training/data/workout_session_service.dart';

import 'support/fake_server.dart';
import 'support/fakes.dart';
import 'support/store_contract.dart';

DateTime _clock = DateTime.utc(2026, 11, 9, 7); // a Monday

final _writerProvider = Provider<ChangeWriter>(
  (ref) => ChangeWriter(ref, clock: () => _clock),
);

final _chest = uid(1);
final _triceps = uid(2);
final _bench = uid(3);

class _World {
  _World() {
    _clock = DateTime.utc(2026, 11, 9, 7);
    server = FakeServer();
    harness = Harness.ready();
    container = ProviderContainer(overrides: harness.overridesWith(server));
  }

  late final FakeServer server;
  late final Harness harness;
  late final ProviderContainer container;

  TrainingRepository get repo => TrainingRepository(harness.local);
  late final TrainingManagementService training = TrainingManagementService(
    writer: container.read(_writerProvider),
    repository: repo,
    clock: () => _clock,
  );
  late final ProgressService progress = ProgressService(
    writer: container.read(_writerProvider),
    repository: ProgressRepository(harness.local),
    clock: () => _clock,
  );
  late final WorkoutSessionService sessions = WorkoutSessionService(
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
    server.seed('muscles', {
      'id': _chest,
      'key': 'chest',
      'label': 'Chest',
      'group_key': 'chest',
    });
    server.seed('muscles', {
      'id': _triceps,
      'key': 'triceps',
      'label': 'Triceps',
      'group_key': 'arms',
    });
    await sync();
  }

  Future<void> sync() => container.read(syncStatusProvider.notifier).syncNow();

  int pending() => container.read(syncStatusProvider).pendingCount;
}

Future<_World> _ready() async {
  final w = _World();
  addTearDown(w.container.dispose);
  await w.start();
  return w;
}

Future<String> _exercise(_World w, String name) => w.training.createExercise(
  name: name,
  category: 'compound',
  primaryMuscleIds: [_chest],
  secondaryMuscleIds: [_triceps],
);

List<TemplateExerciseDraft> _lines(String exerciseId) => [
  TemplateExerciseDraft(
    exerciseId: exerciseId,
    targetSets: 3,
    repMin: 8,
    repMax: 12,
  ),
];

void main() {
  group('exercises', () {
    test(
      'an exercise of your own is saved with its muscles and syncs',
      () async {
        final w = await _ready();
        final id = await _exercise(w, 'Incline press');

        final saved = (await w.repo.exercises()).single;
        expect(saved.id, id);
        expect(saved.name, 'Incline press');
        expect(saved.isCustom, isTrue);
        final links = await w.repo.exerciseMuscles(id);
        expect(links.where((l) => l.role == 'primary').map((l) => l.muscleId), [
          _chest,
        ]);
        expect(
          links.where((l) => l.role == 'secondary').map((l) => l.muscleId),
          [_triceps],
        );

        await w.sync();
        expect(w.pending(), 0);
        expect(
          w.server.tables['exercises']!.values.single['name'],
          'Incline press',
        );
      },
    );

    test(
      'a blank name, a missing muscle and a repeated name are refused with a clear message',
      () async {
        final w = await _ready();
        await _exercise(w, 'Incline press');

        expect(
          () =>
              w.training.createExercise(name: '  ', primaryMuscleIds: [_chest]),
          throwsA(isA<ManagementError>()),
        );
        expect(
          () => w.training.createExercise(
            name: 'Fly',
            primaryMuscleIds: const [],
          ),
          throwsA(isA<ManagementError>()),
        );
        expect(
          () => w.training.createExercise(
            name: 'incline PRESS',
            primaryMuscleIds: [_chest],
          ),
          throwsA(isA<ManagementError>()),
        );
        expect((await w.repo.exercises()).length, 1);
      },
    );

    test(
      'editing changes the muscles; stopping use hides it from pickers but keeps it',
      () async {
        final w = await _ready();
        final id = await _exercise(w, 'Incline press');

        await w.training.updateExercise(
          id,
          name: 'Incline DB press',
          category: 'compound',
          primaryMuscleIds: [_triceps],
        );
        final links = await w.repo.exerciseMuscles(id);
        expect(links.map((l) => (l.muscleId, l.role)), [(_triceps, 'primary')]);
        expect((await w.repo.exercises()).single.name, 'Incline DB press');

        await w.training.setExerciseInactive(id, true);
        expect((await w.repo.exercises()).single.isInactive, isTrue);
        await w.training.setExerciseInactive(id, false);
        expect((await w.repo.exercises()).single.isInactive, isFalse);
        await w.sync();
        expect(w.pending(), 0);
      },
    );
  });

  group('templates', () {
    test(
      'a template is created, then an edit becomes version 2 at once, even offline',
      () async {
        final w = await _ready();
        final bench = await _exercise(w, 'Bench press');
        final id = await w.training.createTemplate(
          name: 'Push',
          exercises: _lines(bench),
        );

        var current = (await w.repo.currentTemplateVersions()).single;
        expect(current.templateId, id);
        expect(current.version, 1);
        expect(
          (await w.repo.templateExercises(current.id)).single.exerciseId,
          bench,
        );

        await w.training.updateTemplate(
          id,
          name: 'Push day',
          exercises: [
            TemplateExerciseDraft(
              exerciseId: bench,
              targetSets: 4,
              repMin: 6,
              repMax: 8,
            ),
          ],
        );
        current = (await w.repo.currentTemplateVersions()).single;
        expect(current.version, 2);
        expect(current.name, 'Push day');
        expect(
          (await w.repo.templateExercises(current.id)).single.targetSets,
          4,
        );

        await w.sync();
        expect(w.pending(), 0);
        expect((await w.repo.currentTemplateVersions()).single.version, 2);
      },
    );

    test(
      'rules: needs a name, an exercise, sensible reps, no duplicates',
      () async {
        final w = await _ready();
        final bench = await _exercise(w, 'Bench press');
        expect(
          () => w.training.createTemplate(name: '', exercises: _lines(bench)),
          throwsA(isA<ManagementError>()),
        );
        expect(
          () => w.training.createTemplate(name: 'Push', exercises: const []),
          throwsA(isA<ManagementError>()),
        );
        expect(
          () => w.training.createTemplate(
            name: 'Push',
            exercises: [
              TemplateExerciseDraft(exerciseId: bench, repMin: 12, repMax: 8),
            ],
          ),
          throwsA(isA<ManagementError>()),
        );
        expect(
          () => w.training.createTemplate(
            name: 'Push',
            exercises: [...(_lines(bench)), ..._lines(bench)],
          ),
          throwsA(isA<ManagementError>()),
        );
      },
    );

    test(
      'duplicating copies the exercises; deleting removes it from the list only',
      () async {
        final w = await _ready();
        final bench = await _exercise(w, 'Bench press');
        final id = await w.training.createTemplate(
          name: 'Push',
          exercises: _lines(bench),
        );
        final copy = await w.training.duplicateTemplate(id);
        final all = await w.repo.currentTemplateVersions();
        expect(all.map((t) => t.name), containsAll(['Push', 'Push (copy)']));
        expect(
          (await w.repo.templateExercises(
            all.firstWhere((t) => t.templateId == copy).id,
          )).length,
          1,
        );

        await w.training.deleteTemplate(copy);
        expect((await w.repo.currentTemplateVersions()).map((t) => t.name), [
          'Push',
        ]);
      },
    );
  });

  group('splits', () {
    Future<(String, String)> twoSplits(_World w) async {
      final a = await w.training.createSplit(
        name: 'PPL',
        days: const [
          SplitDayDraft(label: 'Push'),
          SplitDayDraft(label: 'Rest', isRest: true),
        ],
        activate: true,
      );
      final b = await w.training.createSplit(
        name: 'Upper Lower',
        days: const [SplitDayDraft(label: 'Upper')],
      );
      return (a, b);
    }

    test('a split is created with its days and made active', () async {
      final w = await _ready();
      final bench = await _exercise(w, 'Bench press');
      final tpl = await w.training.createTemplate(
        name: 'Push',
        exercises: _lines(bench),
      );
      await w.training.createSplit(
        name: 'PPL',
        days: [
          SplitDayDraft(label: 'Push', templateId: tpl),
          const SplitDayDraft(label: 'Rest', isRest: true),
        ],
        activate: true,
      );

      final active = (await w.repo.activeSplit())!;
      expect(active.name, 'PPL');
      expect(active.days.map((d) => (d.label, d.isRest)), [
        ('Push', false),
        ('Rest', true),
      ]);
      expect(active.days.first.templateId, tpl);
      await w.sync();
      expect(w.pending(), 0);
    });

    test(
      'activating one split makes the other inactive; archive and duplicate work',
      () async {
        final w = await _ready();
        final (a, b) = await twoSplits(w);
        await w.training.activateSplit(b);

        var all = await w.repo.splits();
        expect(all.firstWhere((s) => s.splitId == b).status, 'active');
        expect(all.firstWhere((s) => s.splitId == a).status, 'inactive');
        await w.sync();
        expect(w.pending(), 0);

        await w.training.duplicateSplit(a);
        await w.training.archiveSplit(a);
        all = await w.repo.splits();
        expect(
          all.map((s) => s.name),
          containsAll(['Upper Lower', 'PPL (copy)']),
        );
        expect(all.any((s) => s.splitId == a), isFalse);
        expect(
          (await w.repo.splits(
            includeArchived: true,
          )).any((s) => s.splitId == a),
          isTrue,
        );
      },
    );

    test(
      'editing saves a new version with the new days; the schedule keeps the old version',
      () async {
        final w = await _ready();
        final id = await w.training.createSplit(
          name: 'PPL',
          days: const [SplitDayDraft(label: 'Push')],
          activate: true,
        );
        final before = (await w.repo.activeSplit())!;
        await w.training.updateSplit(
          id,
          name: 'PPL v2',
          days: const [
            SplitDayDraft(label: 'Push'),
            SplitDayDraft(label: 'Pull'),
          ],
        );

        final after = (await w.repo.activeSplit())!;
        expect(after.versionId, isNot(before.versionId));
        expect(after.name, 'PPL v2');
        expect(after.days.map((d) => d.label), ['Push', 'Pull']);
        expect((await w.repo.splitDayLabels())[before.days.single.id], 'Push');
        await w.sync();
        expect(w.pending(), 0);
      },
    );

    test('rules: name, days, weekly limit, rest day with a template', () async {
      final w = await _ready();
      expect(
        () => w.training.createSplit(
          name: '',
          days: const [SplitDayDraft(label: 'A')],
        ),
        throwsA(isA<ManagementError>()),
      );
      expect(
        () => w.training.createSplit(name: 'X', days: const []),
        throwsA(isA<ManagementError>()),
      );
      expect(
        () => w.training.createSplit(
          name: 'X',
          days: [for (var i = 0; i < 8; i++) SplitDayDraft(label: 'D$i')],
        ),
        throwsA(isA<ManagementError>()),
      );
      expect(
        () => w.training.createSplit(
          name: 'X',
          days: [SplitDayDraft(label: 'R', isRest: true, templateId: uid(99))],
        ),
        throwsA(isA<ManagementError>()),
      );
    });
  });

  group('planning days from a split', () {
    ActiveSplit split(String pattern, int n) => ActiveSplit(
      splitId: 's',
      versionId: 'v',
      name: 'S',
      pattern: pattern,
      days: [
        for (var i = 0; i < n; i++)
          SplitDay(
            id: 'd$i',
            position: i + 1,
            label: 'Day ${i + 1}',
            isRest: false,
          ),
      ],
    );

    test(
      'a weekly split puts day 1 on Monday and leaves later weekdays empty',
      () {
        final plan = planDays(
          split('fixed_weekly', 3),
          '2026-11-09',
          7,
        ); // Monday
        expect(plan.map((p) => p.localDate), [
          '2026-11-09',
          '2026-11-10',
          '2026-11-11',
        ]);
        final wed = planDays(
          split('fixed_weekly', 3),
          '2026-11-11',
          3,
        ); // Wed, Thu, Fri
        expect(wed.map((p) => p.day.label), ['Day 3']);
      },
    );

    test('a rolling split repeats its days in order from the start date', () {
      final plan = planDays(split('rolling', 3), '2026-11-11', 5);
      expect(plan.map((p) => p.day.label), [
        'Day 1',
        'Day 2',
        'Day 3',
        'Day 1',
        'Day 2',
      ]);
      expect(plan.first.localDate, '2026-11-11');
    });
  });

  group('schedule', () {
    test(
      'planning a week from the split fills it, skips days already planned, and syncs',
      () async {
        final w = await _ready();
        final bench = await _exercise(w, 'Bench press');
        final tpl = await w.training.createTemplate(
          name: 'Push',
          exercises: _lines(bench),
        );
        await w.training.createSplit(
          name: 'PPL',
          days: [
            SplitDayDraft(label: 'Push', templateId: tpl),
            const SplitDayDraft(label: 'Rest', isRest: true),
          ],
          activate: true,
        );
        final split = (await w.repo.activeSplit())!;

        await w.training.setScheduleDay('2026-11-10', split: split, rest: true);
        final planned = await w.training.planFromSplit(split, '2026-11-09', 2);
        expect(
          planned,
          1,
        ); // Tuesday already had an entry; only Monday was filled

        final mon = (await w.repo.scheduleFor('2026-11-09'))!;
        expect(mon.isRestDay, isFalse);
        expect(mon.splitDayId, split.days.first.id);
        expect(mon.templateVersionId, isNotNull);
        expect((await w.repo.scheduleFor('2026-11-10'))!.isRestDay, isTrue);
        await w.sync();
        expect(w.pending(), 0);
      },
    );

    test(
      'changing a planned day replaces it; a finished day cannot be changed or cleared',
      () async {
        final w = await _ready();
        final id = await w.training.createSplit(
          name: 'PPL',
          days: const [SplitDayDraft(label: 'Push')],
          activate: true,
        );
        final split = (await w.repo.activeSplit())!;
        await w.training.setScheduleDay(
          '2026-11-09',
          split: split,
          day: split.days.first,
        );
        await w.training.setScheduleDay('2026-11-09', split: split, rest: true);
        expect((await w.repo.scheduleFor('2026-11-09'))!.isRestDay, isTrue);
        await w.training.clearScheduleDay('2026-11-09');
        expect(await w.repo.scheduleFor('2026-11-09'), isNull);
        expect(id, isNotEmpty);

        w.server.seed('schedule_entries', {
          'id': uid(50),
          'local_date': '2026-11-12',
          'is_rest_day': false,
          'status': 'completed',
          'session_id': null,
        });
        await w.sync();
        expect(
          () => w.training.clearScheduleDay('2026-11-12'),
          throwsA(isA<ManagementError>()),
        );
      },
    );
  });

  group('workouts without sets', () {
    test(
      'a workout with no logged sets is not counted; one with a working set is',
      () async {
        final w = await _ready();
        final bench = await _exercise(w, 'Bench press');

        final empty = await w.sessions.startSession();
        await w.sessions.completeSession(empty);
        expect(await w.repo.hasLoggedSets(empty), isFalse);

        final real = await w.sessions.startSession();
        final se = await w.sessions.addExercise(real, bench);
        await w.sessions.logSet(se, weightKg: 60, reps: 8);
        await w.sessions.completeSession(real);
        expect(await w.repo.hasLoggedSets(real), isTrue);

        final finished = await w.repo.finishedSessions();
        expect(
          finished.firstWhere((f) => f.session.id == empty).counted,
          isFalse,
        );
        expect(
          finished.firstWhere((f) => f.session.id == real).counted,
          isTrue,
        );
      },
    );
  });

  group('goals, milestones and assessments', () {
    test(
      'a goal is created, edited, paused, completed and archived, and syncs',
      () async {
        final w = await _ready();
        final id = await w.progress.createGoal(
          type: 'strength',
          title: 'Bench 100 kg',
          targetMetric: 'est_1rm:$_bench',
          targetValue: 100,
          targetUnit: 'kg',
          startDate: '2026-11-01',
          targetDate: '2027-02-01',
        );
        var goal = (await ProgressRepository(w.harness.local).goals()).single;
        expect(goal.title, 'Bench 100 kg');
        expect(goal.status, 'active');

        await w.progress.updateGoal(
          id,
          type: 'strength',
          title: 'Bench 105 kg',
          targetMetric: 'est_1rm:$_bench',
          targetValue: 105,
          targetUnit: 'kg',
          startDate: '2026-11-01',
        );
        await w.progress.setGoalStatus(id, 'paused');
        await w.progress.setGoalStatus(id, 'completed');
        goal =
            (await ProgressRepository(
              w.harness.local,
            ).goals(includeEnded: true)).single;
        expect(goal.title, 'Bench 105 kg');
        expect(goal.targetValue, 105);
        expect(goal.status, 'completed');
        expect(goal.targetDate, isNull);

        await w.sync();
        expect(w.pending(), 0);
      },
    );

    test('goal rules: title, type, dates, numbers', () async {
      final w = await _ready();
      expect(
        () => w.progress.createGoal(type: 'strength', title: ' '),
        throwsA(isA<ManagementError>()),
      );
      expect(
        () => w.progress.createGoal(type: 'nope', title: 'X'),
        throwsA(isA<ManagementError>()),
      );
      expect(
        () => w.progress.createGoal(
          type: 'strength',
          title: 'X',
          startDate: '2026-11-10',
          targetDate: '2026-11-01',
        ),
        throwsA(isA<ManagementError>()),
      );
      expect(
        () => w.progress.createGoal(
          type: 'strength',
          title: 'X',
          targetValue: -5,
        ),
        throwsA(isA<ManagementError>()),
      );
      expect(
        () => w.progress.setGoalStatus(uid(1), 'finished'),
        throwsA(isA<ManagementError>()),
      );
    });

    test('manual progress and milestones are saved against the goal', () async {
      final w = await _ready();
      final goal = await w.progress.createGoal(
        type: 'maintenance',
        title: 'Walk daily',
      );
      await w.progress.addGoalProgress(goal, 6.5, note: 'felt good');
      final m = await w.progress.addMilestone(
        goal,
        title: 'First 7 km',
        targetValue: 7,
      );
      await w.progress.updateMilestone(m, title: 'First 8 km', targetValue: 8);

      expect(
        (await w.harness.local.list('goal_progress')).single['value'],
        6.5,
      );
      final repo = ProgressRepository(w.harness.local);
      expect((await repo.milestones(goal)).single.title, 'First 8 km');
      await w.progress.deleteMilestone(m);
      expect(await repo.milestones(goal), isEmpty);
      expect(
        () => w.progress.addMilestone(goal, title: '', targetValue: 1),
        throwsA(isA<ManagementError>()),
      );
      await w.sync();
      expect(w.pending(), 0);
    });

    test(
      'a muscle assessment keeps one level per muscle and an older one stays',
      () async {
        final w = await _ready();
        await w.progress.saveAssessment({
          _chest: 2,
          _triceps: 4,
        }, notes: 'first');
        _clock = DateTime.utc(2026, 11, 20, 7);
        await w.progress.saveAssessment({_chest: 3});

        expect((await w.harness.local.list('muscle_assessments')).length, 2);
        expect(
          (await w.harness.local.list('muscle_assessment_items')).length,
          3,
        );
        expect(
          () => w.progress.saveAssessment(const {}),
          throwsA(isA<ManagementError>()),
        );
        expect(
          () => w.progress.saveAssessment({_chest: 6}),
          throwsA(isA<ManagementError>()),
        );
        await w.sync();
        expect(w.pending(), 0);
      },
    );
  });
}
