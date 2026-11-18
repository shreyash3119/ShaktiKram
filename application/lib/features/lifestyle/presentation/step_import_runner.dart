import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../data/step_providers.dart';

/// Imports phone steps when the app becomes ready, when it returns to the foreground and every few minutes while open.
/// It never asks for permission. Wrapped around the app in `main.dart` only, so tests never start timers.
class StepImportRunner extends ConsumerStatefulWidget {
  const StepImportRunner({super.key, required this.child, this.interval = const Duration(minutes: 5)});

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<StepImportRunner> createState() => _StepImportRunnerState();
}

class _StepImportRunnerState extends ConsumerState<StepImportRunner> with WidgetsBindingObserver {
  Timer? _timer;

  void _run() {
    if (ref.read(sessionControllerProvider).phase == SessionPhase.ready) {
      unawaited(ref.read(stepSyncProvider.notifier).syncIfReady());
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => _run());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _run();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionState>(sessionControllerProvider, (previous, next) {
      if (next.phase == SessionPhase.ready && previous?.phase != SessionPhase.ready) _run();
    });
    return widget.child;
  }
}
