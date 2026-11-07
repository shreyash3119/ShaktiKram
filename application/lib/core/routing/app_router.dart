import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/connecting_screen.dart';
import '../../features/auth/presentation/revoked_screen.dart';
import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/lifestyle/presentation/lifestyle_screen.dart';
import '../../features/progress/presentation/progress_screen.dart';
import '../../features/reports/presentation/reports_screen.dart';
import '../../features/settings/presentation/devices_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/training/presentation/training_screen.dart';
import '../auth/session_controller.dart';
import 'app_shell.dart';

/// Route paths in one place. Feature screens add nested routes under their own branch later.
class AppRoutes {
  AppRoutes._();
  static const home = '/home';
  static const training = '/training';
  static const progress = '/progress';
  static const lifestyle = '/lifestyle';
  static const reports = '/reports';
  static const settings = '/settings';
  static const devices = '/settings/devices';

  // Outside the main navigation: shown while there is no usable session.
  static const splash = '/splash';
  static const signIn = '/sign-in';
  static const connecting = '/connecting';
  static const revoked = '/revoked';

  static const gateRoutes = {splash, signIn, connecting, revoked};
}

/// Decides where the owner must be for a given session phase. Returns null to stay where they are.
String? sessionRedirect(SessionPhase phase, String location) {
  switch (phase) {
    case SessionPhase.ready:
      return AppRoutes.gateRoutes.contains(location) ? AppRoutes.home : null;
    case SessionPhase.checking:
      return location == AppRoutes.splash ? null : AppRoutes.splash;
    case SessionPhase.signedOut:
      return location == AppRoutes.signIn ? null : AppRoutes.signIn;
    case SessionPhase.connecting:
      return location == AppRoutes.connecting ? null : AppRoutes.connecting;
    case SessionPhase.revoked:
      return location == AppRoutes.revoked ? null : AppRoutes.revoked;
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever the session phase changes.
  final phaseChanged = ValueNotifier<int>(0);
  ref.listen<SessionPhase>(
    sessionControllerProvider.select((s) => s.phase),
    (previous, next) => phaseChanged.value++,
  );
  ref.onDispose(phaseChanged.dispose);

  final router = GoRouter(
    initialLocation: AppRoutes.home,
    refreshListenable: phaseChanged,
    redirect: (context, state) =>
        sessionRedirect(ref.read(sessionControllerProvider).phase, state.matchedLocation),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (context, state) => const SplashScreen()),
      GoRoute(path: AppRoutes.signIn, builder: (context, state) => const SignInScreen()),
      GoRoute(path: AppRoutes.connecting, builder: (context, state) => const ConnectingScreen()),
      GoRoute(path: AppRoutes.revoked, builder: (context, state) => const RevokedScreen()),
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state, StatefulNavigationShell shell) =>
            AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.home, builder: (context, state) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.training, builder: (context, state) => const TrainingScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.progress, builder: (context, state) => const ProgressScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.lifestyle, builder: (context, state) => const LifestyleScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: AppRoutes.reports, builder: (context, state) => const ReportsScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.settings,
              builder: (context, state) => const SettingsScreen(),
              routes: [
                GoRoute(path: 'devices', builder: (context, state) => const DevicesScreen()),
              ],
            ),
          ]),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
