import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/insights/insight_providers.dart';
import '../../../core/insights/insight_repository.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/insight_status.dart';
import '../../../core/widgets/meters.dart';
import '../../../core/widgets/section_widgets.dart';
import '../../progress/data/progress_insights.dart';
import '../../progress/data/progress_providers.dart';
import '../../training/presentation/training_dialogs.dart' show ModalCard;
import '../data/lifestyle_models.dart';
import '../data/lifestyle_providers.dart';
import '../data/lifestyle_service.dart';
import 'step_import_card.dart';
import 'steps_widgets.dart';

/// Lifestyle section: Overview, Recovery, Nutrition, Supplements and Activity. Everything is read from the phone and
/// saved through [LifestyleService] (local first, synced later). Wording stays observational, never medical advice.
/// Recovery readiness and other backend-calculated values are not worked out here: they come from the daily briefing.
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

  void _go(int i) => setState(() => _tab = i);

  List<Widget> _content() {
    switch (_tab) {
      case 1:
        return const [
          _SleepCard(),
          _CheckinCard(),
          _PainCard(),
          _InjuryRestrictionRows(),
          InfoLine('A log of how you feel. This is not medical advice.'),
        ];
      case 2:
        return const [
          _NutritionToday(),
          _TodaysMeals(),
          _LogMeal(),
          _SavedMeals(),
          _Targets(),
        ];
      case 3:
        return const [_SupplementsToday(), _AddSupplement()];
      case 4:
        return const [
          StepsSummaryCard(),
          _StepsActions(),
          _LogCardio(),
          _Hydration(),
        ];
      default:
        return [
          _StatTiles(onGo: _go),
          _RecoveryReadiness(onGo: _go),
          const _Hydration(),
          _QuickLog(onGo: _go),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      title: 'Lifestyle',
      subtitle: 'Recovery, nutrition and daily activity',
      trailing: SizedBox(
        width: 96,
        height: 48,
        child: FilledButton(
          key: const Key('lifestyle-log'),
          onPressed:
              () => showDialog<void>(
                context: context,
                builder: (_) => _LogMenu(onGo: _go),
              ),
          child: const Text('+ Log'),
        ),
      ),
      children: [
        UnderlineTabs(labels: _tabs, index: _tab, onChanged: _go),
        ..._content(),
      ],
    );
  }
}

/// What do you want to log? Each choice opens the place where that is logged.
class _LogMenu extends StatelessWidget {
  const _LogMenu({required this.onGo});

  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    Widget item(String label, VoidCallback go) => SizedBox(
      width: 150,
      child: AppButton(
        label,
        key: Key('log-$label'),
        height: 52,
        onPressed: () {
          Navigator.of(context).pop();
          go();
        },
      ),
    );
    return ModalCard(
      title: 'Log something',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          item('Sleep', () => onGo(1)),
          item('Pain', () => onGo(1)),
          item('Meal', () => onGo(2)),
          item('Supplement', () => onGo(3)),
          item('Cardio', () => onGo(4)),
          item('Steps', () => onGo(4)),
          item(
            'Water',
            () => showDialog<void>(
              context: context,
              builder: (_) => const _OtherWaterDialog(),
            ),
          ),
        ],
      ),
    );
  }
}

// ---- helpers ----

const _savedText = 'Saved on this phone. It will sync when online.';

String _today() => localStampOf(DateTime.now()).localDate;

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '.'));

String _kg(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String _cap(String s) =>
    s.isEmpty
        ? s
        : '${s[0].toUpperCase()}${s.substring(1).replaceAll('_', ' ')}';

/// Runs a save, shows the result as a message and tells the caller whether it worked.
Future<bool> _save(
  BuildContext context,
  Future<Object?> Function() action, {
  String ok = _savedText,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(ok)));
    return true;
  } on ArgumentError catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('$e')));
  }
  return false;
}

Widget _gap([double h = 12]) => SizedBox(height: h);

/// A text box that clears itself when [resetKey] changes (after a save). Left-aligned, with an optional unit.
Widget _field(
  String hint,
  ValueChanged<String> onChanged, {
  Object? resetKey,
  TextInputType? keyboard,
  String initial = '',
  Key? fieldKey,
  String? suffix,
}) => FieldBox(
  key: ValueKey('$hint-$resetKey'),
  fieldKey: fieldKey,
  hint: hint,
  initial: initial,
  keyboard: keyboard,
  textAlign: TextAlign.start,
  suffix: suffix,
  onChanged: onChanged,
);

const _decimal = TextInputType.numberWithOptions(decimal: true);

/// A card with a title, an optional line under it, and its content.
class _Card extends StatelessWidget {
  const _Card({required this.title, this.sub, required this.children});

  final String title;
  final String? sub;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: p.text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 6),
              Text(sub!, style: TextStyle(color: p.muted, fontSize: 16)),
            ],
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// Square number buttons (1-5, 0-10), the selected one filled.
class _Squares extends StatelessWidget {
  const _Squares({
    required this.labels,
    required this.index,
    required this.onChanged,
    this.perRow,
    this.height = 54,
    this.gap = 10,
    this.keyPrefix,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onChanged;
  final int? perRow;
  final double height;
  final double gap;
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return LayoutBuilder(
      builder: (_, c) {
        final n = perRow ?? labels.length;
        final w = (c.maxWidth - (n - 1) * gap) / n;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (var i = 0; i < labels.length; i++)
              SizedBox(
                width: w,
                height: height,
                child: InkWell(
                  key: keyPrefix == null ? null : Key('$keyPrefix-$i'),
                  onTap: () => onChanged(i),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == index ? p.primary : p.tile,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: i == index ? p.primary : p.divider,
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        color: i == index ? p.onPrimary : p.text,
                        fontSize: 17,
                        fontWeight:
                            i == index ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A server answer's freshness line, shown only when the answer is old, offline or missing.
class _Problem extends ConsumerWidget {
  const _Problem(this.spec, this.snapshot);

  final InsightSpec spec;
  final InsightSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final healthy =
        snapshot.hasData &&
        snapshot.error == null &&
        snapshot.freshness != InsightFreshness.stale;
    if (healthy) return const SizedBox.shrink();
    return InsightStatusLine(
      snapshot: snapshot,
      onRefresh: () => ref.read(insightProvider(spec).notifier).refresh(),
    );
  }
}

String _timeText(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}';
}

// ---- Overview ----

class _StatTiles extends ConsumerWidget {
  const _StatTiles({required this.onGo});

  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final day = ref.watch(daySummaryProvider(_today())).valueOrNull;
    final targets = ref.watch(targetsProvider).valueOrNull;
    final stepTarget = day?.steps?.targetSteps ?? targets?.stepTarget;
    final steps = day?.steps?.steps;
    final water = day?.waterMl ?? 0;

    Widget tile(
      Key key,
      String label,
      String value,
      double? fill,
      String link,
      String note,
      int tab,
    ) => Expanded(
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          key: key,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: p.muted, fontSize: 15)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  color: p.text,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 10),
            MeterBar(
              value: (fill ?? 0).clamp(0, 1).toDouble(),
              trackColor: p.tile,
            ),
            const SizedBox(height: 10),
            LinkText(link, onTap: () => onGo(tab)),
            const SizedBox(height: 2),
            Text(note, style: TextStyle(color: p.muted, fontSize: 15)),
          ],
        ),
      ),
    );

    return Column(
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                const Key('tile-sleep'),
                'Sleep',
                day == null || day.sleepSeconds == 0
                    ? '–'
                    : '${(day.sleepSeconds / 3600).toStringAsFixed(1)} h',
                null,
                'Log sleep',
                'Last night',
                1,
              ),
              const SizedBox(width: 12),
              tile(
                const Key('tile-meals'),
                'Meals',
                day == null
                    ? '0 / 0'
                    : '${day.mealsEaten} / ${day.mealsPlanned}',
                day == null || day.mealsPlanned == 0
                    ? null
                    : day.mealsEaten / day.mealsPlanned,
                targets?.caloriesKcal == null ? 'Set target' : 'Edit target',
                'Eaten',
                2,
              ),
            ],
          ),
        ),
        _gap(),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile(
                const Key('tile-water'),
                'Water',
                '${(water / 1000).toStringAsFixed(1)} L',
                targets?.waterMl == null ? null : water / targets!.waterMl!,
                targets?.waterMl == null ? 'Set target' : 'Edit target',
                targets?.waterMl == null
                    ? 'Today'
                    : 'of ${(targets!.waterMl! / 1000).toStringAsFixed(1)} L',
                2,
              ),
              const SizedBox(width: 12),
              tile(
                const Key('tile-steps'),
                'Steps',
                steps == null ? '–' : '$steps',
                stepTarget == null || steps == null ? null : steps / stepTarget,
                stepTarget == null ? 'Set target' : 'Edit target',
                stepTarget == null ? 'Today' : 'of $stepTarget',
                2,
              ),
            ],
          ),
        ),
        _gap(),
      ],
    );
  }
}

/// Readiness as the server calculated it in the daily briefing, with how old that answer is. Nothing is worked out here.
class _RecoveryReadiness extends ConsumerWidget {
  const _RecoveryReadiness({required this.onGo});

  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = localStampOf(DateTime.now()).localDate;
    final result = ref.watch(dailyBriefingProvider(today));
    final readiness = result.briefing?.readiness;
    final deload = result.briefing?.deload;
    final checkin = ref.watch(checkinProvider(today)).valueOrNull;
    return _Card(
      title: 'Recovery and readiness',
      children: [
        if (readiness == null)
          Text(
            checkin == null
                ? 'No check-in today. A quick one gives a better summary.'
                : 'Checked in today. Readiness appears when the daily briefing updates.',
            style: TextStyle(color: p.muted, fontSize: 17, height: 1.3),
          )
        else ...[
          Text(
            _cap(readiness.level),
            key: const Key('lifestyle-readiness'),
            style: TextStyle(
              color: p.text,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          for (final line in readiness.reasoning) ...[
            const SizedBox(height: 6),
            Text(
              line,
              style: TextStyle(color: p.muted, fontSize: 15, height: 1.35),
            ),
          ],
        ],
        if (deload != null &&
            deload.level != 'none' &&
            deload.level != 'unknown') ...[
          const SizedBox(height: 10),
          Text(
            'Deload: ${deload.level.replaceAll('_', ' ')}',
            style: TextStyle(
              color: p.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        _gap(16),
        AppButton.primary(
          checkin == null ? 'Start check-in' : 'Update check-in',
          key: const Key('start-checkin'),
          height: 58,
          onPressed: () => onGo(1),
        ),
        _Problem(dailyBriefingSpec(today), result.snapshot),
      ],
    );
  }
}

class _QuickLog extends StatelessWidget {
  const _QuickLog({required this.onGo});

  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget chip(String label, int tab) => InkWell(
      key: Key('quick-$label'),
      onTap: () => onGo(tab),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: p.divider),
        ),
        child: Text(label, style: TextStyle(color: p.text, fontSize: 16)),
      ),
    );
    return _Card(
      title: 'Quick log',
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            chip('Sleep', 1),
            chip('Meal', 2),
            chip('Pain', 1),
            chip('Cardio', 4),
            chip('Steps', 4),
          ],
        ),
      ],
    );
  }
}

/// Water: +250, +500 or another amount, with the last few entries so a mistake can be removed.
class _Hydration extends ConsumerWidget {
  const _Hydration();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = _today();
    final logs =
        ref.watch(waterForProvider(today)).valueOrNull ?? const <WaterLog>[];
    final targets = ref.watch(targetsProvider).valueOrNull;
    final total = logs.fold<int>(0, (a, w) => a + w.amountMl);
    Future<void> add(int ml) =>
        _save(context, () => ref.read(lifestyleServiceProvider).addWater(ml));
    return _Card(
      title:
          targets?.waterMl == null
              ? 'Hydration · $total ml'
              : 'Hydration · $total / ${targets!.waterMl} ml',
      children: [
        Row(
          children: [
            Expanded(
              child: AppButton(
                '+250 ml',
                height: 58,
                onPressed: () => add(250),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                '+500 ml',
                height: 58,
                onPressed: () => add(500),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AppButton(
                'Other',
                key: const Key('water-other'),
                height: 58,
                onPressed:
                    () => showDialog<void>(
                      context: context,
                      builder: (_) => const _OtherWaterDialog(),
                    ),
              ),
            ),
          ],
        ),
        if (logs.isNotEmpty) ...[
          _gap(),
          RowList([
            for (final w in logs.reversed.take(3))
              RowItem(
                title: '${w.amountMl} ml',
                subtitle:
                    w.occurredAt == null ? null : _timeText(w.occurredAt!),
                trailing: 'Remove',
                onTap:
                    () => ref.read(lifestyleServiceProvider).deleteWater(w.id),
              ),
          ]),
        ],
      ],
    );
  }
}

class _OtherWaterDialog extends ConsumerStatefulWidget {
  const _OtherWaterDialog();

  @override
  ConsumerState<_OtherWaterDialog> createState() => _OtherWaterDialogState();
}

class _OtherWaterDialogState extends ConsumerState<_OtherWaterDialog> {
  String _ml = '';

  @override
  Widget build(BuildContext context) {
    return ModalCard(
      title: 'Add water',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FieldLabel('Amount'),
          _field(
            '250',
            (v) => _ml = v,
            keyboard: TextInputType.number,
            suffix: 'ml',
            fieldKey: const Key('water-amount'),
          ),
          _gap(16),
          AppButton.primary(
            'Add',
            key: const Key('water-add'),
            height: 56,
            onPressed: () async {
              final ml = int.tryParse(_ml.trim());
              if (ml == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Enter the amount in ml.')),
                );
                return;
              }
              if (await _save(
                    context,
                    () => ref.read(lifestyleServiceProvider).addWater(ml),
                  ) &&
                  context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
        ],
      ),
    );
  }
}

// ---- Recovery ----

class _SleepCard extends ConsumerStatefulWidget {
  const _SleepCard();

  @override
  ConsumerState<_SleepCard> createState() => _SleepCardState();
}

class _SleepCardState extends ConsumerState<_SleepCard> {
  String _hours = '';
  int _quality = -1;
  bool _nap = false;
  int _reset = 0;

  @override
  Widget build(BuildContext context) {
    final recent =
        ref.watch(recentSleepProvider).valueOrNull ?? const <SleepLog>[];
    return _Card(
      title: 'Sleep',
      children: [
        const FieldLabel('Hours slept'),
        _field(
          '7.5',
          (v) => _hours = v,
          keyboard: _decimal,
          suffix: 'h',
          resetKey: _reset,
          fieldKey: const Key('sleep-hours'),
        ),
        _gap(16),
        const FieldLabel('Quality · 1 poor, 5 great'),
        _Squares(
          labels: const ['1', '2', '3', '4', '5'],
          index: _quality,
          keyPrefix: 'sleep-quality',
          onChanged: (i) => setState(() => _quality = i),
        ),
        _gap(14),
        PillTabs(
          labels: const ['Night', 'Nap'],
          index: _nap ? 1 : 0,
          container: true,
          onChanged: (i) => setState(() => _nap = i == 1),
        ),
        _gap(14),
        AppButton(
          'Save sleep',
          height: 56,
          onPressed: () async {
            final h = _num(_hours);
            if (h == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enter the hours slept.')),
              );
              return;
            }
            final ok = await _save(
              context,
              () => ref
                  .read(lifestyleServiceProvider)
                  .logSleep(
                    durationSeconds: (h * 3600).round(),
                    quality: _quality < 0 ? null : _quality + 1,
                    isNap: _nap,
                  ),
            );
            if (ok && mounted) {
              setState(() {
                _hours = '';
                _quality = -1;
                _reset++;
              });
            }
          },
        ),
        if (recent.isNotEmpty) ...[
          _gap(),
          RowList([
            for (final s in recent.take(3))
              RowItem(
                title:
                    '${s.hours.toStringAsFixed(1)} h${s.isNap ? ' · nap' : ''}',
                subtitle:
                    '${s.localDate}${s.quality == null ? '' : ' · quality ${s.quality}'}',
                trailing: 'Remove',
                onTap:
                    () => ref.read(lifestyleServiceProvider).deleteSleep(s.id),
              ),
          ]),
        ],
      ],
    );
  }
}

class _CheckinCard extends ConsumerStatefulWidget {
  const _CheckinCard();

  @override
  ConsumerState<_CheckinCard> createState() => _CheckinCardState();
}

class _CheckinCardState extends ConsumerState<_CheckinCard> {
  static const _names = [
    'Energy',
    'Sleep quality',
    'Soreness',
    'Fatigue',
    'Motivation',
    'Stress',
  ];
  final List<int?> _values = List.filled(6, null);
  // Kept from today's saved check-in so saving again does not drop them; pain is logged in its own card.
  bool _pain = false;
  String _notes = '';
  String? _loadedFor;

  void _load(DailyCheckin? c) {
    final key = c?.id ?? 'none';
    if (_loadedFor == key) return;
    _loadedFor = key;
    if (c == null) return;
    _values
      ..[0] = c.energy
      ..[1] = c.sleepQuality
      ..[2] = c.soreness
      ..[3] = c.fatigue
      ..[4] = c.motivation
      ..[5] = c.stress;
    _pain = c.painFlag;
    _notes = c.notes ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final today = _today();
    final existing = ref.watch(checkinProvider(today)).valueOrNull;
    _load(existing);
    return _Card(
      title: 'Daily check-in',
      sub: '1 is low, 5 is high.',
      children: [
        for (var i = 0; i < _names.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 128,
                  child: Text(
                    _names[i],
                    style: TextStyle(color: p.text, fontSize: 17),
                  ),
                ),
                Expanded(
                  child: _Squares(
                    labels: const ['1', '2', '3', '4', '5'],
                    index: (_values[i] ?? 0) - 1,
                    height: 46,
                    gap: 8,
                    keyPrefix: 'checkin-$i',
                    onChanged: (n) => setState(() => _values[i] = n + 1),
                  ),
                ),
              ],
            ),
          ),
        _gap(6),
        AppButton.primary(
          'Save check-in',
          height: 58,
          onPressed:
              () => _save(
                context,
                () => ref
                    .read(lifestyleServiceProvider)
                    .saveCheckin(
                      energy: _values[0],
                      sleepQuality: _values[1],
                      soreness: _values[2],
                      fatigue: _values[3],
                      motivation: _values[4],
                      stress: _values[5],
                      painFlag: _pain,
                      notes: _notes,
                    ),
              ),
        ),
      ],
    );
  }
}

class _PainCard extends ConsumerStatefulWidget {
  const _PainCard();

  @override
  ConsumerState<_PainCard> createState() => _PainCardState();
}

class _PainCardState extends ConsumerState<_PainCard> {
  int _region = -1;
  int _level = -1;
  int _effect = 0;
  static const _effects = [
    'none',
    'minor',
    'limited_movement',
    'stopped_training',
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final regions =
        ref.watch(bodyRegionsProvider).valueOrNull ?? const <BodyRegion>[];
    final recent =
        ref.watch(recentPainProvider).valueOrNull ?? const <PainEntry>[];
    final names = {for (final r in regions) r.id: r.name};
    return _Card(
      title: 'Pain check-in',
      sub: 'Pain level · 0 none, 10 worst',
      children: [
        _Squares(
          labels: [for (var i = 0; i <= 10; i++) '$i'],
          index: _level,
          perRow: 6,
          keyPrefix: 'pain-level',
          onChanged: (i) => setState(() => _level = i),
        ),
        _gap(16),
        const FieldLabel('Where'),
        if (regions.isEmpty)
          const MutedText('Body regions appear after the first sync.')
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < regions.length; i++)
                InkWell(
                  key: Key('pain-region-$i'),
                  onTap: () => setState(() => _region = i),
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: i == _region ? p.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: i == _region ? p.primary : p.divider,
                      ),
                    ),
                    child: Text(
                      regions[i].name,
                      style: TextStyle(
                        color: i == _region ? p.onPrimary : p.text,
                        fontSize: 15,
                        fontWeight:
                            i == _region ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        _gap(16),
        const FieldLabel('Effect on training'),
        PillTabs(
          labels: const ['None', 'Minor', 'Limited', 'Stopped'],
          index: _effect,
          container: true,
          onChanged: (i) => setState(() => _effect = i),
        ),
        _gap(14),
        AppButton(
          'Save pain entry',
          height: 56,
          onPressed: () async {
            if (_region < 0 || _region >= regions.length || _level < 0) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pick the region and the level.')),
              );
              return;
            }
            final ok = await _save(
              context,
              () => ref
                  .read(lifestyleServiceProvider)
                  .logPain(
                    bodyRegionId: regions[_region].id,
                    level: _level,
                    effectOnTraining: _effects[_effect],
                  ),
            );
            if (ok && mounted) {
              setState(() {
                _region = -1;
                _level = -1;
                _effect = 0;
              });
            }
          },
        ),
        if (recent.isNotEmpty) ...[
          _gap(),
          RowList([
            for (final e in recent.take(3))
              RowItem(
                title: '${names[e.bodyRegionId] ?? 'Body'} · ${e.level}/10',
                subtitle:
                    '${e.localDate} · effect: ${_cap(e.effectOnTraining)}',
              ),
          ]),
        ],
      ],
    );
  }
}

/// Two rows, Injuries and Restrictions, each opening a dialog where they are listed and added.
class _InjuryRestrictionRows extends ConsumerWidget {
  const _InjuryRestrictionRows();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final injuries =
        ref.watch(injuriesProvider).valueOrNull ?? const <Injury>[];
    final active = injuries.where((i) => i.status != 'resolved').length;
    final list =
        ref.watch(restrictionsProvider).valueOrNull ??
        const <ExerciseRestriction>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: RowList([
          RowItem(
            key: const Key('injuries-row'),
            title: 'Injuries',
            subtitle: active == 0 ? 'No active injuries' : '$active active',
            trailing: 'Add ›',
            onTap:
                () => showDialog<void>(
                  context: context,
                  builder:
                      (_) => const ModalCard(
                        title: 'Injuries',
                        child: _InjuriesBody(),
                      ),
                ),
          ),
          RowItem(
            key: const Key('restrictions-row'),
            title: 'Restrictions',
            subtitle:
                list.isEmpty
                    ? 'Movements you avoid or modify'
                    : '${list.length} recorded',
            trailing: 'Add ›',
            onTap:
                () => showDialog<void>(
                  context: context,
                  builder:
                      (_) => const ModalCard(
                        title: 'Restrictions',
                        child: _RestrictionsBody(),
                      ),
                ),
          ),
        ]),
      ),
    );
  }
}

class _InjuriesBody extends ConsumerStatefulWidget {
  const _InjuriesBody();

  @override
  ConsumerState<_InjuriesBody> createState() => _InjuriesBodyState();
}

class _InjuriesBodyState extends ConsumerState<_InjuriesBody> {
  String _name = '';
  int _region = -1;
  int _severity = -1;
  int _reset = 0;
  static const _severities = ['mild', 'moderate', 'severe'];

  Future<void> _manage(Injury i) async {
    final choice = await showDialog<String>(
      context: context,
      builder:
          (ctx) => SimpleDialog(
            title: Text(i.name),
            children: [
              for (final c in const [
                ('Mark recovering', 'recovering'),
                ('Mark resolved', 'resolved'),
                ('Back to active', 'active'),
              ])
                SimpleDialogOption(
                  onPressed: () => Navigator.of(ctx).pop(c.$2),
                  child: Text(c.$1),
                ),
            ],
          ),
    );
    if (choice == null || !mounted) return;
    await _save(
      context,
      () =>
          ref.read(lifestyleServiceProvider).updateInjury(i.id, status: choice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final injuries =
        ref.watch(injuriesProvider).valueOrNull ?? const <Injury>[];
    final regions =
        ref.watch(bodyRegionsProvider).valueOrNull ?? const <BodyRegion>[];
    final names = {for (final r in regions) r.id: r.name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (injuries.isEmpty)
          const MutedText('No active injuries recorded.')
        else
          RowList([
            for (final i in injuries)
              RowItem(
                title: i.name,
                subtitle:
                    '${names[i.bodyRegionId] ?? 'Body'} · since ${i.startDate}${i.severity == null ? '' : ' · ${i.severity}'}',
                trailing: _cap(i.status),
                onTap: () => _manage(i),
              ),
          ]),
        _gap(),
        const FieldLabel('Add an injury'),
        _field(
          'What is it? (e.g. Sore left knee)',
          (v) => _name = v,
          resetKey: _reset,
        ),
        _gap(10),
        if (regions.isEmpty)
          const MutedText('Body regions appear after the first sync.')
        else
          PillTabs(
            labels: [for (final r in regions) r.name],
            index: _region,
            layout: PillLayout.scroll,
            onChanged: (i) => setState(() => _region = i),
          ),
        _gap(10),
        PillTabs(
          labels: const ['Mild', 'Moderate', 'Severe'],
          index: _severity,
          onChanged: (i) => setState(() => _severity = i),
        ),
        _gap(),
        AppButton(
          'Save injury',
          onPressed: () async {
            if (_region < 0 || _region >= regions.length) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pick the body region.')),
              );
              return;
            }
            final ok = await _save(
              context,
              () => ref
                  .read(lifestyleServiceProvider)
                  .addInjury(
                    name: _name,
                    bodyRegionId: regions[_region].id,
                    severity: _severity < 0 ? null : _severities[_severity],
                  ),
            );
            if (ok && mounted) {
              setState(() {
                _name = '';
                _region = -1;
                _severity = -1;
                _reset++;
              });
            }
          },
        ),
      ],
    );
  }
}

class _RestrictionsBody extends ConsumerStatefulWidget {
  const _RestrictionsBody();

  @override
  ConsumerState<_RestrictionsBody> createState() => _RestrictionsBodyState();
}

class _RestrictionsBodyState extends ConsumerState<_RestrictionsBody> {
  String _movement = '';
  int _kind = 0;
  int _reset = 0;
  static const _kinds = ['uncomfortable', 'avoid', 'modify'];
  @override
  Widget build(BuildContext context) {
    final list =
        ref.watch(restrictionsProvider).valueOrNull ??
        const <ExerciseRestriction>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MutedText(
          'Movements you avoid or modify. They are recorded here; matching them to exercises comes later.',
        ),
        if (list.isNotEmpty) ...[
          _gap(10),
          RowList([
            for (final r in list)
              RowItem(
                title: r.movement ?? 'Exercise restriction',
                subtitle:
                    '${_cap(r.kind)} · since ${r.activeFrom}${r.note == null ? '' : ' · ${r.note}'}',
                trailing: 'End',
                onTap:
                    () => _save(
                      context,
                      () => ref
                          .read(lifestyleServiceProvider)
                          .endRestriction(r.id),
                    ),
              ),
          ]),
        ],
        _gap(),
        _field(
          'Movement (e.g. deep squat)',
          (v) => _movement = v,
          resetKey: _reset,
        ),
        _gap(10),
        PillTabs(
          labels: const ['Uncomfortable', 'Avoid', 'Modify'],
          index: _kind,
          layout: PillLayout.scroll,
          onChanged: (i) => setState(() => _kind = i),
        ),
        _gap(),
        AppButton(
          'Add restriction',
          onPressed: () async {
            final ok = await _save(
              context,
              () => ref
                  .read(lifestyleServiceProvider)
                  .addRestriction(kind: _kinds[_kind], movement: _movement),
            );
            if (ok && mounted) {
              setState(() {
                _movement = '';
                _reset++;
              });
            }
          },
        ),
      ],
    );
  }
}

// ---- Nutrition ----

/// What today's eaten meals add up to, from the saved meals (never recalculated on the server).
({double kcal, double protein, bool estimated}) _nutritionTotals(
  List<MealPlanEntry> plan,
  Map<String, Meal> meals,
) {
  var kcal = 0.0;
  var protein = 0.0;
  var estimated = false;
  for (final e in plan.where((e) => e.status != 'planned')) {
    final m =
        meals[e.status == 'replaced'
            ? (e.replacedByMealId ?? e.mealId)
            : e.mealId];
    if (m == null) continue;
    kcal += (m.caloriesKcal ?? 0) * e.servings;
    protein += (m.proteinG ?? 0) * e.servings;
    estimated = estimated || m.isEstimate;
  }
  return (kcal: kcal, protein: protein, estimated: estimated);
}

class _NutritionToday extends ConsumerWidget {
  const _NutritionToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final plan =
        ref.watch(mealPlanForProvider(_today())).valueOrNull ??
        const <MealPlanEntry>[];
    final meals = {
      for (final m in ref.watch(mealsProvider).valueOrNull ?? const <Meal>[])
        m.id: m,
    };
    final targets = ref.watch(targetsProvider).valueOrNull;
    final t = _nutritionTotals(plan, meals);
    Widget stat(String value, String note, Key key) => Expanded(
      child: Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: p.text,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(note, style: TextStyle(color: p.muted, fontSize: 16)),
        ],
      ),
    );
    final kcalTarget = targets?.caloriesKcal;
    return _Card(
      title: 'Today',
      children: [
        Row(
          children: [
            stat(
              '${_kg(t.kcal)} kcal',
              kcalTarget == null
                  ? 'No target set'
                  : 'of ${_kg(kcalTarget)} kcal',
              const Key('nutrition-kcal'),
            ),
            stat(
              '${_kg(t.protein)} g',
              targets?.proteinG == null
                  ? 'Protein'
                  : 'Protein · of ${_kg(targets!.proteinG!)} g',
              const Key('nutrition-protein'),
            ),
          ],
        ),
        _gap(14),
        MeterBar(
          value:
              kcalTarget == null || kcalTarget == 0
                  ? 0
                  : (t.kcal / kcalTarget).clamp(0, 1).toDouble(),
          trackColor: p.tile,
        ),
        if (t.estimated) ...[
          _gap(8),
          const MutedText('Includes estimates.', size: 14),
        ],
      ],
    );
  }
}

class _TodaysMeals extends ConsumerWidget {
  const _TodaysMeals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan =
        ref.watch(mealPlanForProvider(_today())).valueOrNull ??
        const <MealPlanEntry>[];
    final meals = {
      for (final m in ref.watch(mealsProvider).valueOrNull ?? const <Meal>[])
        m.id: m,
    };
    return _Card(
      title: 'Today’s meals',
      children: [
        if (plan.isEmpty)
          const NoteRow('No meals yet. Add one below.')
        else ...[
          RowList([
            for (final e in plan)
              RowItem(
                title: '${_cap(e.slot)} · ${meals[e.mealId]?.title ?? 'Meal'}',
                subtitle:
                    e.servings == 1 ? null : '${_kg(e.servings)} servings',
                trailing: _cap(e.status),
                onTap:
                    () => _save(
                      context,
                      () => ref
                          .read(lifestyleServiceProvider)
                          .setMealStatus(
                            e.id,
                            status: e.status == 'eaten' ? 'planned' : 'eaten',
                          ),
                    ),
              ),
          ]),
          _gap(8),
          const MutedText('Tap a meal to mark it eaten.', size: 14),
        ],
      ],
    );
  }
}

class _LogMeal extends ConsumerStatefulWidget {
  const _LogMeal();

  @override
  ConsumerState<_LogMeal> createState() => _LogMealState();
}

class _LogMealState extends ConsumerState<_LogMeal> {
  String _title = '';
  String _kcal = '';
  String _protein = '';
  int _category = 0;
  bool _estimate = false;
  int _reset = 0;

  Future<void> _run({required bool eaten}) async {
    final svc = ref.read(lifestyleServiceProvider);
    final category = mealCategories[_category];
    final ok = await _save(context, () async {
      final id = await svc.saveMeal(
        title: _title,
        category: category,
        caloriesKcal: _num(_kcal),
        proteinG: _num(_protein),
        isEstimate: _estimate,
      );
      if (eaten) await svc.logMealEaten(slot: category, mealId: id);
      return null;
    });
    if (ok && mounted) {
      setState(() {
        _title = '';
        _kcal = '';
        _protein = '';
        _reset++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Add a meal',
      children: [
        const FieldLabel('Meal name'),
        _field(
          'e.g. Chicken and rice',
          (v) => _title = v,
          resetKey: _reset,
          fieldKey: const Key('meal-title'),
        ),
        _gap(14),
        PillTabs(
          labels: [for (final c in mealCategories) _cap(c)],
          index: _category,
          container: true,
          onChanged: (i) => setState(() => _category = i),
        ),
        _gap(14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Calories'),
                  _field(
                    '0',
                    (v) => _kcal = v,
                    keyboard: _decimal,
                    suffix: 'kcal',
                    resetKey: _reset,
                    fieldKey: const Key('meal-kcal'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Protein'),
                  _field(
                    '0',
                    (v) => _protein = v,
                    keyboard: _decimal,
                    suffix: 'g',
                    resetKey: _reset,
                  ),
                ],
              ),
            ),
          ],
        ),
        _gap(14),
        const FieldLabel('Nutrition values'),
        PillTabs(
          labels: const ['Exact', 'Estimated'],
          index: _estimate ? 1 : 0,
          container: true,
          onChanged: (i) => setState(() => _estimate = i == 1),
        ),
        _gap(16),
        AppButton.primary(
          'Save meal',
          height: 58,
          onPressed: () => _run(eaten: false),
        ),
        _gap(10),
        AppButton(
          'Save and log as eaten',
          height: 58,
          onPressed: () => _run(eaten: true),
        ),
      ],
    );
  }
}

/// Meals saved before, to plan again today. Not shown until there is one.
class _SavedMeals extends ConsumerWidget {
  const _SavedMeals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(mealsProvider).valueOrNull ?? const <Meal>[];
    if (meals.isEmpty) return const SizedBox.shrink();
    return _Card(
      title: 'Saved meals',
      children: [
        RowList([
          for (final m in meals)
            RowItem(
              title: m.title,
              subtitle: [
                _cap(m.category),
                if (m.caloriesKcal != null) '${_kg(m.caloriesKcal!)} kcal',
                if (m.proteinG != null) '${_kg(m.proteinG!)} g protein',
                if (m.isEstimate) 'estimate',
              ].join(' · '),
              trailing: 'Plan today ›',
              onTap:
                  () => _save(
                    context,
                    () => ref
                        .read(lifestyleServiceProvider)
                        .planMeal(slot: m.category, mealId: m.id),
                  ),
            ),
        ]),
      ],
    );
  }
}

class _Targets extends ConsumerStatefulWidget {
  const _Targets();

  @override
  ConsumerState<_Targets> createState() => _TargetsState();
}

class _TargetsState extends ConsumerState<_Targets> {
  String _protein = '';
  String _kcal = '';
  String _water = '';
  String _steps = '';
  int _reset = 0;

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(targetsProvider).valueOrNull;
    // The box shows today's target as its hint, or a dash.
    String hint(num? v) => v == null ? '–' : _kg(v.toDouble());
    Widget labeled(String label, Widget field) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [FieldLabel(label), field],
      ),
    );
    return _Card(
      title: 'Targets',
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labeled(
              'Protein',
              _field(
                hint(t?.proteinG),
                (v) => _protein = v,
                keyboard: _decimal,
                suffix: 'g',
                resetKey: _reset,
                fieldKey: const Key('target-protein'),
              ),
            ),
            const SizedBox(width: 12),
            labeled(
              'Calories',
              _field(
                hint(t?.caloriesKcal),
                (v) => _kcal = v,
                keyboard: _decimal,
                suffix: 'kcal',
                resetKey: _reset,
              ),
            ),
          ],
        ),
        _gap(12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            labeled(
              'Water',
              _field(
                hint(t?.waterMl),
                (v) => _water = v,
                keyboard: TextInputType.number,
                suffix: 'ml',
                resetKey: _reset,
              ),
            ),
            const SizedBox(width: 12),
            labeled(
              'Steps',
              _field(
                hint(t?.stepTarget),
                (v) => _steps = v,
                keyboard: TextInputType.number,
                resetKey: _reset,
              ),
            ),
          ],
        ),
        _gap(14),
        AppButton(
          'Save targets',
          height: 56,
          onPressed: () async {
            final ok = await _save(
              context,
              () => ref
                  .read(lifestyleServiceProvider)
                  .setTargets(
                    proteinG: _num(_protein),
                    caloriesKcal: _num(_kcal),
                    waterMl: int.tryParse(_water.trim()),
                    stepTarget: int.tryParse(_steps.trim()),
                  ),
            );
            if (ok && mounted) {
              setState(() {
                _protein = _kcal = _water = _steps = '';
                _reset++;
              });
            }
          },
        ),
        _gap(10),
        const MutedText(
          'Only filled boxes change. Earlier targets stay in history.',
          size: 15,
        ),
      ],
    );
  }
}

// ---- Supplements ----

class _SupplementsToday extends ConsumerWidget {
  const _SupplementsToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplements =
        ref.watch(supplementsProvider).valueOrNull ?? const <Supplement>[];
    final logs =
        ref.watch(supplementLogsForProvider(_today())).valueOrNull ??
        const <SupplementLog>[];
    return _Card(
      title: 'Supplements today',
      children: [
        if (supplements.isEmpty)
          const NoteRow('None added yet.')
        else
          for (final s in supplements)
            _SupplementRow(
              supplement: s,
              logs: [
                for (final l in logs)
                  if (l.supplementId == s.id) l,
              ],
            ),
      ],
    );
  }
}

class _SupplementRow extends ConsumerWidget {
  const _SupplementRow({required this.supplement, required this.logs});

  final Supplement supplement;
  final List<SupplementLog> logs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final phase = ref.watch(supplementPhaseProvider(supplement.id)).valueOrNull;
    final svc = ref.read(lifestyleServiceProvider);
    final taken = logs.where((l) => l.outcome == 'taken').length;
    final dose =
        phase?.doseAmount == null
            ? null
            : '${_kg(phase!.doseAmount!)} ${phase.doseUnit ?? ''}'.trim();
    final status = phase?.status ?? 'active';
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            supplement.name,
            style: TextStyle(
              color: p.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            [
              if (dose != null) dose,
              '${phase?.timesPerDay ?? 1}× a day',
              _cap(status),
              '$taken taken today',
            ].join(' · '),
            style: TextStyle(color: p.muted, fontSize: 14),
          ),
          _gap(8),
          Row(
            children: [
              Expanded(
                child: AppButton.primary(
                  'Taken',
                  height: 44,
                  onPressed:
                      status != 'active'
                          ? null
                          : () => _save(
                            context,
                            () => svc.logSupplement(supplement.id),
                          ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  'Skipped',
                  height: 44,
                  onPressed:
                      status != 'active'
                          ? null
                          : () => _save(
                            context,
                            () => svc.logSupplement(
                              supplement.id,
                              outcome: 'skipped',
                            ),
                          ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AppButton(
                  status == 'active' ? 'Pause' : 'Resume',
                  height: 44,
                  onPressed:
                      () => _save(
                        context,
                        () => svc.changeSupplementPhase(
                          supplement.id,
                          status: status == 'active' ? 'paused' : 'active',
                        ),
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AddSupplement extends ConsumerStatefulWidget {
  const _AddSupplement();

  @override
  ConsumerState<_AddSupplement> createState() => _AddSupplementState();
}

class _AddSupplementState extends ConsumerState<_AddSupplement> {
  String _name = '';
  String _dose = '';
  String _unit = '';
  int _times = 0;
  int _reset = 0;

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Add a supplement',
      sub: 'Your own schedule. Nothing here is a recommendation.',
      children: [
        const FieldLabel('Name'),
        _field(
          'e.g. Creatine',
          (v) => _name = v,
          resetKey: _reset,
          fieldKey: const Key('supplement-name'),
        ),
        _gap(14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Dose'),
                  _field(
                    '5',
                    (v) => _dose = v,
                    keyboard: _decimal,
                    resetKey: _reset,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Unit'),
                  _field('g, mg…', (v) => _unit = v, resetKey: _reset),
                ],
              ),
            ),
          ],
        ),
        _gap(14),
        const FieldLabel('Times per day'),
        _Squares(
          labels: const ['1', '2', '3', '4'],
          index: _times,
          keyPrefix: 'times',
          onChanged: (i) => setState(() => _times = i),
        ),
        _gap(16),
        AppButton.primary(
          'Save supplement',
          height: 58,
          onPressed: () async {
            final ok = await _save(
              context,
              () => ref
                  .read(lifestyleServiceProvider)
                  .addSupplement(
                    name: _name,
                    doseAmount: _num(_dose),
                    doseUnit: _unit,
                    timesPerDay: _times + 1,
                  ),
            );
            if (ok && mounted) {
              setState(() {
                _name = _dose = _unit = '';
                _reset++;
              });
            }
          },
        ),
      ],
    );
  }
}

// ---- Activity ----

/// One short row under the Steps card: the Health Connect tile and the Manual log button.
class _StepsActions extends StatelessWidget {
  const _StepsActions();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 62,
      child: Row(
        children: [
          Expanded(child: StepImportCard()),
          SizedBox(width: 10),
          SizedBox(width: 132, child: ManualLogButton()),
        ],
      ),
    );
  }
}

class _LogCardio extends ConsumerStatefulWidget {
  const _LogCardio();

  @override
  ConsumerState<_LogCardio> createState() => _LogCardioState();
}

class _LogCardioState extends ConsumerState<_LogCardio> {
  int _activity = 0;
  int _intensity = 1;
  String _custom = '';
  String _minutes = '';
  String _km = '';
  int _reset = 0;
  static const _intensities = ['low', 'moderate', 'high'];

  @override
  Widget build(BuildContext context) {
    final recent =
        ref.watch(recentCardioProvider).valueOrNull ?? const <CardioSession>[];
    final isCustom = cardioActivities[_activity] == 'custom';
    return _Card(
      title: 'Log cardio',
      children: [
        PillTabs(
          labels: [for (final a in cardioActivities) _cap(a)],
          index: _activity,
          container: true,
          layout: PillLayout.scroll,
          onChanged: (i) => setState(() => _activity = i),
        ),
        if (isCustom) ...[
          _gap(12),
          const FieldLabel('Activity name'),
          _field('e.g. Rowing', (v) => _custom = v, resetKey: _reset),
        ],
        _gap(14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Duration'),
                  _field(
                    '0',
                    (v) => _minutes = v,
                    keyboard: _decimal,
                    suffix: 'min',
                    resetKey: _reset,
                    fieldKey: const Key('cardio-minutes'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FieldLabel('Distance'),
                  _field(
                    'optional',
                    (v) => _km = v,
                    keyboard: _decimal,
                    suffix: 'km',
                    resetKey: _reset,
                  ),
                ],
              ),
            ),
          ],
        ),
        _gap(14),
        const FieldLabel('Intensity'),
        PillTabs(
          labels: const ['Low', 'Moderate', 'High'],
          index: _intensity,
          container: true,
          onChanged: (i) => setState(() => _intensity = i),
        ),
        _gap(16),
        AppButton.primary(
          'Save cardio',
          height: 58,
          onPressed: () async {
            final minutes = _num(_minutes);
            if (minutes == null) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enter the minutes.')),
              );
              return;
            }
            final km = _num(_km);
            final ok = await _save(
              context,
              () => ref
                  .read(lifestyleServiceProvider)
                  .logCardio(
                    activity: cardioActivities[_activity],
                    customActivity: _custom,
                    durationSeconds: (minutes * 60).round(),
                    distanceM: km == null ? null : km * 1000,
                    intensity: _intensities[_intensity],
                  ),
            );
            if (ok && mounted) {
              setState(() {
                _minutes = _km = _custom = '';
                _reset++;
              });
            }
          },
        ),
        if (recent.isNotEmpty) ...[
          _gap(),
          RowList([
            for (final c in recent.take(3))
              RowItem(
                title: '${c.label} · ${(c.durationSeconds / 60).round()} min',
                subtitle: [
                  c.localDate,
                  if (c.distanceM != null)
                    '${(c.distanceM! / 1000).toStringAsFixed(1)} km',
                  if (c.intensity != null) c.intensity!,
                ].join(' · '),
              ),
          ]),
        ],
      ],
    );
  }
}
