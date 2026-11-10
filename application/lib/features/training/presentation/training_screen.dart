import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/meters.dart';

/// Training section: Overview, Splits, Exercises, History and Schedule.
/// All lists are placeholders until the training data is synced locally.
class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  static const _tabs = ['Overview', 'Splits', 'Exercises', 'History', 'Schedule'];
  int _tab = 0;

  List<Widget> _content() {
    switch (_tab) {
      case 1:
        return const [_YourSplits(), _Alternating(), _Templates(), _ReorderChest()];
      case 2:
        return const [_ExerciseLibrary(), _ExerciseDetails(), _ReorderSimple()];
      case 3:
        return const [_History(), _HistoryFilters(), _CompareSessions()];
      case 4:
        return const [_ScheduleList(), _ScheduleWeek()];
      default:
        return const [
          _TodayCard(),
          _ThisWeek(),
          _QuickActions(),
          _RecentSessions(),
          _TrainingInsights(),
          _ActiveSplit(),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Training',
      subtitle: 'Splits, exercises and workouts',
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

class _TodayCard extends StatelessWidget {
  const _TodayCard();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Today · Day 1 of 4', style: TextStyle(color: p.muted, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        Text('Chest + Shoulders', style: TextStyle(color: p.text, fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        Row(children: [
          for (final m in ['Chest', 'Shoulders'])
            Padding(padding: const EdgeInsets.only(right: 18), child: Text(m, style: TextStyle(color: p.link, fontSize: 14))),
        ]),
        const SizedBox(height: 10),
        Text('7 exercises · about 60–75 min', style: TextStyle(color: p.muted, fontSize: 15)),
        const SizedBox(height: 14),
        AppButton.primary('Start workout', onPressed: () => context.push(AppRoutes.session)),
        const SizedBox(height: 12),
        const MutedText('Shows “Continue workout” if one is in progress.'),
      ]),
    );
  }
}

enum _DayStatus { done, now, planned }

class _ThisWeek extends StatelessWidget {
  const _ThisWeek();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget tile(String day, String name, _DayStatus status) {
      final Widget badge = switch (status) {
        _DayStatus.done => Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.greenFill),
            child: Icon(Icons.check, size: 16, color: p.green),
          ),
        _DayStatus.now => Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.primary),
            child: Icon(Icons.play_arrow_rounded, size: 16, color: p.onPrimary),
          ),
        _DayStatus.planned => Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.faint, width: 1.5)),
          ),
      };
      return Expanded(
        child: InnerTile(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(day, style: TextStyle(color: p.muted, fontSize: 12)),
            const SizedBox(height: 4),
            SizedBox(
              height: 34,
              child: Text(name, textAlign: TextAlign.center, style: TextStyle(color: p.text, fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 6),
            badge,
          ]),
        ),
      );
    }

    return TitledCard(
      title: 'This week',
      link: 'Schedule',
      onLink: () {},
      children: [
        Row(children: [
          tile('Day 1', 'Chest + Shoulders', _DayStatus.done),
          const SizedBox(width: 8),
          tile('Day 2', 'Back + Abs', _DayStatus.done),
          const SizedBox(width: 8),
          tile('Day 3', 'Arms + Forearms', _DayStatus.now),
          const SizedBox(width: 8),
          tile('Day 4', 'Legs', _DayStatus.planned),
        ]),
        const SizedBox(height: 14),
        const MeterBar(value: 0.75),
        const SizedBox(height: 10),
        const MutedText('3 / 4 workouts · 75% complete'),
      ],
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: 'Quick actions', children: [
      ButtonPair(AppButton('Log workout', onPressed: () {}), AppButton('Edit split', onPressed: () {})),
      const SizedBox(height: 12),
      ButtonPair(AppButton('Add exercise', onPressed: () {}), AppButton('Use template', onPressed: () {})),
    ]);
  }
}

class _RecentSessions extends StatelessWidget {
  const _RecentSessions();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Recent sessions', link: 'View all', children: [
      RowList([RowItem(title: 'Back + Abs', subtitle: 'Sun, Nov 2 · 6 exercises · 58 min', chevron: true)]),
    ]);
  }
}

class _TrainingInsights extends StatelessWidget {
  const _TrainingInsights();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Training insights', sample: true, children: [
      Row(children: [
        Expanded(flex: 3, child: StatBlock('12,430 kg', 'This month volume')),
        Expanded(flex: 2, child: StatBlock('3', 'Workouts done')),
        Expanded(flex: 3, child: StatBlock('3 h 45 m', 'Total duration')),
      ]),
      SizedBox(height: 14),
      MutedText('vs. last month: volume +6.2% · workouts +1 · time +24 min'),
    ]);
  }
}

class _ActiveSplit extends StatelessWidget {
  const _ActiveSplit();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Active split · 4-day, since Sep 8', children: [
      RowList([
        RowItem(title: 'Splits', subtitle: 'Past versions and comparisons', chevron: true),
        RowItem(title: 'Templates', subtitle: 'Duplicate and edit', chevron: true),
        RowItem(title: 'Exercise library', subtitle: 'Details, alternatives, and 1RM', chevron: true),
      ]),
    ]);
  }
}

// ---- Splits ----

class _YourSplits extends StatelessWidget {
  const _YourSplits();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(title: 'Your splits', link: 'Compare', children: [
      RowList([
        const RowItem(title: '4-day split', subtitle: 'Active · Day 2 of 4 next', trailing: 'Active'),
        RowItem(title: '3-day split', subtitle: 'Used Aug 1 – Sep 7', trailing: 'Archived', trailingColor: p.amber),
      ]),
      const SizedBox(height: 12),
      ButtonPair(AppButton('Create', onPressed: () {}), AppButton('Duplicate', onPressed: () {})),
      const SizedBox(height: 12),
      ButtonPair(AppButton('Activate', onPressed: () {}), AppButton('Archive', onPressed: () {})),
    ]);
  }
}

class _Alternating extends StatelessWidget {
  const _Alternating();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget variant(String name, String note) => InnerTile(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(color: p.text, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(note, style: TextStyle(color: p.muted, fontSize: 13.5)),
          ]),
        );
    return TitledCard(title: 'Alternating variations', children: [
      Text('Day 4 · Legs', style: TextStyle(color: p.text, fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      const MutedText('Alternates each week.'),
      const SizedBox(height: 12),
      IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(child: variant('Leg Day A', 'Quad focus · next')),
          const SizedBox(width: 12),
          Expanded(child: variant('Leg Day B', 'Hamstring / glute focus')),
        ]),
      ),
      const SizedBox(height: 12),
      AppButton('Edit variations', onPressed: () {}),
    ]);
  }
}

class _Templates extends StatelessWidget {
  const _Templates();

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: 'Templates', sample: true, children: [
      const RowList([
        RowItem(title: 'Chest + Shoulders', subtitle: '7 exercises · v3', chevron: true),
        RowItem(title: 'Back + Abs', subtitle: '6 exercises · v2', chevron: true),
        RowItem(title: 'Arms + Forearms', subtitle: '6 exercises · v4', chevron: true),
      ]),
      const SizedBox(height: 12),
      ButtonPair(AppButton('New template', onPressed: () {}), AppButton('Duplicate', onPressed: () {})),
    ]);
  }
}

class _ReorderChest extends StatelessWidget {
  const _ReorderChest();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget row(String n, String name, String scheme) => RowItem(
          title: '$n · $name',
          subtitle: scheme,
          leading: Text('≡', style: TextStyle(color: p.muted, fontSize: 18)),
          trailing: '…',
        );
    return TitledCard(title: 'Reorder exercises · Chest + Shoulders', children: [
      RowList([
        row('1', 'Barbell Bench Press', '4 × 6–8'),
        row('2', 'Incline Dumbbell Press', '3 × 8–10'),
        row('3', 'Cable Fly', '3 × 12–15'),
      ]),
      const SizedBox(height: 10),
      const MutedText('Drag ≡ to reorder. Changes create a new template version; past sessions keep their old order.'),
    ]);
  }
}

// ---- Exercises ----

class _ExerciseLibrary extends StatefulWidget {
  const _ExerciseLibrary();

  @override
  State<_ExerciseLibrary> createState() => _ExerciseLibraryState();
}

class _ExerciseLibraryState extends State<_ExerciseLibrary> {
  int _muscle = 0;
  int _equipment = 0;

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: 'Exercise library', children: [
      const FieldLabel('Search'),
      const FieldBox(hint: 'Search exercises'),
      const SizedBox(height: 14),
      const FieldLabel('Muscle group'),
      PillTabs(
        labels: const ['All', 'Chest', 'Back', 'Shoulders', 'Arms'],
        index: _muscle,
        layout: PillLayout.scroll,
        onChanged: (i) => setState(() => _muscle = i),
      ),
      const SizedBox(height: 12),
      const FieldLabel('Equipment'),
      PillTabs(
        labels: const ['Any', 'Barbell', 'Dumbbell', 'Cable'],
        index: _equipment,
        layout: PillLayout.scroll,
        onChanged: (i) => setState(() => _equipment = i),
      ),
      const SizedBox(height: 8),
      const RowList([
        RowItem(
          title: 'Incline Dumbbell Press',
          subtitle: 'Target: upper chest · Secondary: front delts, triceps',
          chevron: true,
        ),
      ]),
    ]);
  }
}

class _ExerciseDetails extends StatelessWidget {
  const _ExerciseDetails();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget links(List<String> names) => Wrap(
          spacing: 14,
          children: [for (final n in names) Text(n, style: TextStyle(color: p.link, fontSize: 15))],
        );
    return TitledCard(title: 'Exercise details · Incline Dumbbell Press', children: [
      const FieldLabel('Target'),
      links(const ['Upper chest']),
      const SizedBox(height: 12),
      const FieldLabel('Secondary'),
      links(const ['Front delts', 'Triceps']),
      const SizedBox(height: 12),
      const MutedText('Set the bench to 30°. Moderate bottom stretch, neutral wrists, controlled eccentric.', size: 15),
      const SizedBox(height: 14),
      ButtonPair(AppButton('Replace', onPressed: () {}), AppButton('Alternatives', onPressed: () {})),
    ]);
  }
}

class _ReorderSimple extends StatelessWidget {
  const _ReorderSimple();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget row(String name) => RowItem(
          title: name,
          leading: Text('≡', style: TextStyle(color: p.muted, fontSize: 18)),
        );
    return TitledCard(title: 'Reorder exercises', children: [
      const MutedText('Drag to change the order.'),
      const SizedBox(height: 6),
      RowList([row('Flat Bench Press'), row('Incline Dumbbell Press'), row('Cable Fly'), row('Lateral Raise')]),
    ]);
  }
}

// ---- History ----

class _History extends StatelessWidget {
  const _History();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget filter(String label) => Expanded(
          child: Center(child: Text('$label ▾', style: TextStyle(color: p.muted, fontSize: 13.5))),
        );
    return TitledCard(title: 'History', children: [
      Row(children: [filter('Date'), filter('Split'), filter('Exercise')]),
      const SizedBox(height: 8),
      const RowList([RowItem(title: 'Back + Abs', subtitle: 'Sun, Nov 2 · 58 min', chevron: true)]),
      const SizedBox(height: 12),
      AppButton('Compare sessions', onPressed: () {}),
    ]);
  }
}

class _HistoryFilters extends StatefulWidget {
  const _HistoryFilters();

  @override
  State<_HistoryFilters> createState() => _HistoryFiltersState();
}

class _HistoryFiltersState extends State<_HistoryFilters> {
  int _by = 0;

  @override
  Widget build(BuildContext context) {
    return TitledCard(title: 'History filters', children: [
      PillTabs(labels: const ['By date', 'Split', 'Exercise'], index: _by, onChanged: (i) => setState(() => _by = i)),
      const SizedBox(height: 8),
      const RowList([RowItem(title: 'Compare sessions', subtitle: 'Pick two sessions of the same exercise.', chevron: true)]),
    ]);
  }
}

class _CompareSessions extends StatelessWidget {
  const _CompareSessions();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(title: 'Compare · Chest + Shoulders', sample: true, children: [
      Row(children: [
        Expanded(child: StatBlock('5,120 kg', 'Nov 2 · 64 min')),
        Expanded(child: StatBlock('4,890 kg', 'Oct 28 · 62 min')),
      ]),
      SizedBox(height: 8),
      RowList([RowItem(title: 'Bench Press top set', trailing: '85 vs 82.5 kg')]),
    ]);
  }
}

// ---- Schedule ----

class _ScheduleList extends StatelessWidget {
  const _ScheduleList();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return TitledCard(title: 'Schedule', sample: true, link: 'Custom', children: [
      RowList([
        const RowItem(title: 'Mon · Chest + Shoulders', trailing: 'Completed'),
        const RowItem(title: 'Tue · Back + Abs', trailing: 'Completed'),
        const RowItem(title: 'Wed · Arms + Forearms', trailing: 'Planned'),
        const RowItem(title: 'Thu · Rest day', trailing: 'Rest'),
        RowItem(title: 'Fri · Legs', trailing: 'Skipped', trailingColor: p.amber),
      ]),
    ]);
  }
}

class _ScheduleWeek extends StatelessWidget {
  const _ScheduleWeek();

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    const days = [
      ('Mon', 'Done'),
      ('Tue', 'Done'),
      ('Wed', 'Next'),
      ('Thu', 'Rest'),
      ('Fri', 'Planned'),
      ('Sat', 'Skip'),
      ('Sun', 'Rest'),
    ];
    return TitledCard(title: 'Schedule · this week', link: 'Calendar', children: [
      Row(children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: i == 2 ? p.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                Text(days[i].$1, style: TextStyle(color: i == 2 ? p.onPrimary : p.muted, fontSize: 12.5, fontWeight: i == 2 ? FontWeight.w700 : FontWeight.w500)),
                const SizedBox(height: 2),
                Text(days[i].$2, style: TextStyle(color: i == 2 ? p.onPrimary : p.muted, fontSize: 11.5, fontWeight: i == 2 ? FontWeight.w700 : FontWeight.w400)),
              ]),
            ),
          ),
      ]),
      const SizedBox(height: 14),
      const MutedText('Planned rest days and approved breaks do not count as missed.', size: 15),
    ]);
  }
}
