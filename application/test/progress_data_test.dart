import 'package:flutter_test/flutter_test.dart';
import 'package:shaktikram/features/progress/data/progress_models.dart';
import 'package:shaktikram/features/progress/data/progress_repository.dart';

import 'support/memory_local_store.dart';
import 'support/store_contract.dart';

/// Shaped like the answer of `api_daily_briefing` (backend `20261109000600_stage4_api.sql`).
Map<String, dynamic> _briefingJson() => {
  'date': '2026-11-12',
  'plan': {
    'status': 'planned',
    'is_rest_day': false,
    'template_name': 'Push A',
    'planned_exercises': 5,
    'is_break_day': false,
    'active_split': 'PPL',
  },
  'readiness': {
    'level': 'moderate',
    'wellness_score': 62.5,
    'reason_codes': ['low_sleep'],
    'reasoning': ['You logged 5.5 hours of sleep.'],
    'value_kind': 'suggestion',
    'note': 'Decision support only.',
    'date': '2026-11-12',
    'context': {
      'last_session_date': '2026-11-10',
      'days_since_last_session': 2,
      'sessions_last_7_days': 3,
    },
  },
  'restriction_warnings': [
    {'exercise_id': 'e1', 'kind': 'avoid'},
  ],
  'next_targets': [
    {'exercise_id': 'e1', 'action': 'increase', 'suggested_weight_kg': 62.5},
  ],
  'supplements_today': [
    {
      'supplement_id': 's1',
      'name': 'Creatine',
      'expected_doses': 1,
      'taken_today': 0,
    },
  ],
  'hydration': {
    'local_date': '2026-11-12',
    'total_ml': 1500,
    'target_ml': 3000,
  },
  'water_target_ml': 3000,
  'nutrition': {
    'eaten_protein_g': 92.5,
    'protein_target_g': 150,
    'eaten_calories_kcal': 1800,
  },
  'steps': {'steps': 4200, 'target': 10000},
  'reassessment': {'is_due': true, 'next_due_date': '2026-11-16'},
  'deload': {
    'level': 'watch',
    'reasoning': ['Fatigue was high on 4 of the last 10 check-ins.'],
    'value_kind': 'suggestion',
  },
  'goals': {'on_track': 2, 'behind': 1},
  'streak': {'current_streak': 4, 'longest_streak': 9},
  'recent_records': [
    {
      'kind': 'max_weight',
      'exercise': 'Bench press',
      'value': 85,
      'achieved_on': '2026-11-10',
    },
  ],
  'trends': [
    {
      'exercise': 'Squat',
      'signal': 'plateau',
      'change_pct': 0.4,
      'value_kind': 'observation',
    },
  ],
  'weak_points': {
    'rear_delts': {
      'muscle_key': 'rear_delts',
      'category': 'weak',
      'priority': 'high',
      'direct_sets_28d': 3,
      'suggestions': [
        {
          'exercise_id': 'x',
          'exercise_name': 'Face pull',
          'in_current_split': true,
        },
      ],
    },
  },
};

void main() {
  group('DailyBriefing', () {
    test('reads every section the server sends', () {
      final b = DailyBriefing.fromJson(_briefingJson());
      expect(
        (b.plan.templateName, b.plan.plannedExercises, b.plan.activeSplit),
        ('Push A', 5, 'PPL'),
      );
      expect(
        (
          b.readiness!.level,
          b.readiness!.wellnessScore,
          b.readiness!.reasoning.single,
        ),
        ('moderate', 62.5, 'You logged 5.5 hours of sleep.'),
      );
      expect(
        (
          b.readinessContext!.daysSinceLastSession,
          b.readinessContext!.sessionsLast7Days,
        ),
        (2, 3),
      );
      expect(b.deload!.level, 'watch');
      expect(
        (b.hydrationMl, b.waterTargetMl, b.steps, b.stepTarget),
        (1500, 3000, 4200, 10000),
      );
      expect((b.eatenProteinG, b.proteinTargetG), (92.5, 150.0));
      expect((b.reassessmentDue, b.nextReassessmentDate), (true, '2026-11-16'));
      expect((b.currentStreak, b.longestStreak), (4, 9));
      expect(b.goalCounts, {'on_track': 2, 'behind': 1});
      expect(
        (b.recentRecords.single.exercise, b.recentRecords.single.value),
        ('Bench press', 85.0),
      );
      expect(b.trends.single.signal, 'plateau');
      expect(b.supplements.single.name, 'Creatine');
      expect(b.restrictionWarnings, hasLength(1));
      expect(b.nextTargets, hasLength(1));
      expect(b.weakPoints.single.suggestions, ['Face pull']);
    });

    test('sections the server leaves out are empty, not errors', () {
      final b = DailyBriefing.fromJson({'date': '2026-11-12'});
      expect(
        (b.readiness, b.deload, b.currentStreak, b.hydrationMl, b.steps),
        (null, null, null, null, null),
      );
      expect(b.recentRecords, isEmpty);
      expect(b.trends, isEmpty);
      expect(b.weakPoints, isEmpty);
      expect(b.supplements, isEmpty);
      expect(b.goalCounts, isEmpty);
      expect((b.plan.isRestDay, b.reassessmentDue), (false, false));
    });

    test(
      'weak points also read from a list, and numbers may arrive as text',
      () {
        final b = DailyBriefing.fromJson({
          'date': 'd',
          'weak_points': [
            {'muscle_key': 'abs', 'direct_sets_28d': '2', 'suggestions': []},
          ],
          'steps': {'steps': '900', 'target': 8000},
        });
        expect(
          (
            b.weakPoints.single.muscleKey,
            b.weakPoints.single.directSets28d,
            b.steps,
          ),
          ('abs', 2, 900),
        );
      },
    );
  });

  group('view rows', () {
    test(
      'trend, goal progress and body composition rows keep the server values',
      () {
        final t = ExerciseTrend.fromJson({
          'exercise_id': 'e1',
          'signal': 'improving',
          'change_pct': '3.5',
          'sessions_considered': 4,
          'last_session_date': '2026-11-10',
        });
        expect(
          (t.signal, t.changePct, t.sessionsConsidered),
          ('improving', 3.5, 4),
        );
        final g = GoalProgress.fromJson({
          'goal_id': 'g1',
          'title': 'Bench 90',
          'goal_status': 'active',
          'progress_status': 'on_track',
          'progress_pct': 80,
          'reached': false,
          'current_value': 85,
          'target_value': 90,
        });
        expect(
          (g.progressPct, g.currentValue, g.reached, g.progressStatus),
          (80.0, 85.0, false, 'on_track'),
        );
        final c = BodyComposition.fromJson({
          'local_date': '2026-11-02',
          'body_fat_pct': 18.2,
          'weight_kg': 78,
          'fat_mass_kg': 14.2,
          'lean_mass_kg': 63.8,
          'method': 'smart_scale_bia',
        });
        expect((c.fatMassKg, c.leanMassKg), (14.2, 63.8));
        expect(ExerciseTrend.fromJson({}).signal, 'insufficient_data');
      },
    );
  });

  group('ProgressRepository', () {
    test(
      'reads records, achievements and goals that arrived by sync, newest first',
      () async {
        final store = MemoryLocalStore();
        await store.applyPulled([
          pulled('personal_records', 1, {
            'id': uid(1),
            'kind': 'max_weight',
            'value': 80,
            'achieved_on': '2026-10-27',
            'session_id': uid(50),
            'exercise_id': uid(60),
          }),
          pulled('personal_records', 2, {
            'id': uid(2),
            'kind': 'est_1rm',
            'value': 101.5,
            'achieved_on': '2026-11-02',
            'session_id': uid(51),
            'exercise_id': uid(60),
            'previous_value': 99,
          }),
          pulled('personal_records', 3, {
            'id': uid(3),
            'kind': 'max_weight',
            'value': 120,
            'achieved_on': '2026-11-03',
            'session_id': uid(52),
            'exercise_id': uid(61),
          }),
          pulled('achievements', 4, {
            'id': uid(4),
            'kind': 'workouts_completed',
            'threshold': 10,
            'title': '10 workouts',
            'achieved_on': '2026-11-01',
          }),
          pulled('goals', 5, {
            'id': uid(5),
            'type': 'strength',
            'title': 'Bench 90 kg',
            'status': 'active',
            'start_date': '2026-10-01',
            'target_value': 90,
          }),
          pulled('goals', 6, {
            'id': uid(6),
            'type': 'cutting',
            'title': 'Old cut',
            'status': 'abandoned',
            'start_date': '2026-01-01',
          }),
          pulled('goals', 7, {
            'id': uid(7),
            'type': 'consistency',
            'title': 'Done one',
            'status': 'completed',
            'start_date': '2026-05-01',
          }),
          pulled('milestones', 8, {
            'id': uid(8),
            'goal_id': uid(5),
            'title': '85 kg',
            'target_value': 85,
          }),
          pulled('milestones', 9, {
            'id': uid(9),
            'goal_id': uid(5),
            'title': '80 kg',
            'target_value': 80,
          }),
        ], 9);
        final repo = ProgressRepository(store);

        final all = await repo.personalRecords();
        expect(all.map((r) => r.achievedOn), [
          '2026-11-03',
          '2026-11-02',
          '2026-10-27',
        ]);
        expect(
          (await repo.personalRecords(exerciseId: uid(60))).map((r) => r.kind),
          ['est_1rm', 'max_weight'],
        );
        expect((await repo.personalRecords(limit: 1)).single.value, 120);
        expect((await repo.achievements()).single.threshold, 10);
        expect((await repo.goals()).map((g) => g.title), [
          'Bench 90 kg',
          'Done one',
        ]);
        expect((await repo.goals(includeEnded: true)), hasLength(3));
        expect((await repo.milestones(uid(5))).map((m) => m.title), [
          '80 kg',
          '85 kg',
        ]);
      },
    );
  });
}
