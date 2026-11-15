import 'dart:io';

import 'package:shaktikram/core/backend/report_error.dart';
import 'package:shaktikram/core/backend/reporting_gateway.dart';

/// A summary shaped like the real `GET /api/v1/reports/summary` answer.
Map<String, dynamic> summaryJson({
  bool compare = false,
  int sessions = 2,
  String label = 'November 2026',
}) => {
  'period': {
    'kind': 'monthly',
    'label': label,
    'start': '2026-11-01',
    'end': '2026-11-30',
    'days': 30,
  },
  'training': {
    'sessions': sessions,
    'volume_kg': 12450,
    'working_sets': 24,
    'total_reps': 210,
    'avg_duration_min': 62.5,
    'weekly': [
      {'week_start': '2026-11-02', 'sessions': 1, 'volume_kg': 6000},
      {'week_start': '2026-11-09', 'sessions': 1, 'volume_kg': 6450.5},
    ],
    'attendance': {
      'scheduled': 8,
      'completed': 6,
      'missed': 1,
      'break_days': 1,
      'consistency_pct': 85.7,
      'weekly': [
        {
          'week_start': '2026-11-02',
          'scheduled': 4,
          'completed': 3,
          'missed': 1,
          'break_days': 0,
          'consistency_pct': 75,
        },
      ],
    },
  },
  'strength': {
    'value_kind': 'estimated',
    'exercises': [
      {
        'exercise': 'Bench press',
        'sessions': 2,
        'first_e1rm_kg': 100,
        'last_e1rm_kg': 105,
        'top_weight_kg': 90,
        'volume_kg': 3000,
        'e1rm_change_pct': 5.0,
      },
    ],
    'e1rm_series': {
      'Bench press': [
        {'date': '2026-11-03', 'e1rm_kg': 100},
        {'date': '2026-11-10', 'e1rm_kg': 105},
      ],
    },
    'records': [
      {
        'achieved_on': '2026-11-10',
        'exercise': 'Bench press',
        'kind': 'max_weight',
        'value': 90,
        'previous_value': 85,
        'weight_kg': 90,
        'reps': 5,
      },
    ],
  },
  'body': {
    'value_kind': 'estimated',
    'measurements': [
      {
        'measurement_type': 'waist',
        'label': 'Waist',
        'unit': 'cm',
        'method': 'tape',
        'n': 2,
        'first_value': 84,
        'last_value': 83,
        'change': -1,
      },
    ],
    'weight_series': [
      {'date': '2026-11-01', 'value': 80.2},
      {'date': '2026-11-15', 'value': 79.6},
    ],
    'composition': [
      {
        'date': '2026-11-05',
        'method': 'scale',
        'body_fat_pct': 18.5,
        'weight_kg': 80,
        'fat_mass_kg': 14.8,
        'lean_mass_kg': 65.2,
      },
    ],
  },
  'muscles': {
    'value_kind': 'user_assessment',
    'ratings': [
      {
        'muscle_key': 'chest',
        'assessments': 2,
        'first_level': 3,
        'last_level': 4,
        'assessment_change': 'higher_rating',
      },
    ],
    'priority_changes': [
      {'muscle_key': 'chest', 'priority': 'high', 'from_date': '2026-11-02'},
    ],
    'training_exposure': [
      {'muscle_key': 'chest', 'direct_sets': 12, 'indirect_sets': 6},
    ],
  },
  'injuries': {
    'injuries': [
      {
        'name': 'Left shoulder',
        'body_region_key': 'shoulder',
        'side': 'left',
        'status': 'active',
        'severity': 'mild',
        'start_date': '2026-10-20',
        'latest_pain_level': 4,
        'suggest_professional_review': true,
      },
    ],
    'pain': {'entries': 3, 'max_level': 5, 'avg_level': 3.7},
  },
  'recovery': {
    'checkin_averages': {
      'days': 10,
      'energy': 3.5,
      'sleep_quality': 3.2,
      'soreness': 2.1,
      'fatigue': 2.4,
      'motivation': 4,
      'stress': 2,
    },
    'sleep': {'nights': 12, 'avg_hours': 7.2, 'avg_quality': 3.4},
  },
  'lifestyle': {
    'value_kind': 'estimated',
    'steps': {
      'days_logged': 20,
      'avg_steps': 8200,
      'max_steps': 12000,
      'days_on_target': 9,
    },
    'cardio': {'sessions': 3, 'total_minutes': 95, 'total_km': 12.5},
    'hydration': {'days_logged': 15, 'avg_ml': 2400, 'avg_pct_of_target': 80},
    'nutrition': {
      'days_planned': 10,
      'avg_planned_protein_g': 140,
      'avg_eaten_protein_g': 125,
      'avg_protein_target_g': 150,
    },
    'supplements': [
      {
        'name': 'Creatine',
        'taken': 20,
        'missed': 2,
        'skipped': 1,
        'logged_adherence_pct': 87.0,
      },
    ],
  },
  'goals': {
    'as_of': '2026-11-14',
    'goals': [
      {
        'title': 'Bench 100 kg',
        'type': 'strength',
        'goal_status': 'active',
        'target_metric': 'e1rm',
        'target_value': 100,
        'start_value': 80,
        'current_value': 90,
        'progress_pct': 50,
        'progress_status': 'on_track',
      },
    ],
    'milestones': [
      {
        'goal': 'Bench 100 kg',
        'title': '90 kg',
        'target_value': 90,
        'is_reached': true,
      },
    ],
  },
  'context': {
    'splits': [
      {
        'name': 'Push Pull Legs',
        'pattern': 'ppl',
        'start_date': '2026-09-01',
        'end_date': null,
        'duration_days': 74,
      },
    ],
    'breaks': [
      {
        'title': 'Travel',
        'reason': 'work',
        'mode': 'rest',
        'status': 'completed',
        'start_date': '2026-11-20',
        'end_date': '2026-11-21',
        'days_in_period': 2,
      },
    ],
    'deloads': [
      {
        'start_date': '2026-11-23',
        'end_date': '2026-11-29',
        'status': 'planned',
        'reason': 'Scheduled deload',
      },
    ],
  },
  'observations': [
    {
      'code': 'training_volume',
      'text': 'Training volume was 12,450 kg over 2 workouts.',
    },
    {'code': 'consistency', 'text': 'You completed 6 of 8 scheduled sessions.'},
  ],
  if (compare)
    'comparison': {
      'previous_period': {
        'kind': 'monthly',
        'label': 'October 2026',
        'start': '2026-10-01',
        'end': '2026-10-31',
        'days': 31,
      },
      'metrics': [
        {'key': 'sessions', 'current': 2, 'previous': 4, 'change_pct': -50},
        {
          'key': 'volume_kg',
          'current': 12450,
          'previous': 10000,
          'change_pct': 24.5,
        },
        {
          'key': 'avg_sleep_hours',
          'current': 7.2,
          'previous': null,
          'change_pct': null,
        },
      ],
    },
};

/// A gateway that answers from memory. Tests set [result] or [error] and read [summaryCalls].
class FakeReportingGateway implements ReportingGateway {
  Map<String, dynamic>? result;
  ReportError? error;
  final List<Map<String, String>> summaryCalls = [];
  final List<String> events = [];
  BackupValidation? validation;
  ReportError? validateError;

  @override
  Future<Map<String, dynamic>> summary(Map<String, String> query) async {
    summaryCalls.add(query);
    final e = error;
    if (e != null) throw e;
    return result ?? summaryJson();
  }

  @override
  Future<DownloadedFile> downloadReport({
    required Map<String, String> query,
    required ReportFormat format,
    required String directory,
    DownloadProgress? onProgress,
  }) async {
    events.add('report:${format.wire}:${query['period']}');
    final e = error;
    if (e != null) throw e;
    return _write(directory, 'report.${format.wire}');
  }

  @override
  Future<DownloadedFile> downloadBackup({
    required BackupKind kind,
    bool includeMedia = false,
    required String directory,
    DownloadProgress? onProgress,
  }) async {
    events.add('backup:${kind.name}:media=$includeMedia');
    final e = error;
    if (e != null) throw e;
    return _write(
      directory,
      kind == BackupKind.fullZip ? 'backup.zip' : 'export.zip',
    );
  }

  @override
  Future<BackupValidation> validateBackup(String filePath) async {
    events.add('validate:$filePath');
    final e = validateError;
    if (e != null) throw e;
    return validation ??
        const BackupValidation(
          ok: true,
          errors: [],
          warnings: [],
          counts: {'workout_session': 2},
        );
  }

  Future<DownloadedFile> _write(String directory, String name) async {
    await Directory(directory).create(recursive: true);
    final file = File('$directory${Platform.pathSeparator}$name');
    await file.writeAsBytes([1, 2, 3, 4]);
    return DownloadedFile(path: file.path, sizeBytes: 4, fileName: name);
  }
}
