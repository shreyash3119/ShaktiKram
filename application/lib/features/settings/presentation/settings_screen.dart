import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import 'settings_common.dart';

/// Settings hub: profile summary, a backup reminder, five pages (training, notifications, appearance, data & sync,
/// account) and the sync state. Sign out and the danger zone live on the Account page. The profile numbers are
/// still placeholders until the profile is stored on the phone.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    return ScreenFrame(
      title: 'Settings',
      subtitle: 'Profile, sync and data',
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Profile & goals',
                      style: TextStyle(
                        color: p.text,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  InkWell(
                    key: const Key('profile-edit'),
                    onTap:
                        () => ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Profile editing is coming soon.'),
                          ),
                        ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(
                        'Edit',
                        style: TextStyle(color: p.link, fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Expanded(child: StatBlock('19', 'Age', size: 28)),
                  Expanded(child: StatBlock('174 cm', 'Height', size: 28)),
                  Expanded(child: StatBlock('78 kg', 'Weight', size: 28)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Level: Intermediate · Cut to 75 kg · Bench 90 kg',
                style: TextStyle(color: p.muted, fontSize: 15),
              ),
            ],
          ),
        ),
        const BackupBanner(),
        SettingsCard(
          children: [
            RowList([
              NavRow(
                'Workout & training',
                onTap: () => context.push(AppRoutes.settingsTraining),
              ),
              NavRow(
                'Notifications',
                onTap: () => context.push(AppRoutes.settingsNotifications),
              ),
              NavRow(
                'Appearance',
                onTap: () => context.push(AppRoutes.settingsAppearance),
              ),
              NavRow(
                'Data & sync',
                onTap: () => context.push(AppRoutes.settingsData),
              ),
              NavRow(
                'Account',
                onTap: () => context.push(AppRoutes.settingsAccount),
              ),
            ]),
          ],
        ),
        const SyncCard(),
        Center(
          child: Text(
            'Personal Fitness Manager v1.0.0',
            style: TextStyle(color: p.muted, fontSize: 15),
          ),
        ),
      ],
    );
  }
}
