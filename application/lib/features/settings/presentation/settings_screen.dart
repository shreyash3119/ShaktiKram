import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/db/local_store.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/sync/sync_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import 'sync_check_card.dart';

/// Settings. Account, devices, sign out, sync status and the theme work now.
/// The other switches and fields only change the screen until the settings table is synced locally
/// (rest-timer sound and vibration F6, app lock F8, notifications).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _appLock = true;
  bool _warmupDefault = true;
  bool _restSound = true;
  bool _restVibration = true;
  final Map<String, bool> _notify = {
    'Workout reminders': true,
    'Leave for gym': true,
    'Supplements': true,
    'Water': false,
    'Reassessment': true,
  };

  Future<void> _confirmSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Sign out of this phone?'),
            content: const Text(
              'You will need to sign in again to use the app on this phone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Sign out'),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      await ref.read(sessionControllerProvider.notifier).signOut();
    }
  }

  Future<void> _confirmClear() async {
    await showDialog<void>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Clear data?'),
            content: const Text(
              'Clearing data is not available yet. It will need you to type DELETE to confirm.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final session = ref.watch(sessionControllerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final sync = ref.watch(syncStatusProvider);

    const themeLabels = ['Dark', 'Light', 'System'];
    const themeModes = [ThemeMode.dark, ThemeMode.light, ThemeMode.system];

    final lastSync =
        sync.lastSyncAt == null
            ? 'Not synced yet'
            : 'Last sync ${_clock(sync.lastSyncAt!.toLocal())}';
    final issueNote =
        sync.issueCount > 0
            ? '${sync.issueCount} change${sync.issueCount == 1 ? ' was' : 's were'} not accepted by the server.'
            : null;
    final (
      String syncTitle,
      String syncRight,
      String? syncProblem,
    ) = switch (sync.phase) {
      SyncPhase.synced => ('Synced', lastSync, null),
      SyncPhase.syncing => ('Syncing', sync.pulledCount > 0 ? 'Downloaded ${sync.pulledCount} records' : 'In progress', null),
      SyncPhase.pending => (
        '${sync.pendingCount} waiting',
        'Will send when online',
        null,
      ),
      SyncPhase.offline => (
        'Offline',
        'Saved on this device',
        'Offline: your changes are saved on this device and will send later.',
      ),
      SyncPhase.error => (
        'Sync problem',
        lastSync,
        sync.message ??
            issueNote ??
            'Sync failed. Your changes are saved on this device.',
      ),
    };

    return ScreenFrame(
      title: 'Settings',
      subtitle: 'Profile, sync, preferences and data',
      children: [
        const TitledCard(
          title: 'Profile & Goals',
          link: 'Edit',
          children: [
            MutedText('Your details, fitness level and goals.', size: 15),
            SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: StatBlock('19 yrs', 'Age', size: 18)),
                Expanded(child: StatBlock('174 cm', 'Height', size: 18)),
                Expanded(child: StatBlock('78.0 kg', 'Weight', size: 18)),
                Expanded(child: StatBlock('Intermediate', 'Level', size: 15)),
              ],
            ),
          ],
        ),
        const TitledCard(
          title: 'Workout & training',
          children: [
            RowList([
              RowItem(
                title: 'Workout split & routines',
                subtitle: 'Manage current and past splits',
                chevron: true,
              ),
              RowItem(
                title: 'Training schedule & reminders',
                subtitle: 'Workout days, time, notifications',
                chevron: true,
              ),
              RowItem(
                title: 'Equipment',
                subtitle: 'Available equipment and alternatives',
                chevron: true,
              ),
            ]),
          ],
        ),
        TitledCard(
          title: 'App preferences',
          children: [
            RowList([
              RowItem(
                title: 'Units',
                subtitle: 'kg, cm, km',
                trailing: 'Imperial: coming soon',
                trailingColor: p.amber,
              ),
              const RowItem(
                title: 'Rest timer alerts',
                subtitle: 'Sound, vibration, timer',
                chevron: true,
              ),
            ]),
            ToggleRow(
              title: 'App lock',
              subtitle: 'Fingerprint or face unlock on this device',
              value: _appLock,
              onChanged: (v) => setState(() => _appLock = v),
            ),
            RowItem(
              title: 'Theme',
              subtitle:
                  '${themeLabels[themeModes.indexOf(themeMode)]}${themeMode == ThemeMode.dark ? ' (default)' : ''}',
              chevron: true,
            ),
          ],
        ),
        TitledCard(
          title: 'Data & reports',
          children: [
            RowList([
              RowItem(
                title: 'Sync',
                subtitle: '$lastSync · ${sync.pendingCount} pending',
                trailing: syncTitle,
              ),
              RowItem(
                title: 'Export data',
                subtitle: 'Download monthly or yearly reports (Excel / PDF)',
                chevron: true,
                onTap: () => context.go(AppRoutes.reports),
              ),
              const RowItem(
                title: 'Backup & restore',
                subtitle: 'Local backup, not cloud sync',
                chevron: true,
              ),
            ]),
          ],
        ),
        TitledCard(
          title: 'Account',
          children: [
            RowList([
              RowItem(
                title: 'Owner account',
                subtitle: session.email ?? 'Signed in',
              ),
              RowItem(
                title: 'This device',
                subtitle: session.deviceLabel ?? defaultDeviceLabel,
              ),
              RowItem(
                title: 'Manage devices',
                subtitle: 'See and remove phones that can use your data',
                chevron: true,
                onTap: () => context.go(AppRoutes.devices),
              ),
              RowItem(
                key: const Key('sign-out-tile'),
                title: 'Sign out',
                onTap: _confirmSignOut,
              ),
            ]),
          ],
        ),
        TitledCard(
          title: 'Clear data',
          children: [
            const MutedText(
              'Delete selected data or reset the app. You type DELETE to confirm and your existing account will be removed. '
              'This cannot be undone.',
            ),
            const SizedBox(height: 14),
            AppButton(
              'Clear data…',
              kind: ButtonKind.danger,
              onPressed: _confirmClear,
            ),
          ],
        ),
        const TitledCard(
          title: 'About',
          children: [
            RowList([
              RowItem(
                title: 'Personal Fitness Manager',
                subtitle: 'v1.0.0 (in progress)',
                chevron: true,
              ),
            ]),
          ],
        ),
        const GroupLabel('Profile · Training · Notifications'),
        TitledCard(
          title: 'Edit profile & goals',
          children: [
            const Row(
              children: [
                Expanded(
                  child: LabeledField(
                    'Age',
                    initial: '19',
                    keyboard: TextInputType.number,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: LabeledField(
                    'Height (cm)',
                    initial: '174',
                    keyboard: TextInputType.number,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: LabeledField(
                    'Weight (kg)',
                    initial: '78.0',
                    keyboard: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            const RowList([
              RowItem(title: 'Cut to 75 kg', subtitle: 'Active', chevron: true),
              RowItem(
                title: 'Bench Press 90 kg',
                subtitle: 'Active',
                chevron: true,
              ),
            ]),
            const SizedBox(height: 10),
            AppButton('Add goal', onPressed: () {}),
          ],
        ),
        TitledCard(
          title: 'Training defaults',
          children: [
            const RowList([
              RowItem(
                title: 'Default rest',
                subtitle: 'Between sets',
                trailing: '90 s',
              ),
              RowItem(
                title: 'Rep range',
                subtitle: 'Default for new exercises',
                trailing: '8–12',
              ),
            ]),
            ToggleRow(
              title: 'Warm-up sets',
              subtitle: 'Add sets by default',
              value: _warmupDefault,
              onChanged: (v) => setState(() => _warmupDefault = v),
            ),
          ],
        ),
        const GroupLabel('Notifications'),
        TitledCard(
          title: 'Notification preferences',
          children: [
            for (final e in _notify.entries)
              ToggleRow(
                title: e.key,
                value: e.value,
                onChanged: (v) => setState(() => _notify[e.key] = v),
              ),
          ],
        ),
        TitledCard(
          title: 'Rest timer',
          children: [
            ToggleRow(
              title: 'Sound',
              value: _restSound,
              onChanged: (v) => setState(() => _restSound = v),
            ),
            ToggleRow(
              title: 'Vibration',
              value: _restVibration,
              onChanged: (v) => setState(() => _restVibration = v),
            ),
          ],
        ),
        const GroupLabel('Preferences'),
        TitledCard(
          title: 'Theme',
          children: [
            PillTabs(
              labels: themeLabels,
              index: themeModes.indexOf(themeMode),
              onChanged:
                  (i) =>
                      ref.read(themeModeProvider.notifier).set(themeModes[i]),
            ),
          ],
        ),
        const GroupLabel('Data management'),
        TitledCard(
          title: 'Sync status',
          children: [
            RowList([RowItem(title: syncTitle, trailing: syncRight)]),
            if (syncProblem == null) ...[
              const SizedBox(height: 12),
              AppButton(
                'Sync now',
                onPressed:
                    () => ref.read(syncStatusProvider.notifier).syncNow(),
              ),
            ],
            if (syncProblem != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.tile,
                  borderRadius: BorderRadius.circular(AppTheme.radius),
                ),
                child: Text(
                  syncProblem,
                  style: TextStyle(color: p.red, fontSize: 14.5, height: 1.35),
                ),
              ),
              const SizedBox(height: 12),
              AppButton.primary(
                'Retry sync',
                onPressed:
                    () => ref.read(syncStatusProvider.notifier).syncNow(),
              ),
            ],
          ],
        ),
        if (kDebugMode) const SyncCheckCard(),
        TitledCard(
          title: 'Local storage',
          children: [
            FutureBuilder<int>(
              key: ValueKey(
                '${ref.watch(dataRevisionProvider)}-${sync.pendingCount}',
              ),
              future: ref.read(localStoreProvider).recordCount(),
              builder:
                  (context, snapshot) => Row(
                    children: [
                      Expanded(
                        child: StatBlock(
                          '${snapshot.data ?? 0}',
                          'Records on device',
                          size: 22,
                        ),
                      ),
                      Expanded(
                        child: StatBlock(
                          '${sync.pendingCount}',
                          'Pending changes',
                          size: 22,
                        ),
                      ),
                    ],
                  ),
            ),
          ],
        ),
        TitledCard(
          title: 'Backup & restore',
          children: [
            const MutedText(
              'Last backup: not yet made. Auto-backup: every 7 days.',
              size: 15,
            ),
            const SizedBox(height: 12),
            ButtonPair(
              AppButton('Back up now', onPressed: () {}),
              AppButton('Restore…', onPressed: () {}),
            ),
          ],
        ),
      ],
    );
  }
}

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
}
