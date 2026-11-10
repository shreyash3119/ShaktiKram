import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/session_controller.dart';
import 'sync_status.dart';

/// Starts sync rounds: when the app becomes ready, every minute, and when it returns to the foreground.
/// Wrapped around the app in `main.dart` only, so tests never start timers.
class SyncRunner extends ConsumerStatefulWidget {
  const SyncRunner({super.key, required this.child, this.interval = const Duration(seconds: 60)});

  final Widget child;
  final Duration interval;

  @override
  ConsumerState<SyncRunner> createState() => _SyncRunnerState();
}

class _SyncRunnerState extends ConsumerState<SyncRunner> with WidgetsBindingObserver {
  Timer? _timer;

  bool get _ready => ref.read(sessionControllerProvider).phase == SessionPhase.ready;

  void _sync() {
    if (_ready) unawaited(ref.read(syncStatusProvider.notifier).syncNow());
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(widget.interval, (_) => _sync());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
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
      if (next.phase == SessionPhase.ready && previous?.phase != SessionPhase.ready) _sync();
    });
    return widget.child;
  }
}
