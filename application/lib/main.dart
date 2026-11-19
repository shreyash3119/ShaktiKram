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
import 'core/notifications/notification_gateway.dart';
import 'core/notifications/reminder_runner.dart';
import 'core/notifications/reminder_settings.dart';
import 'core/sync/sync_runner.dart';
import 'features/auth/presentation/startup_problem_app.dart';
import 'features/lifestyle/data/health_connect_step_source.dart';
import 'features/lifestyle/data/step_source.dart';
import 'features/lifestyle/presentation/step_import_runner.dart';

const _launchColor = Color(0xFF0B111D);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final problem = AppConfig.problem;
  if (problem != null) {
    runApp(StartupProblemApp(title: 'App is not configured', message: problem));
    return;
  }
  // The launch picture is on screen straight away, while the set-up below runs. The Android launch screen itself is
  // only the plain background colour (a system launch screen cannot show a large picture on Android 12 and newer).
  runApp(const _Launch());
}

/// Shows the launch picture, runs the set-up, then starts the app with the picture still on top until the session
/// check has finished. No fixed delay: the picture is only on screen for as long as the set-up really takes.
class _Launch extends StatefulWidget {
  const _Launch();

  @override
  State<_Launch> createState() => _LaunchState();
}

class _LaunchState extends State<_Launch> {
  List<Override>? _overrides;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      // The three set-up steps do not depend on each other, so they run together. Each does what it did before.
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
      if (!mounted) return;
      setState(() {
        _overrides = [
          authServiceProvider.overrideWithValue(
            SupabaseAuthService(client.auth),
          ),
          backendGatewayProvider.overrideWithValue(
            SupabaseBackendGateway(client),
          ),
          deviceStoreProvider.overrideWithValue(SharedPrefsDeviceStore(prefs)),
          localStoreProvider.overrideWithValue(localStore),
          reminderStoreProvider.overrideWithValue(SharedPrefsReminderStore(prefs)),
          notificationGatewayProvider.overrideWithValue(LocalNotificationGateway()),
          stepSourceProvider.overrideWithValue(HealthConnectStepSource()),
        ];
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    if (error != null) {
      return StartupProblemApp(title: 'The app could not start', message: '$error');
    }
    final overrides = _overrides;
    if (overrides == null) return const LaunchPicture();
    return ProviderScope(
      overrides: overrides,
      child: const _LaunchCover(
        child: SyncRunner(
          child: ReminderRunner(child: StepImportRunner(child: ShaktiKramApp())),
        ),
      ),
    );
  }
}

/// The launch picture: branding/splash_img.png, as large as the screen allows without stretching or cropping it.
class LaunchPicture extends StatelessWidget {
  const LaunchPicture({super.key});

  @override
  Widget build(BuildContext context) {
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: _launchColor,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: SizedBox.expand(
            child: Image(
              image: AssetImage('branding/splash_img.png'),
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: _noPicture,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _noPicture(BuildContext c, Object e, StackTrace? s) => const SizedBox.shrink();
}

/// Keeps [LaunchPicture] over the app until the session phase is known and the router has moved on to the screen that
/// belongs to it. A safety timer removes it anyway, so the app can never sit on the picture.
class _LaunchCover extends ConsumerStatefulWidget {
  const _LaunchCover({required this.child});

  final Widget child;

  @override
  ConsumerState<_LaunchCover> createState() => _LaunchCoverState();
}

class _LaunchCoverState extends ConsumerState<_LaunchCover> {
  bool _covering = true;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    _safetyTimer = Timer(const Duration(seconds: 3), _release);
    WidgetsBinding.instance.addPostFrameCallback((_) => _releaseIfKnown());
  }

  void _releaseIfKnown() {
    if (!mounted) return;
    if (ref.read(sessionControllerProvider).phase != SessionPhase.checking) _release();
  }

  void _release() {
    _safetyTimer?.cancel();
    if (mounted && _covering) setState(() => _covering = false);
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
        // After the frame that applies the router's redirect, so what appears is the final screen.
        WidgetsBinding.instance.addPostFrameCallback((_) => _release());
      },
    );
    return Stack(
      textDirection: TextDirection.ltr,
      children: [
        Positioned.fill(child: widget.child),
        if (_covering) const Positioned.fill(child: LaunchPicture()),
      ],
    );
  }
}
