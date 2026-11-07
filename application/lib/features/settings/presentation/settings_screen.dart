import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/widgets/screen_scaffold.dart';

/// Account and device (working), plus placeholders for what Settings will contain:
/// units, notifications (sound and vibration, decision F6), app lock (F8), backups.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out of this phone?'),
        content: const Text('You will need to sign in again to use the app on this phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Sign out')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(sessionControllerProvider.notifier).signOut();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionControllerProvider);

    return ScreenScaffold(
      title: 'Settings',
      children: [
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text('Owner account'),
              subtitle: Text(session.email ?? 'Signed in'),
            ),
            ListTile(
              leading: const Icon(Icons.smartphone),
              title: const Text('This device'),
              subtitle: Text(session.deviceLabel ?? defaultDeviceLabel),
            ),
            ListTile(
              leading: const Icon(Icons.devices_other_outlined),
              title: const Text('Manage devices'),
              subtitle: const Text('See and remove phones that can use your data'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go(AppRoutes.devices),
            ),
            ListTile(
              key: const Key('sign-out-tile'),
              leading: const Icon(Icons.logout),
              title: const Text('Sign out'),
              onTap: () => _confirmSignOut(context, ref),
            ),
          ]),
        ),
        const Card(
          child: Column(children: [
            ListTile(leading: Icon(Icons.straighten), title: Text('Units'), subtitle: Text('kg, cm, km (coming soon)')),
            ListTile(
                leading: Icon(Icons.timer_outlined),
                title: Text('Rest timer alerts'),
                subtitle: Text('Sound and vibration, set separately (coming soon)')),
            ListTile(
                leading: Icon(Icons.fingerprint),
                title: Text('App lock'),
                subtitle: Text('Fingerprint or face unlock, optional (coming soon)')),
          ]),
        ),
      ],
    );
  }
}
