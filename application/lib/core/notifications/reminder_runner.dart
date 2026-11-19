import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/training/data/training_providers.dart';
import '../auth/session_controller.dart';
import 'notification_gateway.dart';
import 'reminder_planner.dart';
import 'reminder_settings.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Keeps the phone's pending notifications in line with Settings and the training schedule: when the app is ready, when a
/// reminder switch or time changes, and whenever the app comes forward or goes away (so a schedule edited in the app is
/// picked up). Wrapped around the app in `main.dart` only, so tests never start it.
class ReminderRunner extends ConsumerStatefulWidget {
  const ReminderRunner({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ReminderRunner> createState() => _ReminderRunnerState();
}

class _ReminderRunnerState extends ConsumerState<ReminderRunner> with WidgetsBindingObserver {
  bool _asked = false;
  bool _busy = false;
  bool _again = false;

  bool get _ready => ref.read(sessionControllerProvider).phase == SessionPhase.ready;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || !_ready) return;
    if (_busy) {
      _again = true;
      return;
    }
    _busy = true;
    try {
      final gateway = ref.read(notificationGatewayProvider);
      final settings = ref.read(reminderSettingsProvider);
      if (!_asked && settings.anyOn) {
        _asked = true;
        await gateway.requestPermission();
      }
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final repo = ref.read(trainingRepositoryProvider);
      final entries = await repo.scheduleBetween(
        _ymd(today),
        _ymd(today.add(const Duration(days: reminderHorizonDays))),
      );
      final workouts = <PlannedWorkout>[];
      for (final e in entries) {
        if (e.isRestDay || e.status != 'planned') continue;
        final day = e.splitDayId == null ? null : await repo.splitDay(e.splitDayId!);
        if (day?.isRest == true) continue;
        final p = e.localDate.split('-');
        if (p.length != 3) continue;
        workouts.add(PlannedWorkout(
          date: DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2])),
          name: day?.label ?? 'Your workout',
        ));
      }
      await gateway.replaceAll(planReminders(settings: settings, workouts: workouts, now: now));
    } catch (e) {
      debugPrint('Reminders were not updated: $e');
    } finally {
      _busy = false;
      if (_again) {
        _again = false;
        unawaited(_refresh());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ReminderSettings>(reminderSettingsProvider, (_, __) => _refresh());
    ref.listen<SessionPhase>(
      sessionControllerProvider.select((s) => s.phase),
      (_, next) {
        if (next == SessionPhase.ready) _refresh();
      },
    );
    return widget.child;
  }
}
