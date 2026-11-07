import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/backend/backend_error.dart';
import '../../../core/backend/backend_gateway.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/state_views.dart';

final devicesProvider = FutureProvider.autoDispose<List<DeviceRecord>>((ref) {
  return ref.watch(backendGatewayProvider).listDevices();
});

String _formatWhen(DateTime? value) {
  if (value == null) return 'never';
  final d = value.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}

/// Lists the owner's registered devices and lets the owner remove the others.
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  Future<void> _revoke(BuildContext context, WidgetRef ref, DeviceRecord device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${device.label}?'),
        content: const Text(
          'It can no longer send or receive data. If the phone was lost, also sign out all sessions '
          'and change the owner password in the Supabase dashboard, because removing a device does not '
          'end its sign-in.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(backendGatewayProvider).revokeDevice(device.id);
      ref.invalidate(devicesProvider);
    } on BackendError catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = ref.watch(devicesProvider);
    final thisDeviceId = ref.watch(sessionControllerProvider.select((s) => s.deviceId));

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: SafeArea(
        child: devices.when(
          loading: () => const LoadingView(message: 'Loading devices…'),
          error: (error, _) => ErrorView(
            message: error is BackendError ? error.userMessage : 'Could not load devices.',
            onRetry: () => ref.invalidate(devicesProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyView(title: 'No devices', icon: Icons.devices_other_outlined);
            }
            return RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(devicesProvider);
                await ref.read(devicesProvider.future);
              },
              child: ListView.separated(
                padding: const EdgeInsets.all(AppTheme.pagePadding),
                itemCount: list.length,
                separatorBuilder: (context, index) => const SizedBox(height: AppTheme.gap),
                itemBuilder: (context, index) {
                  final device = list[index];
                  final isThis = device.id == thisDeviceId;
                  return Card(
                    child: ListTile(
                      leading: Icon(device.platform == 'web' ? Icons.language : Icons.smartphone),
                      title: Text(device.label),
                      subtitle: Text(
                        '${device.isRevoked ? 'Removed' : 'Active'}'
                        '${isThis ? ' · This device' : ''}\n'
                        'Last seen ${_formatWhen(device.lastSeenAt)}',
                      ),
                      isThreeLine: true,
                      trailing: (isThis || device.isRevoked)
                          ? null
                          : TextButton(
                              onPressed: () => _revoke(context, ref, device),
                              child: const Text('Remove'),
                            ),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}
