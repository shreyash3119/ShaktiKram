import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/widgets/state_views.dart';

/// Shown after sign-in while this device is registered. If registration fails (for example no connection),
/// it shows the problem with a retry button.
class ConnectingScreen extends ConsumerWidget {
  const ConnectingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);
    final controller = ref.read(sessionControllerProvider.notifier);
    final message = session.message;

    return Scaffold(
      body: SafeArea(
        child: message == null
            ? const LoadingView(message: 'Setting up this device…')
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ErrorView(message: message, onRetry: controller.retry),
                  TextButton(onPressed: controller.signOut, child: const Text('Sign out')),
                ],
              ),
      ),
    );
  }
}
