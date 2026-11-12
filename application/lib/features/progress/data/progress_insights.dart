import '../../../core/insights/insight_repository.dart';

/// The server calculations Progress and Home show, and how long each counts as fresh. The keys are the cache keys.
/// Nothing here computes anything: each spec only says which server function or view to read.

/// The whole "today" picture for [localDate] (`YYYY-MM-DD`).
InsightSpec dailyBriefingSpec(String localDate) => InsightSpec(
      key: 'daily_briefing:$localDate',
      freshFor: const Duration(minutes: 15),
      fetch: (g) => g.callInsight('api_daily_briefing', params: {'p_on': localDate}),
    );

InsightSpec _view(String view, {String? orderBy, bool descending = false, int? limit, Duration freshFor = const Duration(hours: 1)}) => InsightSpec(
      key: 'view:$view',
      freshFor: freshFor,
      fetch: (g) => g.readView(view, orderBy: orderBy, descending: descending, limit: limit),
    );

final exerciseTrendsSpec = _view('v_exercise_trends');
final exerciseSessionBestSpec = _view('v_exercise_session_best', orderBy: 'local_date', descending: true, limit: 300);
final goalProgressSpec = _view('v_goal_progress', freshFor: const Duration(minutes: 30));
final goalMilestonesSpec = _view('v_goal_milestones', freshFor: const Duration(minutes: 30));
final muscleExposureSpec = _view('v_muscle_exposure_weekly', orderBy: 'week_start', descending: true, limit: 200);
final muscleRatingsSpec = _view('v_muscle_ratings');
final bodyCompositionSpec = _view('v_body_composition', orderBy: 'local_date', descending: true, limit: 60);
