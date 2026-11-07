import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/theme/app_theme.dart';

/// Shown when the owner removed this device. The only way forward is to sign out.
class RevokedScreen extends ConsumerWidget {
  const RevokedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.pagePadding * 1.5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.phonelink_erase, size: 48, color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text('This device was removed', style: text.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                const Text(
                  'You removed this phone from your account. Sign out, then sign in again if you want to use it.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: ref.read(sessionControllerProvider.notifier).signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
