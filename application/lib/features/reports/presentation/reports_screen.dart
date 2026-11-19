import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/backend/reporting_gateway.dart'
    show reportingConfiguredProvider;
import '../../../core/insights/insight_repository.dart' show InsightFreshness;
import '../../../core/sync/sync_status.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/insight_status.dart' show ageText;
import '../../../core/widgets/section_widgets.dart';
import '../../../core/widgets/tab_slider.dart';
import '../../training/presentation/training_dialogs.dart' show ModalCard;
import '../data/report_period.dart';
import '../data/report_repository.dart';
import 'export_tab.dart';
import 'report_sections.dart';

const reportTabs = [
  'Overview',
  'Workouts',
  'Strength',
  'Body',
  'Lifestyle',
  'Goals',
  'Export',
];

/// Index of a tab named in a link such as `/reports?tab=export`.
int reportTabIndex(String? name) {
  final i = reportTabs.indexWhere(
    (t) => t.toLowerCase() == (name ?? '').toLowerCase(),
  );
  return i < 0 ? 0 : i;
}

/// Reports: what the reporting service worked out about a period, plus exports and backup.
/// Every figure comes from the server; the phone only shows it and keeps the last answer for offline use.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key, this.initialTab});

  final String? initialTab;

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  late int _tab = reportTabIndex(widget.initialTab);

  Future<void> _pickRange(ReportQuery current) async {
    final now = DateTime.now();
    final range = current.range;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange:
          range == null
              ? null
              : DateTimeRange(
                start: range.$1,
                end: range.$2.isAfter(now) ? now : range.$2,
              ),
      helpText: 'Report range (up to $maxCustomDays days)',
    );
    if (picked == null || !mounted) return;
    ref.read(reportQueryProvider.notifier).state = ReportQuery.custom(
      picked.start,
      picked.end,
    );
  }

  void _selectKind(int i) {
    final kind = ReportKind.values[i];
    final current = ref.read(reportQueryProvider);
    if (kind == current.kind && kind != ReportKind.custom) return;
    final next = ReportQuery.current(kind, DateTime.now());
    ref.read(reportQueryProvider.notifier).state = next;
    if (kind == ReportKind.custom) _pickRange(next);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(reportQueryProvider);
    final request = ref.watch(reportRequestProvider);
    final compare = ref.watch(reportCompareProvider);

    // "Updated 2 min ago" once a report is on the phone; otherwise the screen's purpose.
    final configured = ref.watch(reportingConfiguredProvider);
    final usable =
        configured &&
        query.validate() == null &&
        !query.startsAfter(DateTime.now());
    final snap =
        usable ? ref.watch(reportSummaryProvider(request)).valueOrNull : null;
    final subtitle =
        snap != null && snap.hasData
            ? 'Updated ${ageText(snap.fetchedAt)}'
            : 'Analyze history and export';

    // Everything under the tab row, for tab [tab]. The slider asks for the neighbouring tab too while a swipe is in
    // progress, so this only creates widgets.
    List<Widget> items(int tab) => [
        const SizedBox(height: 14),
        PillTabs(
          labels: [for (final k in ReportKind.values) k.label],
          index: ReportKind.values.indexOf(query.kind),
          layout: PillLayout.scroll,
          container: true,
          onChanged: _selectKind,
        ),
        const SizedBox(height: 10),
        _PeriodBar(
          query: query,
          onPickRange: () => _pickRange(query),
          onChanged: (q) => ref.read(reportQueryProvider.notifier).state = q,
        ),
        if (tab == 0)
          ToggleRow(
            title: 'Compare with the previous period',
            subtitle: 'Adds change figures to the Overview',
            value: compare,
            onChanged:
                (v) => ref.read(reportCompareProvider.notifier).state = v,
          ),
        const _UnsyncedNotice(),
        const SizedBox(height: 4),
        if (tab == reportTabs.length - 1)
          ExportTab(request: request)
        else
          _ReportBody(request: request, tab: tab),
        const SizedBox(height: 8),
    ];

    return ScreenFrame(
      title: 'Reports',
      subtitle: subtitle,
      trailing: HeaderIconButton(
        key: const Key('reports-info'),
        icon: Icons.info_outline,
        tooltip: 'About reports',
        onTap:
            () => showDialog<void>(
              context: context,
              builder: (_) => _AboutDialog(request: request),
            ),
      ),
      children: [
        UnderlineTabs(
          labels: reportTabs,
          index: _tab,
          onChanged: (i) => setState(() => _tab = i),
        ),
        TabSlider(
          index: _tab,
          count: reportTabs.length,
          onChanged: (i) => setState(() => _tab = i),
          builder: (i) => TabSlider.page(items(i)),
        ),
      ],
    );
  }
}

/// What the figures are and where they come from, with a way to ask the server again.
class _AboutDialog extends ConsumerWidget {
  const _AboutDialog({required this.request});

  final ReportRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final configured = ref.watch(reportingConfiguredProvider);
    return ModalCard(
      title: 'About reports',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Calculated by the server from your records. The phone only shows the figures and keeps the last answer for offline use.\n\nNot medical advice.',
            style: TextStyle(color: p.muted, fontSize: 16, height: 1.4),
          ),
          if (configured) ...[
            const SizedBox(height: 16),
            AppButton(
              'Refresh report',
              key: const Key('report-refresh'),
              height: 52,
              onPressed: () {
                ref.read(reportSummaryProvider(request).notifier).refresh();
                Navigator.of(context).pop();
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PeriodBar extends StatelessWidget {
  const _PeriodBar({
    required this.query,
    required this.onPickRange,
    required this.onChanged,
  });
  final ReportQuery query;
  final VoidCallback onPickRange;
  final ValueChanged<ReportQuery> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final canStep = query.canStep;
    final nextPeriod = query.shifted(1);
    final nextPeriodStart = nextPeriod.range?.$1;
    final today = DateUtils.dateOnly(DateTime.now());

    final nextBlocked =
        !canStep ||
        (nextPeriodStart != null &&
            !DateUtils.dateOnly(nextPeriodStart).isBefore(today));
    return AppCard(
      child: Row(
        children: [
          if (canStep)
            IconButton(
              key: const Key('period-prev'),
              tooltip: 'Previous period',
              onPressed: () => onChanged(query.shifted(-1)),
              icon: const Icon(Icons.chevron_left),
            ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: query.kind == ReportKind.custom ? onPickRange : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    query.label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: p.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (query.kind == ReportKind.custom)
                    Text(
                      'Tap to change',
                      style: TextStyle(color: p.link, fontSize: 12),
                    ),
                  if (query.kind == ReportKind.complete)
                    Text(
                      'From your first record to today',
                      style: TextStyle(color: p.muted, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          if (canStep)
            IconButton(
              key: const Key('period-next'),
              tooltip: 'Next period',
              onPressed: nextBlocked ? null : () => onChanged(nextPeriod),
              icon: const Icon(Icons.chevron_right),
            ),
        ],
      ),
    );
  }
}

/// Shown when changes made on this phone have not reached the server yet. Reports are worked out on the server.
class _UnsyncedNotice extends ConsumerWidget {
  const _UnsyncedNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(syncStatusProvider.select((s) => s.pendingCount));
    if (pending == 0) return const SizedBox.shrink();
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 6),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$pending ${pending == 1 ? 'change' : 'changes'} on this phone ${pending == 1 ? 'has' : 'have'} not synced yet',
              style: TextStyle(
                color: p.amber,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            const MutedText(
              'Reports are calculated on the server, so they do not include these changes until they sync.',
              size: 13,
            ),
            const SizedBox(height: 6),
            LinkText(
              'Sync now',
              onTap: () => ref.read(syncStatusProvider.notifier).syncNow(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportBody extends ConsumerWidget {
  const _ReportBody({required this.request, required this.tab});
  final ReportRequest request;
  final int tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = request.query;
    final problem = query.validate();

    if (problem != null) {
      return _Message(
        title: 'This period cannot be used',
        text: problem,
        icon: Icons.event_busy_outlined,
      );
    }
    if (query.startsAfter(DateTime.now())) {
      return const _Message(
        title: 'This period has not started',
        text: 'There are no records in the future. Go back to see a report.',
        icon: Icons.schedule_outlined,
      );
    }

    final configured = ref.watch(reportingConfiguredProvider);

    if (!configured) {
      return const _Message(
        title: 'Reports are not set up',
        text:
            'This build has no reporting service address. Set REPORT_API_URL and rebuild the app.',
        icon: Icons.settings_outlined,
      );
    }

    final async = ref.watch(reportSummaryProvider(request));
    final snap = async.valueOrNull;

    if (snap == null) {
      if (async.hasError) {
        return _Message(
          title: 'Could not load the report',
          text: '${async.error}',
          icon: Icons.error_outline,
        );
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final refresh =
        snap.refreshing
            ? null
            : () => ref.read(reportSummaryProvider(request).notifier).refresh();
    final showStatus =
        snap.refreshing ||
        snap.error != null ||
        !snap.hasData ||
        snap.freshness == InsightFreshness.stale;
    final children = <Widget>[
      if (showStatus) ...[
        _StatusLine(snapshot: snap, configured: configured, onRefresh: refresh),
        const SizedBox(height: 12),
      ],
    ];
    final summary = snap.summary;
    if (summary == null) {
      if (snap.refreshing) {
        children.add(
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          ),
        );
      } else {
        children.add(
          _Message(
            title:
                !configured
                    ? 'Reports are not set up'
                    : (snap.isOffline ? 'You are offline' : 'No report yet'),
            text:
                !configured
                    ? 'This build has no reporting service address. Set REPORT_API_URL and rebuild the app.'
                    : (snap.isOffline
                        ? 'This period has not been loaded on this phone yet. Connect to the internet and try again.'
                        : 'The report could not be loaded yet.'),
            icon:
                !configured
                    ? Icons.settings_outlined
                    : (snap.isOffline
                        ? Icons.cloud_off_outlined
                        : Icons.insert_chart_outlined),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      );
    }
    switch (tab) {
      case 0:
        children.add(OverviewSection(summary: summary));
      case 1:
        children.add(WorkoutsSection(summary: summary));
      case 2:
        children.add(StrengthSectionView(summary: summary));
      case 3:
        children.add(BodySectionView(summary: summary));
      case 4:
        children.add(LifestyleSectionView(summary: summary));
      default:
        children.add(GoalsSectionView(summary: summary));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.snapshot,
    required this.configured,
    required this.onRefresh,
  });
  final ReportSnapshot snapshot;
  final bool configured;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final String text;
    var warn = false;
    if (snapshot.refreshing) {
      text = 'Updating from the server…';
    } else if (snapshot.error != null) {
      warn = true;
      text =
          snapshot.hasData
              ? '${snapshot.isOffline ? 'Offline' : 'Could not update'}. Showing the report from ${ageText(snapshot.fetchedAt)}. ${snapshot.isOffline ? '' : snapshot.error!.message}'
                  .trim()
              : snapshot.error!.message;
    } else if (snapshot.hasData) {
      final old = snapshot.freshness == InsightFreshness.stale;
      text =
          'Calculated by the server. Updated ${ageText(snapshot.fetchedAt)}${old ? ' (may be out of date)' : ''}.';
    } else {
      text = 'Not loaded yet.';
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              color: warn ? p.amber : p.muted,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
        if (configured && onRefresh != null)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: LinkText('Refresh', onTap: onRefresh!),
          ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.title, required this.text, required this.icon});
  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      child: Column(
        children: [
          Icon(icon, size: 36, color: p.muted),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: p.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          MutedText(text, align: TextAlign.center),
        ],
      ),
    );
  }
}
