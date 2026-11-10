import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/meters.dart';

/// Lifestyle section: Overview, Recovery, Nutrition, Supplements and Activity.
/// Values are placeholders until the data is synced locally. Wording stays observational, never medical advice.
class LifestyleScreen extends StatefulWidget {
  const LifestyleScreen({super.key});

  @override
  State<LifestyleScreen> createState() => _LifestyleScreenState();
}

class _LifestyleScreenState extends State<LifestyleScreen> {
  static const _tabs = [
    'Overview',
    'Recovery',
    'Nutrition',
    'Supplements',
    'Activity',
  ];
  int _tab = 0;

  List<Widget> _content() {
    switch (_tab) {
      case 1:
        return const [
          _SleepSchedule(),
          _RecoveryRating(),
          _InjuryRecords(),
          _PainCheckIn(),
          _Restrictions(),
          _Later(),
        ];
      case 2:
        return const [
          _NutritionToday(),
          _LogMeal(),
          _SavedMeals(),
          _Targets(),
          _WeeklyPlan(),
        ];
      case 3:
        return const [_SupplementsTaken(), _SupplementSchedule()];
      case 4:
        return const [_ActivityCard(), _LogCardio(), _Hydration()];
      default:
        return const [
          _TodayLifestyle(),
          _RecoveryReadiness(),
          _SleepBars(),
          _SupplementsTaken(),
          _MealsCompleted(),
          _Hydration(),
          _ActivityCard(),
          _QuickLog(),
          _InjuriesNotes(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Lifestyle',
      subtitle: 'Recovery, nutrition and daily activity',
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

class _TodayLifestyle extends StatelessWidget {
  const _TodayLifestyle();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget tile(
      String label,
      String value,
      double v,
      String foot, {
      Color? color,
    }) => InnerTile(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: p.muted, fontSize: 14)),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: p.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          MeterBar(value: v, color: color, trackColor: p.card),
          const SizedBox(height: 6),
          Text(foot, style: TextStyle(color: p.muted, fontSize: 13)),
        ],
      ),
    );
    return TitledCard(
      title: 'Today’s lifestyle',
      sample: true,
      link: 'Update',
      children: [
        ButtonPair(
          tile('Sleep', '6.8 h', 0.9, 'of 7.5 h', color: p.amber),
          tile('Meals', '3 / 4', 0.75, 'Completed'),
        ),
        const SizedBox(height: 12),
        ButtonPair(
          tile('Water', '2.4 L', 0.8, 'of 3.0 L'),
          tile('Steps', '6,420', 0.64, 'of 10,000'),
        ),
      ],
    );
  }
}

class _RecoveryReadiness extends StatelessWidget {
  const _RecoveryReadiness();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Recovery & readiness',
      sample: true,
      link: 'Check-in',
      children: [
        Row(
          children: [
            const RingGauge(
              value: 0.8,
              centerText: '8.0',
              subText: '/10',
              size: 96,
              stroke: 9,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  const MeterRow(
                    label: 'Energy',
                    value: 0.8,
                    trailing: '8/10',
                    labelWidth: 66,
                    trailingWidth: 46,
                  ),
                  const MeterRow(
                    label: 'Sleep',
                    value: 0.75,
                    trailing: '7.5/10',
                    labelWidth: 66,
                    trailingWidth: 46,
                  ),
                  MeterRow(
                    label: 'Soreness',
                    value: 0.3,
                    trailing: '3/10',
                    color: p.amber,
                    labelWidth: 66,
                    trailingWidth: 46,
                  ),
                  MeterRow(
                    label: 'Fatigue',
                    value: 0.2,
                    trailing: '2/10',
                    color: p.amber,
                    labelWidth: 66,
                    trailingWidth: 46,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const MutedText(
          'Observations from your check-in, not a medical assessment.',
        ),
      ],
    );
  }
}

class _SleepBars extends StatelessWidget {
  const _SleepBars();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const values = [6.0, 7.2, 5.6, 7.6, 6.8, 6.0, 8.1];
    final colors = [
      for (var i = 0; i < values.length; i++) i == 3 ? p.link : p.amber,
    ];
    return TitledCard(
      title: 'Sleep',
      sample: true,
      link: 'Details',
      children: [
        const MutedText('7-day average 6.8 h · target 7.5 h'),
        const SizedBox(height: 10),
        BarChartView(
          values: values,
          labels: const ['M', 'T', 'W', 'T', 'F', 'S', 'S'],
          maxValue: 8.5,
          colors: colors,
          height: 160,
          barWidth: 20,
        ),
      ],
    );
  }
}

class _SupplementsTaken extends StatelessWidget {
  const _SupplementsTaken();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget dot(bool done) => Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? p.greenFill : p.tile,
      ),
      child: done ? Icon(Icons.check, size: 14, color: p.green) : null,
    );
    return TitledCard(
      title: 'Supplements · 2 / 3 taken',
      sample: true,
      link: 'Manage',
      children: [
        RowList([
          RowItem(
            title: 'Creatine monohydrate',
            trailing: '5 g/day',
            leading: dot(true),
          ),
          RowItem(title: 'Multivitamin', trailing: '1/day', leading: dot(true)),
          RowItem(title: 'Omega-3', trailing: '2/day', leading: dot(false)),
        ]),
        const SizedBox(height: 10),
        AppButton('Add supplement', onPressed: () {}),
      ],
    );
  }
}

class _MealsCompleted extends StatelessWidget {
  const _MealsCompleted();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget dot(bool done) => Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done ? p.greenFill : p.tile,
      ),
      child: done ? Icon(Icons.check, size: 14, color: p.green) : null,
    );
    return TitledCard(
      title: 'Meals · 3 / 4 completed',
      sample: true,
      link: 'Nutrition',
      children: [
        RowList([
          RowItem(title: 'Breakfast', leading: dot(true)),
          RowItem(title: 'Lunch', leading: dot(true)),
          RowItem(title: 'Snack', leading: dot(true)),
          RowItem(title: 'Dinner', leading: dot(false)),
        ]),
        const SizedBox(height: 8),
        const MutedText('Higher effort today may mean extra nutrition.'),
      ],
    );
  }
}

class _Hydration extends StatelessWidget {
  const _Hydration();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Hydration',
      sample: true,
      children: [
        Text(
          '2.4 / 3.0 L',
          style: TextStyle(
            color: p.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(child: MeterBar(value: 0.8)),
            SizedBox(
              width: 48,
              child: Text(
                '80%',
                textAlign: TextAlign.right,
                style: TextStyle(color: p.muted, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ButtonPair(
          AppButton('+250 ml', onPressed: () {}),
          AppButton('+500 ml', onPressed: () {}),
        ),
      ],
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Activity',
      sample: true,
      link: 'Details',
      children: [
        Text(
          '6,420 / 10,000 steps',
          style: TextStyle(
            color: p.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Expanded(child: MeterBar(value: 0.64)),
            SizedBox(
              width: 48,
              child: Text(
                '64%',
                textAlign: TextAlign.right,
                style: TextStyle(color: p.muted, fontSize: 14),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        const InnerTile(child: Center(child: Text('No watch connected'))),
        const SizedBox(height: 10),
        AppButton('Log cardio', onPressed: () {}),
      ],
    );
  }
}

class _QuickLog extends StatelessWidget {
  const _QuickLog();

  @override
  Widget build(BuildContext context) {
    Widget b(String l) => AppButton(l, height: 46, onPressed: () {});
    return TitledCard(
      title: 'Quick log',
      children: [
        ButtonPair(b('Sleep log'), b('Recovery')),
        const SizedBox(height: 10),
        ButtonPair(b('Meal plan'), b('Supplements')),
        const SizedBox(height: 10),
        ButtonPair(b('Cardio'), b('Water')),
      ],
    );
  }
}

class _InjuriesNotes extends StatelessWidget {
  const _InjuriesNotes();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Injuries & notes',
      sample: true,
      link: 'All',
      children: [
        RowItem(
          title: 'Shoulder soreness',
          subtitle: 'Right · improving · after last workout',
          trailing: 'Active',
          trailingColor: p.amber,
        ),
        const MutedText('Follow any advice from a qualified clinician.'),
        const SizedBox(height: 12),
        ButtonPair(
          AppButton('View details', onPressed: () {}),
          AppButton('Record pain', onPressed: () {}),
        ),
      ],
    );
  }
}

// ---- Recovery ----

class _SleepSchedule extends StatelessWidget {
  const _SleepSchedule();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Sleep schedule',
      sample: true,
      children: [
        FieldLabel('Last night'),
        Row(
          children: [
            Expanded(child: LabeledField('Bedtime', initial: '11:30 pm')),
            SizedBox(width: 12),
            Expanded(child: LabeledField('Wake time', initial: '7:00 am')),
          ],
        ),
        SizedBox(height: 8),
        RowList([
          RowItem(
            title: 'Last night',
            subtitle: 'Sleep duration',
            trailing: '6.8 h',
          ),
          RowItem(
            title: 'Sleep efficiency',
            subtitle: 'Time asleep / time in bed',
            trailing: '91%',
          ),
        ]),
      ],
    );
  }
}

class _RecoveryRating extends StatelessWidget {
  const _RecoveryRating();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Recovery rating',
      sample: true,
      link: 'Trends',
      children: [
        const MutedText('Daily check-in scores, last 7 days'),
        const SizedBox(height: 6),
        const MeterRow(
          label: 'Energy',
          value: 0.8,
          trailing: '8.0',
          trailingWidth: 36,
        ),
        const MeterRow(
          label: 'Sleep',
          value: 0.75,
          trailing: '7.5',
          trailingWidth: 36,
        ),
        MeterRow(
          label: 'Soreness',
          value: 0.3,
          trailing: '3.0',
          color: p.amber,
          trailingWidth: 36,
        ),
        MeterRow(
          label: 'Fatigue',
          value: 0.2,
          trailing: '2.0',
          color: p.amber,
          trailingWidth: 36,
        ),
      ],
    );
  }
}

class _InjuryRecords extends StatelessWidget {
  const _InjuryRecords();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Injury & pain records',
      sample: true,
      link: 'Manage',
      children: [
        RowList([
          RowItem(
            title: 'Shoulder pain',
            subtitle: 'Right · since Oct 31 · improving',
            trailing: 'Active',
            trailingColor: p.amber,
          ),
          const RowItem(
            title: 'Lower back',
            subtitle: 'Resolved Sep 14',
            trailing: 'Resolved',
          ),
        ]),
        const SizedBox(height: 10),
        const FieldLabel('Today’s pain (0–10)'),
        AppButton('What changed today?', onPressed: () {}),
        const SizedBox(height: 10),
        AppButton('Record pain', onPressed: () {}),
      ],
    );
  }
}

class _PainCheckIn extends StatefulWidget {
  const _PainCheckIn();

  @override
  State<_PainCheckIn> createState() => _PainCheckInState();
}

class _PainCheckInState extends State<_PainCheckIn> {
  int _region = 0;
  int _side = 1;
  double _level = 4;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Pain check-in',
      children: [
        const FieldLabel('Body region'),
        PillTabs(
          labels: const ['Shoulder', 'Back', 'Knee', 'Other'],
          index: _region,
          onChanged: (i) => setState(() => _region = i),
        ),
        const SizedBox(height: 8),
        PillTabs(
          labels: const ['Left', 'Right', 'Both'],
          index: _side,
          onChanged: (i) => setState(() => _side = i),
        ),
        const SizedBox(height: 12),
        const FieldLabel('Pain level (0–10)'),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: p.amber,
                  inactiveTrackColor: p.tile,
                  thumbColor: p.amber,
                ),
                child: Slider(
                  value: _level,
                  min: 0,
                  max: 10,
                  divisions: 10,
                  onChanged: (v) => setState(() => _level = v),
                ),
              ),
            ),
            Text(
              '${_level.round()}/10',
              style: TextStyle(color: p.text, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 8),
        AppButton.primary('Save pain entry', onPressed: () {}),
        const SizedBox(height: 12),
        const MutedText('Seek medical advice if pain is severe or persistent.'),
      ],
    );
  }
}

class _Restrictions extends StatelessWidget {
  const _Restrictions();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Restrictions & deload',
      children: [
        RowList([
          RowItem(
            title: 'Overhead pressing',
            subtitle: 'Avoid heavy overhead work',
            trailing: 'Restricted',
          ),
          RowItem(
            title: 'Deload',
            subtitle: 'None scheduled',
            trailing: 'Plan ›',
          ),
        ]),
      ],
    );
  }
}

class _Later extends StatelessWidget {
  const _Later();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const TitledCard(
          title: 'Equipment restrictions & limitations',
          children: [
            InnerTile(
              child: Text(
                'Record equipment and movement limitations. Changes apply to future sessions.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.gap),
        TitledCard(
          title: 'Deload planning',
          children: [
            const MutedText(
              'Plan a recovery week and reduce training volume. Your schedule and history stay intact.',
            ),
            const SizedBox(height: 12),
            AppButton('Schedule deload', onPressed: () {}),
          ],
        ),
      ],
    );
  }
}

// ---- Nutrition ----

class _NutritionToday extends StatelessWidget {
  const _NutritionToday();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Nutrition today',
      sample: true,
      link: 'Targets',
      children: [
        Text(
          '1,640 / 2,400 kcal',
          style: TextStyle(
            color: p.text,
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const MeterRow(
          label: 'Protein',
          value: 0.65,
          trailing: '98 g',
          trailingWidth: 44,
        ),
        const MeterRow(
          label: 'Carbs',
          value: 0.62,
          trailing: '174 g',
          trailingWidth: 44,
        ),
        const MeterRow(
          label: 'Fat',
          value: 0.56,
          trailing: '39 g',
          trailingWidth: 44,
        ),
      ],
    );
  }
}

class _LogMeal extends StatefulWidget {
  const _LogMeal();

  @override
  State<_LogMeal> createState() => _LogMealState();
}

class _LogMealState extends State<_LogMeal> {
  int _type = 0;

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Log a meal',
      children: [
        PillTabs(
          labels: const ['Breakfast', 'Lunch', 'Dinner', 'Snack'],
          index: _type,
          onChanged: (i) => setState(() => _type = i),
        ),
        const SizedBox(height: 12),
        const LabeledField('Name', hint: 'e.g. Oatmeal bowl'),
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(
              child: LabeledField(
                'Calories (kcal)',
                hint: '—',
                keyboard: TextInputType.number,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                'Protein (g)',
                hint: '—',
                keyboard: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(
              child: LabeledField(
                'Carbs (g)',
                hint: '—',
                keyboard: TextInputType.number,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                'Fat (g)',
                hint: '—',
                keyboard: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppButton.primary('Save meal', onPressed: () {}),
        const SizedBox(height: 12),
        const MutedText(
          'Nutrition is approximate unless you enter exact amounts.',
        ),
      ],
    );
  }
}

class _SavedMeals extends StatelessWidget {
  const _SavedMeals();

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Saved meals & plans',
      link: 'History',
      children: [
        const RowList([
          RowItem(
            title: 'Oatmeal bowl',
            subtitle: 'Breakfast',
            trailing: 'Use ›',
          ),
          RowItem(
            title: 'Eggs + toast',
            subtitle: 'Breakfast',
            trailing: 'Use ›',
          ),
          RowItem(
            title: 'Stir-fry bowl',
            subtitle: 'Dinner',
            trailing: 'Use ›',
          ),
        ]),
        const SizedBox(height: 10),
        AppButton('Plan this week', onPressed: () {}),
      ],
    );
  }
}

class _Targets extends StatelessWidget {
  const _Targets();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Targets',
      sample: true,
      children: [
        MutedText('Current daily targets'),
        SizedBox(height: 6),
        MeterRow(
          label: 'Calories',
          value: 0.8,
          trailing: '2,400',
          trailingWidth: 52,
        ),
        MeterRow(
          label: 'Protein',
          value: 0.7,
          trailing: '150 g',
          trailingWidth: 52,
        ),
        MeterRow(
          label: 'Carbs',
          value: 0.75,
          trailing: '280 g',
          trailingWidth: 52,
        ),
        MeterRow(label: 'Fat', value: 0.6, trailing: '70 g', trailingWidth: 52),
      ],
    );
  }
}

class _WeeklyPlan extends StatelessWidget {
  const _WeeklyPlan();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return TitledCard(
      title: 'Weekly meal plan',
      sample: true,
      link: 'Plan',
      children: [
        Row(
          children: [
            for (final d in days)
              Expanded(
                child: Column(
                  children: [
                    Text(d, style: TextStyle(color: p.muted, fontSize: 13)),
                    const SizedBox(height: 2),
                    Text('4', style: TextStyle(color: p.muted, fontSize: 13)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        const MutedText('Planned meals per day.'),
      ],
    );
  }
}

// ---- Supplements ----

class _SupplementSchedule extends StatelessWidget {
  const _SupplementSchedule();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(
      title: 'Supplement schedule',
      sample: true,
      children: [
        const RowList([
          RowItem(
            title: 'Creatine',
            subtitle: '5 g · with breakfast',
            trailing: 'Log ›',
          ),
          RowItem(
            title: 'Multivitamin',
            subtitle: '1 tablet · breakfast',
            trailing: 'Log ›',
          ),
          RowItem(
            title: 'Omega-3',
            subtitle: '2 g · dinner',
            trailing: 'Log ›',
          ),
        ]),
        const SizedBox(height: 10),
        RowItem(
          title: 'Omega-3 · 2 capsules · dinner',
          trailing: 'Missed',
          trailingColor: p.amber,
        ),
        const MutedText(
          'Always check labels. Ask a professional before changing supplementation.',
        ),
        const SizedBox(height: 12),
        AppButton('Add supplement', onPressed: () {}),
      ],
    );
  }
}

// ---- Activity ----

class _LogCardio extends StatefulWidget {
  const _LogCardio();

  @override
  State<_LogCardio> createState() => _LogCardioState();
}

class _LogCardioState extends State<_LogCardio> {
  int _kind = 3;

  @override
  Widget build(BuildContext context) {
    return TitledCard(
      title: 'Log cardio',
      children: [
        PillTabs(
          labels: const ['Walk', 'Run', 'Cycle', 'Treadmill', 'Other'],
          index: _kind,
          layout: PillLayout.scroll,
          onChanged: (i) => setState(() => _kind = i),
        ),
        const SizedBox(height: 12),
        const Row(
          children: [
            Expanded(
              child: LabeledField(
                'Minutes',
                initial: '25',
                keyboard: TextInputType.number,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: LabeledField(
                'Distance (km)',
                initial: '3.0',
                keyboard: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        AppButton.primary('Save session', onPressed: () {}),
      ],
    );
  }
}
