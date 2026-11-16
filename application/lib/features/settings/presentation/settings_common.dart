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
import '../../../core/widgets/section_widgets.dart';
import '../../reports/presentation/backup_screen.dart' show lastBackupProvider;
import 'sync_check_card.dart';

/// Pieces shared by the Settings hub and its pages.

/// A page opened from the Settings hub: back button, title and subtitle, then the content.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: title,
      subtitle: subtitle,
      leading: HeaderIconButton(
        key: const Key('settings-back'),
        icon: Icons.chevron_left,
        tooltip: 'Back',
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.settings);
          }
        },
      ),
      children: children,
    );
  }
}

/// A card with a title and content, or just content when [title] is null.
class SettingsCard extends StatelessWidget {
  const SettingsCard({super.key, this.title, required this.children});

  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: TextStyle(
                color: p.text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
          ],
          ...children,
        ],
      ),
    );
  }
}

/// A row with an info tile, a title and a short summary on the right.
class NavRow extends StatelessWidget {
  const NavRow(this.title, {super.key, this.summary, required this.onTap});

  final String title;
  final String? summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: p.tile,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.info_outline, color: p.link, size: 22),
            ),
            const SizedBox(width: 14),
            Text(title, style: TextStyle(color: p.text, fontSize: 19)),
            if (summary != null) ...[
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary!,
                  textAlign: TextAlign.end,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: p.muted, fontSize: 15),
                ),
              ),
            ] else
              const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// A plain row: title, a small line under it, and a value or chevron on the right.
class PlainRow extends StatelessWidget {
  const PlainRow(
    this.title, {
    super.key,
    this.sub,
    this.value,
    this.chevron = false,
    this.onTap,
  });

  final String title;
  final String? sub;
  final String? value;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: p.text, fontSize: 19)),
                  if (sub != null)
                    Text(sub!, style: TextStyle(color: p.muted, fontSize: 15)),
                ],
              ),
            ),
            if (value != null)
              Text(value!, style: TextStyle(color: p.muted, fontSize: 17)),
            if (chevron) Icon(Icons.chevron_right, color: p.muted),
          ],
        ),
      ),
    );
  }
}

/// A toggle row whose value lives in a provider so it survives leaving the page.
/// These switches only change the screen until the settings table is synced locally
/// (rest-timer sound and vibration, app lock, notifications).
const _toggleDefaults = {'Water': false};

final prefToggleProvider = StateProvider.family<bool, String>(
  (ref, key) => _toggleDefaults[key] ?? true,
);

class PrefToggle extends ConsumerWidget {
  const PrefToggle(this.prefKey, {super.key, required this.title, this.sub});

  final String prefKey;
  final String title;
  final String? sub;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ToggleRow(
    key: Key('toggle-$prefKey'),
    title: title,
    subtitle: sub,
    value: ref.watch(prefToggleProvider(prefKey)),
    onChanged: (v) => ref.read(prefToggleProvider(prefKey).notifier).state = v,
  );
}

String clockText(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
}

/// "owner@example.com" -> "owner@...com".
String maskedEmail(String? email) {
  if (email == null || !email.contains('@')) return 'Signed in';
  final at = email.indexOf('@');
  final tail = email.contains('.') ? email.substring(email.lastIndexOf('.') + 1) : '';
  return '${email.substring(0, at)}@...$tail';
}

/// The sync state: a title, a line of detail and the button that asks for a sync. [detailed] adds the counts.
class SyncCard extends ConsumerWidget {
  const SyncCard({super.key, this.detailed = false});

  final bool detailed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final sync = ref.watch(syncStatusProvider);
    final lastSync =
        sync.lastSyncAt == null
            ? 'Not synced yet'
            : 'Last sync ${clockText(sync.lastSyncAt!.toLocal())}';
    final issueNote =
        sync.issueCount > 0
            ? '${sync.issueCount} change${sync.issueCount == 1 ? ' was' : 's were'} not accepted by the server.'
            : null;
    final (String title, String right, String? problem) = switch (sync.phase) {
      SyncPhase.synced => ('Synced', lastSync, null),
      SyncPhase.syncing => (
        'Syncing',
        sync.pulledCount > 0
            ? 'Downloaded ${sync.pulledCount} records'
            : 'In progress',
        null,
      ),
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
    final records = FutureBuilder<int>(
      key: ValueKey('${ref.watch(dataRevisionProvider)}-${sync.pendingCount}'),
      future: ref.read(localStoreProvider).recordCount(),
      builder:
          (context, snap) => Row(
            children: [
              Expanded(
                child: StatBlock(
                  '${snap.data ?? 0}',
                  'Records on device',
                  size: 26,
                ),
              ),
              Expanded(
                child: StatBlock(
                  '${sync.pendingCount}',
                  'Pending changes',
                  size: 26,
                ),
              ),
            ],
          ),
    );
    void syncNow() => ref.read(syncStatusProvider.notifier).syncNow();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                title,
                key: const Key('sync-title'),
                style: TextStyle(
                  color: p.text,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  detailed ? right : '$right · ${sync.pendingCount} pending',
                  textAlign: detailed ? TextAlign.end : TextAlign.start,
                  style: TextStyle(color: p.muted, fontSize: 14),
                ),
              ),
            ],
          ),
          if (detailed) ...[const SizedBox(height: 14), records],
          if (problem != null) ...[
            const SizedBox(height: 12),
            Text(
              problem,
              style: TextStyle(color: p.red, fontSize: 15, height: 1.35),
            ),
          ],
          const SizedBox(height: 14),
          problem == null
              ? AppButton('Sync now', height: 56, onPressed: syncNow)
              : AppButton.primary('Retry sync', height: 56, onPressed: syncNow),
        ],
      ),
    );
  }
}

/// "No backup yet" in amber with the button that makes one; after a backup it shows when.
class BackupBanner extends ConsumerWidget {
  const BackupBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final last = ref.watch(lastBackupProvider).valueOrNull;
    final none = last == null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.cardPadding),
      decoration: BoxDecoration(
        color: none ? p.amber.withValues(alpha: 0.12) : p.card,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: Border.all(
          color: none ? p.amber.withValues(alpha: 0.6) : p.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            none ? 'No backup yet' : 'Last backup',
            style: TextStyle(
              color: p.text,
              fontSize: 21,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            none
                ? 'Backups are never made automatically.'
                : '${last.createdAt.toLocal().toString().substring(0, 16)} · never made automatically',
            style: TextStyle(color: none ? p.amber : p.muted, fontSize: 16),
          ),
          const SizedBox(height: 14),
          none
              ? AppButton.primary(
                'Back up now',
                key: const Key('back-up-now'),
                height: 56,
                onPressed: () => context.push(AppRoutes.backup),
              )
              : AppButton(
                'Back up now',
                key: const Key('back-up-now'),
                height: 56,
                onPressed: () => context.push(AppRoutes.backup),
              ),
        ],
      ),
    );
  }
}

Future<void> confirmSignOut(BuildContext context, WidgetRef ref) async {
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

Future<void> _confirmClear(BuildContext context) {
  return showDialog<void>(
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

/// Sign out and the danger zone, at the bottom of the hub and of the Account page.
class SignOutAndDanger extends ConsumerWidget {
  const SignOutAndDanger({super.key, this.title = 'Danger zone'});

  final String title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppButton(
          'Sign out',
          key: const Key('sign-out-tile'),
          height: 56,
          onPressed: () => confirmSignOut(context, ref),
        ),
        const SizedBox(height: AppTheme.gap),
        Container(
          padding: const EdgeInsets.all(AppTheme.cardPadding),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(color: p.red.withValues(alpha: 0.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: p.red,
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title == 'Danger zone'
                    ? 'Delete selected data or reset the app. This cannot be undone.'
                    : 'Delete selected data or reset the app. You type DELETE to confirm. This cannot be undone.',
                style: TextStyle(color: p.muted, fontSize: 16, height: 1.3),
              ),
              const SizedBox(height: 14),
              AppButton(
                'Clear data…',
                kind: ButtonKind.danger,
                height: 56,
                onPressed: () => _confirmClear(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The development-only live sync check, shown in debug builds on the Data & sync page.
Widget debugSyncCheck() => kDebugMode ? const SyncCheckCard() : const SizedBox.shrink();
