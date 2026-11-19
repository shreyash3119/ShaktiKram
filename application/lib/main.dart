import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/auth/auth_service.dart';
import 'core/auth/session_controller.dart';
import 'core/auth/device_store.dart';
import 'core/auth/supabase_auth_service.dart';
import 'core/backend/backend_gateway.dart';
import 'core/backend/supabase_backend_gateway.dart';
import 'core/config/app_config.dart';
import 'core/db/local_store.dart';
import 'core/db/sqflite_local_store.dart';
import 'core/sync/sync_runner.dart';
import 'features/auth/presentation/startup_problem_app.dart';
import 'features/lifestyle/data/health_connect_step_source.dart';
import 'features/lifestyle/data/step_source.dart';
import 'features/lifestyle/presentation/step_import_runner.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();

  final problem = AppConfig.problem;
  if (problem != null) {
    runApp(StartupProblemApp(title: 'App is not configured', message: problem));
    return;
  }

  var held = false;
  try {
    // The three set-up steps do not depend on each other, so they run together instead of one after another. Each
    // does exactly what it did before; only the waiting overlaps. (Future.wait rethrows the first error as it is.)
    final ready = await Future.wait<Object?>([
      Supabase.initialize(
        url: AppConfig.supabaseUrl,
        publishableKey: AppConfig.supabasePublishableKey,
      ),
      SharedPreferences.getInstance(),
      SqfliteLocalStore.open(),
    ]);
    final client = Supabase.instance.client;
    final prefs = ready[1] as SharedPreferences;
    final localStore = ready[2] as SqfliteLocalStore;

    // Keep the Android launch screen up until the session check has finished (a few milliseconds), so it is followed
    // directly by Home (or sign-in) and not by a second "Starting…" screen. The app still builds and starts normally
    // meanwhile; only the first picture is held back.
    binding.deferFirstFrame();
    held = true;
    runApp(
      ProviderScope(
        overrides: [
          authServiceProvider.overrideWithValue(
            SupabaseAuthService(client.auth),
          ),
          backendGatewayProvider.overrideWithValue(
            SupabaseBackendGateway(client),
          ),
          deviceStoreProvider.overrideWithValue(SharedPrefsDeviceStore(prefs)),
          localStoreProvider.overrideWithValue(localStore),
          stepSourceProvider.overrideWithValue(HealthConnectStepSource()),
        ],
        child: const _FirstFrameGate(
          child: SyncRunner(child: StepImportRunner(child: ShaktiKramApp())),
        ),
      ),
    );
  } catch (e) {
    if (held) binding.allowFirstFrame();
    runApp(StartupProblemApp(title: 'The app could not start', message: '$e'));
  }
}

/// Releases the first frame held back in [main] once the session phase is known and the router has moved on to the
/// screen that belongs to it. A safety timer releases it anyway if the check ever stays unfinished, so the app can
/// never sit on the launch screen.
class _FirstFrameGate extends ConsumerStatefulWidget {
  const _FirstFrameGate({required this.child});

  final Widget child;

  @override
  ConsumerState<_FirstFrameGate> createState() => _FirstFrameGateState();
}

class _FirstFrameGateState extends ConsumerState<_FirstFrameGate> {
  static const _safety = Duration(seconds: 3);
  bool _released = false;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    _safetyTimer = Timer(_safety, _release);
  }

  void _release() {
    if (_released) return;
    _released = true;
    _safetyTimer?.cancel();
    WidgetsBinding.instance.allowFirstFrame();
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SessionPhase>(
      sessionControllerProvider.select((s) => s.phase),
      (previous, next) {
        if (next == SessionPhase.checking) return;
        // After the frame that applies the router's redirect, so the first picture is the final screen.
        WidgetsBinding.instance.addPostFrameCallback((_) => _release());
      },
    );
    return widget.child;
  }
}
