import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/session_controller.dart';
import '../../../core/notifications/notification_gateway.dart';
import '../../../core/notifications/reminder_planner.dart';
import '../../../core/notifications/reminder_settings.dart';
import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import 'settings_common.dart';

/// Workout & training: where splits and equipment are managed, the training days and the defaults for new exercises.
/// The days, reminder time and defaults only change the screen until the settings table is synced locally.
final trainingDaysProvider = StateProvider<List<bool>>(
  (ref) => [true, false, true, false, true, false, false],
);

class TrainingSettingsPage extends ConsumerWidget {
  const TrainingSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final days = ref.watch(trainingDaysProvider);
    const letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return SettingsPage(
      title: 'Workout & training',
      subtitle: 'Splits, schedule, equipment',
      children: [
        SettingsCard(
          children: [
            RowList([
              PlainRow(
                'Workout split',
                sub: 'Manage current and past splits',
                chevron: true,
                onTap: () => context.go(AppRoutes.training),
              ),
              PlainRow(
                'Equipment',
                sub: 'Available equipment and alternatives',
                chevron: true,
                onTap: () => context.go(AppRoutes.training),
              ),
            ]),
          ],
        ),
        SettingsCard(
          title: 'Training schedule',
          children: [
            Row(
              children: [
                for (var i = 0; i < 7; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(
                    child: InkWell(
                      key: Key('day-$i'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        final next = [...days];
                        next[i] = !next[i];
                        ref.read(trainingDaysProvider.notifier).state = next;
                      },
                      child: Container(
                        height: 52,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: days[i] ? p.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: days[i] ? p.primary : p.divider,
                          ),
                        ),
                        child: Text(
                          letters[i],
                          style: TextStyle(
                            color: days[i] ? p.onPrimary : p.muted,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: p.divider),
            const PlainRow('Reminder time', value: '6:30 pm'),
          ],
        ),
        const SettingsCard(
          children: [
            _SectionLabel('Defaults for new exercises'),
            RowList([
              PlainRow('Default rest', sub: 'Between sets', value: '90 s'),
              PlainRow(
                'Rep range',
                sub: 'Default for new exercises',
                value: '8–12',
              ),
              PrefToggle(
                'Warm-up sets',
                title: 'Warm-up sets',
                sub: 'Add sets by default',
              ),
            ]),
          ],
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(color: p.muted, fontSize: 15, letterSpacing: 0.8),
      ),
    );
  }
}

/// Notifications and the rest timer. Only changes the screen until the settings table is synced locally.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  Future<void> _pickTime(
    BuildContext context,
    int minutes,
    void Function(int) save,
  ) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
    );
    if (t != null) save(t.hour * 60 + t.minute);
  }

  Future<void> _test(BuildContext context, WidgetRef ref) async {
    final gateway = ref.read(notificationGatewayProvider);
    final messenger = ScaffoldMessenger.of(context);
    final allowed = await gateway.requestPermission();
    await gateway.showNow('ShaktiKram', 'Reminders are working.');
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          allowed
              ? 'Test notification sent.'
              : 'Notifications are blocked. Allow them for ShaktiKram in the phone\'s Settings > Apps > Notifications.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(reminderSettingsProvider);
    final n = ref.read(reminderSettingsProvider.notifier);
    return SettingsPage(
      title: 'Notifications',
      subtitle: 'Reminders and timers',
      children: [
        SettingsCard(
          children: [
            RowList([
              ToggleRow(
                key: const Key('toggle-Workout reminders'),
                title: 'Workout reminders',
                subtitle: 'On your planned training days',
                value: s.workout,
                onChanged: n.setWorkout,
              ),
              ToggleRow(
                key: const Key('toggle-Leave for gym'),
                title: 'Leave for gym',
                subtitle: 'Nudge $leaveBeforeMinutes minutes before',
                value: s.leaveForGym,
                onChanged: n.setLeaveForGym,
              ),
              ToggleRow(
                key: const Key('toggle-Supplements'),
                title: 'Supplements',
                subtitle: 'Every day at ${reminderClock(s.supplementMinutes)}',
                value: s.supplements,
                onChanged: n.setSupplements,
              ),
              ToggleRow(
                key: const Key('toggle-Water'),
                title: 'Water',
                subtitle: 'Every 2 hours, 9 am to 9 pm',
                value: s.water,
                onChanged: n.setWater,
              ),
              ToggleRow(
                key: const Key('toggle-Reassessment'),
                title: 'Reassessment',
                subtitle: 'Sundays at 10:00 am',
                value: s.reassessment,
                onChanged: n.setReassessment,
              ),
            ]),
          ],
        ),
        SettingsCard(
          title: 'Times',
          children: [
            RowList([
              PlainRow(
                'Workout time',
                sub: 'When your training day reminder arrives',
                value: reminderClock(s.workoutMinutes),
                chevron: true,
                onTap:
                    () => _pickTime(context, s.workoutMinutes, n.setWorkoutMinutes),
              ),
              PlainRow(
                'Supplement time',
                sub: 'Daily supplement reminder',
                value: reminderClock(s.supplementMinutes),
                chevron: true,
                onTap:
                    () => _pickTime(
                      context,
                      s.supplementMinutes,
                      n.setSupplementMinutes,
                    ),
              ),
              PlainRow(
                'Send a test notification',
                sub: 'Check that sound and pop-ups work on this phone',
                chevron: true,
                onTap: () => _test(context, ref),
              ),
            ]),
          ],
        ),
        _SectionLabel('Rest timer'),
        SettingsCard(
          children: [
            RowList([
              PrefToggle(
                'Rest sound',
                title: 'Sound',
                sub: 'Play a sound when rest ends',
              ),
              PrefToggle(
                'Rest vibration',
                title: 'Vibration',
                sub: 'Vibrate when rest ends',
              ),
            ]),
          ],
        ),
      ],
    );
  }
}

/// Theme, units and app lock. The theme works now; units are metric only and app lock only changes the screen.
class AppearancePage extends ConsumerWidget {
  const AppearancePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final mode = ref.watch(themeModeProvider);
    const labels = ['Dark', 'Light', 'System'];
    const modes = [ThemeMode.dark, ThemeMode.light, ThemeMode.system];
    return SettingsPage(
      title: 'Appearance',
      subtitle: 'Theme, units and security',
      children: [
        SettingsCard(
          title: 'Theme',
          children: [
            PillTabs(
              labels: labels,
              index: modes.indexOf(mode),
              container: true,
              onChanged:
                  (i) => ref.read(themeModeProvider.notifier).set(modes[i]),
            ),
          ],
        ),
        SettingsCard(
          title: 'Units',
          children: [
            PillTabs(
              labels: const ['Metric', 'Imperial · Soon'],
              index: 0,
              container: true,
              onChanged:
                  (i) =>
                      i == 1
                          ? ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Imperial units are coming soon.'),
                            ),
                          )
                          : null,
            ),
            const SizedBox(height: 10),
            Text('kg, cm, km', style: TextStyle(color: p.muted, fontSize: 15)),
          ],
        ),
        const SettingsCard(
          children: [
            PrefToggle(
              'App lock',
              title: 'App lock',
              sub: 'Fingerprint or face unlock on this device',
            ),
          ],
        ),
      ],
    );
  }
}

/// Sync, backups and exports.
class DataSyncPage extends StatelessWidget {
  const DataSyncPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsPage(
      title: 'Data & sync',
      subtitle: 'Sync, export and backup',
      children: [
        const SyncCard(detailed: true),
        debugSyncCheck(),
        const BackupBanner(),
        SettingsCard(
          children: [
            RowList([
              PlainRow(
                'Export data',
                sub: 'Download a report as Excel or PDF',
                chevron: true,
                onTap: () => context.go('${AppRoutes.reports}?tab=export'),
              ),
              PlainRow(
                'Backup & data export',
                sub: 'Full backup, CSV export, check a file',
                chevron: true,
                onTap: () => context.push(AppRoutes.backup),
              ),
            ]),
          ],
        ),
      ],
    );
  }
}

/// The owner account, this device, the devices that can use the data, sign out and clearing data.
class AccountPage extends ConsumerStatefulWidget {
  const AccountPage({super.key});

  @override
  ConsumerState<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends ConsumerState<AccountPage> {
  bool _show = false;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final session = ref.watch(sessionControllerProvider);
    final email = session.email;
    return SettingsPage(
      title: 'Account',
      subtitle: 'Owner and devices',
      children: [
        SettingsCard(
          children: [
            RowList([
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Owner account',
                            style: TextStyle(color: p.text, fontSize: 19),
                          ),
                          Text(
                            _show ? (email ?? 'Signed in') : maskedEmail(email),
                            style: TextStyle(color: p.muted, fontSize: 15),
                          ),
                        ],
                      ),
                    ),
                    InkWell(
                      key: const Key('show-email'),
                      onTap: () => setState(() => _show = !_show),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(
                          _show ? 'Hide' : 'Show',
                          style: TextStyle(color: p.link, fontSize: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              PlainRow(
                'This device',
                sub: session.deviceLabel ?? defaultDeviceLabel,
              ),
              PlainRow(
                'Manage devices',
                sub: 'See and remove phones that can use your data',
                chevron: true,
                onTap: () => context.go(AppRoutes.devices),
              ),
            ]),
          ],
        ),
        const SignOutAndDanger(),
      ],
    );
  }
}
