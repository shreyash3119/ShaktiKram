import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/meters.dart';

/// Progress section: Overview, Strength, Body, Muscles and Goals.
/// Charts and lists use placeholder values until the data is synced locally.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  static const _tabs = ['Overview', 'Strength', 'Body', 'Muscles', 'Goals'];
  int _tab = 0;

  List<Widget> _content() {
    switch (_tab) {
      case 1:
        return const [_StrengthChart(), _PrHistory(), _ComparePeriods()];
      case 2:
        return const [
          _BodyWeight(),
          _BodyComposition(),
          _MeasurementHistory(),
          _PhotosCard(),
        ];
      case 3:
        return const [
          _MusclesAssessment(),
          _RearDeltsAssessment(),
          _WeakPoints(),
          _VolumeByMuscle(),
          _Frequency(),
        ];
      case 4:
        return const [_GoalsCard(), _GoalMilestones(), _Milestones()];
      default:
        return const [
          _Highlights(),
          _StrengthChart(),
          _PrHistorySmall(),
          _BodyLast(),
          _GoalsCard(),
          _MusclesAssessment(),
          _Exposure(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Progress',
      subtitle: 'Your history and change over time',
      children: [
        PillTabs(
          labels: _tabs,
          index: _tab,
          container: true,
          layout: PillLayout.scroll,
          onChanged: (i) => setState(() => _tab = i),
        ),
        ..._content(),
      ],
    );
  }
}

class _Highlights extends StatelessWidget {
  const _Highlights();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget col(String label, String value, String note) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: p.muted, fontSize: 13)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: p.text,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(note, style: TextStyle(color: p.muted, fontSize: 13)),
        ],
      ),
    );
    return TitledCard(
      title: 'Recent highlights',
      sample: true,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            col('Latest PR', 'Bench Press 85 kg', 'Nov 2, 2026'),
            const SizedBox(width: 12),
            col('Workout streak', '3 days', 'This week 3 / 4'),
          ],
        ),
      ],
    );
  }
}

class _StrengthChart extends StatefulWidget {
  const _StrengthChart();

  @override
  State<_StrengthChart> createState() => _StrengthChartState();
}

class _StrengthChartState extends State<_StrengthChart> {
  int _metric = 0;

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Strength',
      sample: true,
      children: [
        PillTabs(
          labels: const ['Bench Press ▾', 'Top set', 'Est. 1RM'],
          index: _metric,
          layout: PillLayout.wrap,
          onChanged: (i) => setState(() => _metric = i),
        ),
        const SizedBox(height: 12),
        const LineChartView(
          values: [63, 69, 72, 78, 83],
          xLabels: ['Sep 1', 'Sep 15', 'Oct 1', 'Oct 15', 'Nov 1'],
          yMin: 60,
          yMax: 90,
          yTicks: [60, 70, 80, 90],
        ),
        const SizedBox(height: 10),
        const MutedText(
          'Top working set (kg) per session. Latest 85 kg, previous 82.5 kg.',
        ),
      ],
    );
  }
}

class _PrHistorySmall extends StatelessWidget {
  const _PrHistorySmall();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'PR history',
      link: 'All PRs',
      children: [
        RowList([
          RowItem(
            title: 'Bench Press',
            subtitle: 'New weight · Nov 2',
            trailing: '85 kg × 5',
          ),
          RowItem(
            title: 'Bench Press',
            subtitle: 'Estimated 1RM · Oct 28',
            trailing: '97.8 kg',
          ),
          RowItem(
            title: 'Bench Press',
            subtitle: 'Best reps · Nov 2',
            trailing: '+1 rep at 82.5 kg',
          ),
        ]),
      ],
    );
  }
}

class _PrHistory extends StatefulWidget {
  const _PrHistory();

  @override
  State<_PrHistory> createState() => _PrHistoryState();
}

class _PrHistoryState extends State<_PrHistory> {
  int _filter = 0;

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'PR history',
      link: 'All',
      children: [
        PillTabs(
          labels: const ['All exercises', 'Any date'],
          index: _filter,
          onChanged: (i) => setState(() => _filter = i),
        ),
        const SizedBox(height: 8),
        const RowList([
          RowItem(
            title: 'Squat',
            subtitle: 'New weight · Oct 27',
            trailing: '110 kg',
          ),
          RowItem(
            title: 'Barbell Row',
            subtitle: 'New weight · Oct 30',
            trailing: '65 kg',
          ),
          RowItem(
            title: 'Bench Press',
            subtitle: 'Best reps · Nov 2',
            trailing: '+1 rep',
          ),
        ]),
      ],
    );
  }
}

class _ComparePeriods extends StatefulWidget {
  const _ComparePeriods();

  @override
  State<_ComparePeriods> createState() => _ComparePeriodsState();
}

class _ComparePeriodsState extends State<_ComparePeriods> {
  int _mode = 0;

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Compare periods',
      sample: true,
      children: [
        PillTabs(
          labels: const ['This month vs last', 'Custom'],
          index: _mode,
          onChanged: (i) => setState(() => _mode = i),
        ),
        const SizedBox(height: 8),
        const RowList([
          RowItem(title: 'Workouts', trailing: '12 vs 10'),
          RowItem(title: 'Bench Press top set', trailing: '85 vs 80 kg'),
          RowItem(title: 'Weight', trailing: '78.0 vs 78.6 kg'),
        ]),
      ],
    );
  }
}

class _BodyLast extends StatelessWidget {
  const _BodyLast();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Body · last measured Nov 2',
      link: 'History',
      children: [
        RowList([
          RowItem(
            title: 'Weight',
            subtitle: 'Smart scale · down 0.6 kg',
            trailing: '78.0 kg',
          ),
          RowItem(
            title: 'Body fat',
            subtitle: 'Smart-scale reading',
            trailing: '18.4%',
          ),
          RowItem(
            title: 'Waist',
            subtitle: 'Tape measurement',
            trailing: '82 cm',
          ),
        ]),
        SizedBox(height: 10),
        MutedText('Averages from different methods may not be comparable.'),
      ],
    );
  }
}

class _GoalsCard extends StatelessWidget {
  const _GoalsCard();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget goal(String title, String detail, double v, String pct) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(detail, style: TextStyle(color: p.muted, fontSize: 13.5)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: MeterBar(value: v)),
              SizedBox(
                width: 48,
                child: Text(
                  pct,
                  textAlign: TextAlign.right,
                  style: TextStyle(color: p.text, fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    return TitledCard(
      title: 'Goals',
      sample: true,
      link: 'Settings',
      children: [
        goal(
          'Cut to 75 kg',
          'Start 80.0 · current 78.0 kg · target date Dec 31',
          0.4,
          '40%',
        ),
        goal(
          'Bench Press 90 kg',
          'Start 75.0 · current 85 · target date Jan 31',
          0.67,
          '67%',
        ),
        const SizedBox(height: 6),
        const MutedText(
          'Progress is a guide, not a promise. Adjust goals to real-life changes.',
        ),
      ],
    );
  }
}

class _GoalMilestones extends StatelessWidget {
  const _GoalMilestones();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Goal milestones',
      sample: true,
      children: [
        RowItem(
          title: 'Bench Press 90 kg',
          subtitle: '85 / 90 kg · 5 kg to go',
          trailing: '67%',
        ),
        SizedBox(height: 4),
        MeterBar(value: 0.67),
      ],
    );
  }
}

class _Milestones extends StatelessWidget {
  const _Milestones();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget tick() => Icon(Icons.check, size: 18, color: p.text);
    return TitledCard(
      title: 'Milestones',
      sample: true,
      children: [
        RowList([
          RowItem(title: '80% of 75 kg', trailing: 'Nov 2', leading: tick()),
          RowItem(title: '80% of 90 kg', trailing: 'Nov 2', leading: tick()),
          const RowItem(title: 'Bench 90 kg', trailing: 'Target'),
        ]),
      ],
    );
  }
}

class _MusclesAssessment extends StatelessWidget {
  const _MusclesAssessment();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const rows = [
      ('Rear delts', 2),
      ('Calves', 3),
      ('Forearms', 4),
      ('Side delts', 2),
      ('Front delts', 3),
    ];
    return TitledCard(
      title: 'Muscles · self-assessment',
      link: 'Reassess',
      children: [
        const MutedText(
          'Relative scores from 1–5. Reassess every 2–4 weeks to adjust your priorities and exercise choices.',
        ),
        const SizedBox(height: 8),
        for (final r in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    r.$1,
                    style: TextStyle(color: p.muted, fontSize: 14.5),
                  ),
                ),
                DotRating(r.$2),
              ],
            ),
          ),
        const SizedBox(height: 8),
        const MutedText('Last assessed Nov 2.'),
      ],
    );
  }
}

class _Exposure extends StatelessWidget {
  const _Exposure();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Training exposure · last 4 weeks',
      sample: true,
      children: [
        MutedText(
          'Muscles from your ratings deserve focus or exercise variety.',
        ),
        SizedBox(height: 6),
        RowList([
          RowItem(
            title: 'Rear delts',
            subtitle: 'Direct work · weekly',
            trailing: '4 sets',
          ),
          RowItem(
            title: 'Abs',
            subtitle: 'Direct work · weekly',
            trailing: '6 sets',
          ),
        ]),
      ],
    );
  }
}

class _BodyWeight extends StatefulWidget {
  const _BodyWeight();

  @override
  State<_BodyWeight> createState() => _BodyWeightState();
}

class _BodyWeightState extends State<_BodyWeight> {
  int _range = 0;

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Body weight',
      sample: true,
      children: [
        PillTabs(
          labels: const ['1M', '3M', '6M', '1Y', 'Custom'],
          index: _range,
          onChanged: (i) => setState(() => _range = i),
        ),
        const SizedBox(height: 10),
        const LineChartView(
          values: [79.6, 79.2, 78.9, 78.5, 78.3, 77.9, 77.0],
          xLabels: ['Sep 1', '', 'Sep 15', 'Oct 1', 'Oct 15', '', 'Nov 1'],
          yMin: 77,
          yMax: 80,
          yTicks: [77, 78, 79, 80],
        ),
        const SizedBox(height: 10),
        const MutedText(
          'Weight trends adjusted for daily fluctuations. Compare longer periods for context.',
        ),
      ],
    );
  }
}

class _BodyComposition extends StatelessWidget {
  const _BodyComposition();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Body composition',
      sample: true,
      link: 'Add reading',
      children: [
        RowList([
          RowItem(
            title: 'Weight',
            subtitle: 'Smart scale',
            trailing: '78.0 kg',
          ),
          RowItem(
            title: 'Body fat',
            subtitle: 'Smart scale estimate',
            trailing: '18.4%',
          ),
          RowItem(
            title: 'Fat mass',
            subtitle: 'Calculated: weight × body fat %',
            trailing: '14.3 kg',
          ),
          RowItem(
            title: 'Lean mass',
            subtitle: 'Calculated estimate',
            trailing: '63.7 kg',
          ),
        ]),
        SizedBox(height: 10),
        MutedText(
          'Smart-scale readings vary; compare consistent measurement methods.',
        ),
      ],
    );
  }
}

class _MeasurementHistory extends StatelessWidget {
  const _MeasurementHistory();

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Measurement history',
      sample: true,
      link: 'Add',
      children: [
        const RowList([
          RowItem(title: 'Waist', subtitle: 'Nov 2', trailing: '82 cm'),
          RowItem(title: 'Chest', subtitle: 'Nov 2', trailing: '99 cm'),
          RowItem(title: 'Arm', subtitle: 'Nov 2', trailing: '34 cm'),
          RowItem(title: 'Thigh', subtitle: 'Nov 2', trailing: '57 cm'),
        ]),
        const SizedBox(height: 12),
        AppButton('Add measurement', onPressed: () {}),
      ],
    );
  }
}

class _PhotosCard extends StatelessWidget {
  const _PhotosCard();

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Progress photos',
      children: [
        AppButton('Timeline / calendar', onPressed: () {}),
        const RowList([
          RowItem(
            title: 'Photo history',
            subtitle: 'Private, device-only',
            trailing: 'Later',
          ),
        ]),
      ],
    );
  }
}

class _RearDeltsAssessment extends StatefulWidget {
  const _RearDeltsAssessment();

  @override
  State<_RearDeltsAssessment> createState() => _RearDeltsAssessmentState();
}

class _RearDeltsAssessmentState extends State<_RearDeltsAssessment> {
  int _priority = 0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Muscle assessment · rear delts',
      children: [
        const MutedText(
          'Rate each muscle 1–5. Use the same conditions for tracking.',
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Rear delts',
                    style: TextStyle(
                      color: p.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Priority: high · weak point',
                    style: TextStyle(color: p.muted, fontSize: 13.5),
                  ),
                ],
              ),
            ),
            const DotRating(2),
          ],
        ),
        const SizedBox(height: 12),
        PillTabs(
          labels: const ['P1', 'P2', 'P3'],
          index: _priority,
          onChanged: (i) => setState(() => _priority = i),
        ),
        const SizedBox(height: 12),
        AppButton('Reassess this Nov 16', onPressed: () {}),
      ],
    );
  }
}

class _WeakPoints extends StatelessWidget {
  const _WeakPoints();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Weak points & priorities',
      children: [
        const MutedText('Your current priorities'),
        RowList([
          RowItem(
            title: 'Rear delts',
            subtitle: 'Score 1 · reassessment Nov 2',
            trailing: 'High · P1',
            trailingColor: p.amber,
          ),
          RowItem(
            title: 'Obliques',
            subtitle: 'Score 1',
            trailing: 'High · P1',
            trailingColor: p.amber,
          ),
          const RowItem(
            title: 'Abs',
            subtitle: 'Score 2',
            trailing: 'Medium · P2',
          ),
        ]),
        const SizedBox(height: 10),
        const MutedText('Next reassessment due Nov 16.'),
        const SizedBox(height: 12),
        AppButton('Reassess now', onPressed: () {}),
      ],
    );
  }
}

class _VolumeByMuscle extends StatelessWidget {
  const _VolumeByMuscle();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Training volume by muscle',
      sample: true,
      children: [
        const MutedText(
          'Estimated hard sets this week. Primary muscle = 1.0 set.',
        ),
        const SizedBox(height: 8),
        const MeterRow(
          label: 'Chest',
          value: 0.75,
          trailing: '12',
          trailingWidth: 30,
        ),
        const MeterRow(
          label: 'Back',
          value: 0.88,
          trailing: '14',
          trailingWidth: 30,
        ),
        const MeterRow(
          label: 'Shoulders',
          value: 0.69,
          trailing: '11',
          trailingWidth: 30,
        ),
        MeterRow(
          label: 'Rear delts',
          value: 0.25,
          trailing: '4',
          color: p.amber,
          trailingWidth: 30,
        ),
        MeterRow(
          label: 'Abs',
          value: 0.38,
          trailing: '6',
          color: p.amber,
          trailingWidth: 30,
        ),
        const MeterRow(
          label: 'Legs',
          value: 1.0,
          trailing: '16',
          trailingWidth: 30,
        ),
      ],
    );
  }
}

class _Frequency extends StatelessWidget {
  const _Frequency();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Frequency & exposure',
      sample: true,
      children: [
        RowList([
          RowItem(
            title: 'Chest',
            subtitle: 'Direct training · 1× last week',
            trailing: '1×/wk',
          ),
          RowItem(
            title: 'Rear delts',
            subtitle: 'Direct training',
            trailing: '1×/wk',
          ),
          RowItem(title: 'Abs', subtitle: 'Sessions per week', trailing: '2×'),
        ]),
      ],
    );
  }
}
