import 'package:flutter/material.dart';

import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/meters.dart';
import '../../../core/theme/app_theme.dart';

/// Reports section: analytics tabs plus the export centre and backup.
/// Figures are placeholders; exporting is wired up when the report endpoints exist (decision D18).
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const _periods = ['This week', 'This month', 'Quarter', 'Year', 'Custom'];
  static const _tabs = ['Overview', 'Workouts', 'Strength', 'Body', 'Export'];
  int _period = 0;
  int _tab = 0;

  List<Widget> _content() {
    switch (_tab) {
      case 1:
        return const [_Performance(), _Consistency(), _CompareCard(title: 'Compare periods')];
      case 2:
        return const [_StrengthHighlights(), _DetailedReports()];
      case 3:
        return const [_BodyChanges(), _MuscleRadar()];
      case 4:
        return const [
          _ExportReports(),
          _ReportingPeriod(),
          _Categories(),
          _IncludeInExport(),
          _ReportPreview(),
          _ExportHistory(),
          GroupLabel('Backup'),
          _Backup(),
        ];
      default:
        return const [
          GroupLabel('Analytics'),
          _Performance(),
          _Consistency(),
          _StrengthHighlights(),
          _BodyChanges(),
          _MuscleRadar(),
          GroupLabel('Export'),
          _ExportReports(),
          _ExportHistory(),
          _Backup(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Reports',
      subtitle: 'Analyze history and export',
      children: [
        PillTabs(labels: _periods, index: _period, container: true, layout: PillLayout.scroll, onChanged: (i) => setState(() => _period = i)),
        PillTabs(labels: _tabs, index: _tab, container: true, layout: PillLayout.scroll, onChanged: (i) => setState(() => _tab = i)),
        ..._content(),
      ],
    );
  }
}

class _Performance extends StatelessWidget {
  const _Performance();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Performance overview', sample: true, children: [
      Row(children: [
        Expanded(child: StatBlock('3 / 4', 'Workouts', size: 26)),
        Expanded(child: StatBlock('12,450 kg', 'Total volume', size: 26)),
      ]),
      SizedBox(height: 18),
      Row(children: [
        Expanded(child: StatBlock('3 h 45 m', 'Total time', size: 26)),
        Expanded(child: StatBlock('+6.2 %', 'vs last week', size: 26)),
      ]),
    ]);
  }
}

class _Consistency extends StatelessWidget {
  const _Consistency();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Workout consistency', sample: true, link: 'Last 4 weeks', children: [
      Row(children: [
        RingGauge(value: 0.75, centerText: '75%', subText: '12 / 16', size: 104, stroke: 9),
        SizedBox(width: 14),
        Expanded(
          child: BarChartView(
            values: [3, 2, 4, 3],
            labels: ['W1', 'W2', 'W3', 'W4'],
            maxValue: 4,
            height: 120,
            barWidth: 28,
          ),
        ),
      ]),
      SizedBox(height: 12),
      MutedText('Last 4 weeks. Planned breaks and rest days are excluded.'),
    ]);
  }
}

class _StrengthHighlights extends StatelessWidget {
  const _StrengthHighlights();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Strength highlights', sample: true, link: 'Details', children: [
      RowList([
        RowItem(title: 'Bench Press', trailing: '+2.5 kg'),
        RowItem(title: 'Barbell Row', trailing: '+5.0 kg'),
        RowItem(title: 'Squat', trailing: '+5.0 kg'),
      ]),
    ]);
  }
}

class _BodyChanges extends StatelessWidget {
  const _BodyChanges();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget col(String v, String l, String d) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(v, style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(l, style: TextStyle(color: p.muted, fontSize: 14)),
            Text(d, style: TextStyle(color: p.muted, fontSize: 14)),
          ]),
        );
    return TitledCard(title: 'Body changes', sample: true, link: 'Details', children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        col('78.0 kg', 'Weight', '▼ 0.6 kg'),
        col('18.4 %', 'Body fat', '▼ 0.4 %'),
      ]),
      const SizedBox(height: 14),
      const MutedText('Body-fat readings are compared only within the same method.', size: 15),
    ]);
  }
}

class _MuscleRadar extends StatelessWidget {
  const _MuscleRadar();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Muscle development · self-assessed', sample: true, link: 'Details', children: [
      RadarChartView(
        labels: ['Chest', 'Shoulders', 'Back', 'Arms', 'Abs', 'Forearms', 'Calves', 'Glutes'],
        values: [0.8, 0.7, 0.55, 0.3, 0.2, 0.5, 0.25, 0.2],
      ),
      MutedText('Your own 1–5 ratings, not measured growth.', size: 15),
    ]);
  }
}

class _CompareCard extends StatefulWidget {
  const _CompareCard({required this.title});
  final String title;

  @override
  State<_CompareCard> createState() => _CompareCardState();
}

class _CompareCardState extends State<_CompareCard> {
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: widget.title, sample: true, children: [
      PillTabs(labels: const ['Month vs month', 'Custom'], index: _mode, onChanged: (i) => setState(() => _mode = i)),
      const SizedBox(height: 8),
      const RowList([
        RowItem(title: 'Workouts', subtitle: '12 vs 11', trailing: '+1'),
        RowItem(title: 'Volume', subtitle: 'Oct vs Sep', trailing: '+6.2%'),
        RowItem(title: 'Avg sleep', trailing: '6.8 vs 6.5 h'),
      ]),
    ]);
  }
}

class _DetailedReports extends StatelessWidget {
  const _DetailedReports();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Detailed reports', children: [
      RowList([
        RowItem(title: 'Workout report', subtitle: 'Sessions, volume, attendance', chevron: true),
        RowItem(title: 'Strength progression', subtitle: 'Lifts, PRs, estimated 1RM', chevron: true),
        RowItem(title: 'Body composition', subtitle: 'Weight, body fat, measurements', chevron: true),
        RowItem(title: 'Muscle development', subtitle: 'Self-assessment history', chevron: true),
        RowItem(title: 'Lifestyle & nutrition', subtitle: 'Sleep, meals, supplements, activity', chevron: true),
        RowItem(title: 'Goal achievement', subtitle: 'Milestones and dates', chevron: true),
      ]),
    ]);
  }
}

// ---- Export ----

class _ExportReports extends StatefulWidget {
  const _ExportReports();

  @override
  State<_ExportReports> createState() => _ExportReportsState();
}

class _ExportReportsState extends State<_ExportReports> {
  int _format = 0;

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: 'Export reports', children: [
      const Row(children: [
        Expanded(child: LabeledField('Start', initial: 'Oct 1')),
        SizedBox(width: 12),
        Expanded(child: LabeledField('End', initial: 'Nov 4')),
      ]),
      const SizedBox(height: 10),
      const MutedText('End date should be on or after the start date.', size: 14),
      const SizedBox(height: 12),
      ButtonPair(AppButton('Monthly', onPressed: () {}), AppButton('Yearly', onPressed: () {})),
      const SizedBox(height: 10),
      AppButton('Custom range', onPressed: () {}),
      const SizedBox(height: 12),
      PillTabs(labels: const ['Excel .xlsx', 'PDF'], index: _format, onChanged: (i) => setState(() => _format = i)),
      const SizedBox(height: 12),
      AppButton.primary('Generate report', onPressed: () {}),
    ]);
  }
}

class _ReportingPeriod extends StatefulWidget {
  const _ReportingPeriod();

  @override
  State<_ReportingPeriod> createState() => _ReportingPeriodState();
}

class _ReportingPeriodState extends State<_ReportingPeriod> {
  int _i = 4;

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: 'Reporting period', children: [
      const InnerTile(
        child: Text(
          'Oct 1 – Nov 4, 2026\nChoose an existing range or make a custom report',
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 12),
      PillTabs(
        labels: const ['This week', 'This month', 'Quarter', 'Year', 'Custom'],
        index: _i,
        layout: PillLayout.scroll,
        onChanged: (v) => setState(() => _i = v),
      ),
    ]);
  }
}

class _Categories extends StatefulWidget {
  const _Categories();

  @override
  State<_Categories> createState() => _CategoriesState();
}

class _CategoriesState extends State<_Categories> {
  static const _items = [
    ('Workouts', 'Sessions and attendance'),
    ('Strength progression', 'Lifts and PRs'),
    ('Body composition', 'Weight, body fat, measurements'),
    ('Muscle development', 'Self-assessment'),
    ('Lifestyle & nutrition', 'Sleep, meals, supplements'),
    ('Goal achievement', 'Goals and milestones'),
  ];
  final List<bool> _on = [true, true, true, true, false, true];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(title: 'Report categories', children: [
      Text('Oct 1 – Nov 4', style: TextStyle(color: p.link, fontSize: 15)),
      const SizedBox(height: 8),
      for (var i = 0; i < _items.length; i++) ...[
        if (i > 0) Divider(height: 1, color: p.divider),
        ToggleRow(
          title: _items[i].$1,
          subtitle: _items[i].$2,
          value: _on[i],
          onChanged: (v) => setState(() => _on[i] = v),
        ),
      ],
      const SizedBox(height: 12),
      ButtonPair(AppButton('Preview', onPressed: () {}), AppButton.primary('Generate', onPressed: () {})),
    ]);
  }
}

class _IncludeInExport extends StatelessWidget {
  const _IncludeInExport();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget dot(bool on) => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(shape: BoxShape.circle, color: on ? p.greenFill : p.tile),
          child: on ? Icon(Icons.check, size: 15, color: p.green) : null,
        );
    return TitledCard(title: 'Include in export', children: [
      RowList([
        RowItem(title: 'Workouts', leading: dot(true)),
        RowItem(title: 'Strength progression', leading: dot(true)),
        RowItem(title: 'Body composition', leading: dot(true)),
        RowItem(title: 'Muscle development', leading: dot(true)),
        RowItem(title: 'Lifestyle & nutrition', leading: dot(false)),
        RowItem(title: 'Goal achievement', leading: dot(false)),
      ]),
    ]);
  }
}

class _ReportPreview extends StatelessWidget {
  const _ReportPreview();

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: 'Report preview', sample: true, children: [
      const Text('Workout report · Oct 1 – Nov 4', style: TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      const MutedText('12 sessions · 48,320 kg · 3 PRs'),
      const SizedBox(height: 12),
      ButtonPair(AppButton('Excel', onPressed: () {}), AppButton('PDF', onPressed: () {})),
    ]);
  }
}

class _ExportHistory extends StatelessWidget {
  const _ExportHistory();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Export history', sample: true, children: [
      RowList([
        RowItem(title: 'Monthly report · Oct 2026', subtitle: 'PDF · Nov 1', trailing: 'Open'),
        RowItem(title: 'Custom · Sep 1 – Oct 15', subtitle: 'Excel · Oct 16', trailing: 'Open'),
      ]),
    ]);
  }
}

class _Backup extends StatelessWidget {
  const _Backup();

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: 'Backup & restore', children: [
      const MutedText('Full app data, separate from Excel / PDF reports.', size: 15),
      const SizedBox(height: 6),
      const RowList([RowItem(title: 'Last backup', subtitle: 'Not yet made')]),
      const SizedBox(height: 12),
      ButtonPair(AppButton('Back up now', onPressed: () {}), AppButton('Restore…', onPressed: () {})),
    ]);
  }
}
