import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/meters.dart';
import '../data/lifestyle_models.dart';
import '../data/lifestyle_providers.dart';
import '../data/lifestyle_service.dart';

/// Lifestyle section: Overview, Recovery, Nutrition, Supplements and Activity. Everything is read from the phone and
/// saved through [LifestyleService] (local first, synced later). Wording stays observational, never medical advice.
/// Recovery readiness and other backend-calculated values are not worked out here (Phase 7).
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
          _SleepCard(),
          _InjuriesCard(),
          _PainCard(),
          _RestrictionsCard(),
        ];
      case 2:
        return const [_NutritionToday(), _LogMeal(), _SavedMeals(), _Targets()];
      case 3:
        return const [_SupplementsToday(), _AddSupplement()];
      case 4:
        return const [_StepsCard(), _LogCardio(), _WaterCard()];
      default:
        return [
          const _TodayLifestyle(),
          const _RecoveryReadiness(),
          const _CheckinCard(),
          const _WaterCard(),
          _QuickLog(onGo: (i) => setState(() => _tab = i)),
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

/// A text box that clears itself when [resetKey] changes (after a save).
Widget _field(
  String hint,
  ValueChanged<String> onChanged, {
  Object? resetKey,
  TextInputType? keyboard,
  String initial = '',
  Key? fieldKey,
}) => FieldBox(
  key: ValueKey('$hint-$resetKey'),
  fieldKey: fieldKey,
  hint: hint,
  initial: initial,
  keyboard: keyboard,
  onChanged: onChanged,
);

const _decimal = TextInputType.numberWithOptions(decimal: true);

// ---- Overview ----

class _TodayLifestyle extends ConsumerWidget {
  const _TodayLifestyle();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final day = ref.watch(daySummaryProvider(_today())).valueOrNull;
    final targets = ref.watch(targetsProvider).valueOrNull;
    Widget tile(String label, String value, double? v, String foot) =>
        InnerTile(
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
              MeterBar(
                value: (v ?? 0).clamp(0, 1).toDouble(),
                trackColor: p.card,
              ),
              const SizedBox(height: 6),
              Text(foot, style: TextStyle(color: p.muted, fontSize: 13)),
            ],
          ),
        );
    final stepTarget = day?.steps?.targetSteps ?? targets?.stepTarget;
    final steps = day?.steps?.steps;
    final water = day?.waterMl ?? 0;
    return TitledCard(
      title: 'Today’s lifestyle',
      children: [
        ButtonPair(
          tile(
            'Sleep',
            day == null || day.sleepSeconds == 0
                ? '–'
                : '${(day.sleepSeconds / 3600).toStringAsFixed(1)} h',
            null,
            'Last night',
          ),
          tile(
            'Meals',
            day == null ? '–' : '${day.mealsEaten} / ${day.mealsPlanned}',
            day == null || day.mealsPlanned == 0
                ? null
                : day.mealsEaten / day.mealsPlanned,
            'Eaten',
          ),
        ),
        _gap(),
        ButtonPair(
          tile(
            'Water',
            '${(water / 1000).toStringAsFixed(1)} L',
            targets?.waterMl == null ? null : water / targets!.waterMl!,
            targets?.waterMl == null
                ? 'No target set'
                : 'of ${(targets!.waterMl! / 1000).toStringAsFixed(1)} L',
          ),
          tile(
            'Steps',
            steps == null ? '–' : '$steps',
            stepTarget == null || steps == null ? null : steps / stepTarget,
            stepTarget == null ? 'No target set' : 'of $stepTarget',
          ),
        ),
      ],
    );
  }
}

class _RecoveryReadiness extends StatelessWidget {
  const _RecoveryReadiness();

  @override
  Widget build(BuildContext context) {
    return const TitledCard(
      title: 'Recovery and readiness',
      sample: true,
      children: [
        MutedText(
          'Readiness is calculated by the backend from your check-ins, sleep and training, and will appear here in a later step.',
        ),
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
    final today = _today();
    final existing = ref.watch(checkinProvider(today)).valueOrNull;
    _load(existing);
    return TitledCard(
      title: 'Daily check-in',
      children: [
        const MutedText(
          '1 is low, 5 is high. One check-in per day; saving again updates it.',
        ),
        for (var i = 0; i < _names.length; i++) ...[
          _gap(10),
          FieldLabel(_names[i]),
          PillTabs(
            labels: const ['1', '2', '3', '4', '5'],
            index: (_values[i] ?? 0) - 1 < 0 ? -1 : _values[i]! - 1,
            onChanged: (n) => setState(() => _values[i] = n + 1),
          ),
        ],
        _gap(10),
        PillTabs(
          labels: const ['No pain today', 'Some pain'],
          index: _pain ? 1 : 0,
          onChanged: (n) => setState(() => _pain = n == 1),
        ),
        _gap(10),
        _field(
          'Notes',
          (v) => _notes = v,
          initial: _notes,
          resetKey: existing?.id,
        ),
        _gap(),
        AppButton.primary(
          'Save check-in',
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

class _WaterCard extends ConsumerStatefulWidget {
  const _WaterCard();

  @override
  ConsumerState<_WaterCard> createState() => _WaterCardState();
}

class _WaterCardState extends ConsumerState<_WaterCard> {
  String _custom = '';
  int _reset = 0;

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final logs =
        ref.watch(waterForProvider(today)).valueOrNull ?? const <WaterLog>[];
    final targets = ref.watch(targetsProvider).valueOrNull;
    final total = logs.fold<int>(0, (a, w) => a + w.amountMl);
    Future<void> add(int ml) =>
        _save(context, () => ref.read(lifestyleServiceProvider).addWater(ml));
    return TitledCard(
      title: 'Hydration',
      children: [
        Text(
          targets?.waterMl == null
              ? '$total ml today'
              : '$total / ${targets!.waterMl} ml today',
          style: TextStyle(
            color: context.pal.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (targets?.waterMl != null) ...[
          _gap(10),
          MeterBar(value: (total / targets!.waterMl!).clamp(0, 1).toDouble()),
        ],
        _gap(),
        ButtonPair(
          AppButton('+ 250 ml', onPressed: () => add(250)),
          AppButton('+ 500 ml', onPressed: () => add(500)),
        ),
        _gap(),
        Row(
          children: [
            Expanded(
              child: _field(
                'Other amount (ml)',
                (v) => _custom = v,
                keyboard: TextInputType.number,
                resetKey: _reset,
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: AppButton(
                'Add',
                onPressed: () async {
                  final ml = int.tryParse(_custom.trim());
                  if (ml == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Enter the amount in ml.')),
                    );
                    return;
                  }
                  if (await _save(
                    context,
                    () => ref.read(lifestyleServiceProvider).addWater(ml),
                  )) {
                    setState(() {
                      _custom = '';
                      _reset++;
                    });
                  }
                },
              ),
            ),
          ],
        ),
        if (logs.isNotEmpty) ...[
          _gap(),
          RowList([
            for (final w in logs.reversed.take(4))
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

String _timeText(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}';
}

class _QuickLog extends StatelessWidget {
  const _QuickLog({required this.onGo});

  final ValueChanged<int> onGo;

  @override
  Widget build(BuildContext context) {
    Widget b(String l, int tab) =>
        AppButton(l, height: 46, onPressed: () => onGo(tab));
    return TitledCard(
      title: 'Quick log',
      children: [
        ButtonPair(b('Sleep log', 1), b('Pain / injury', 1)),
        _gap(10),
        ButtonPair(b('Meals', 2), b('Supplements', 3)),
        _gap(10),
        ButtonPair(b('Cardio', 4), b('Steps', 4)),
      ],
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
    return TitledCard(
      title: 'Sleep',
      children: [
        const MutedText(
          'Log how long you slept. It is saved under the day you woke up.',
        ),
        _gap(10),
        _field(
          'Hours slept (e.g. 7.5)',
          (v) => _hours = v,
          keyboard: _decimal,
          resetKey: _reset,
          fieldKey: const Key('sleep-hours'),
        ),
        _gap(10),
        const FieldLabel('Quality (optional)'),
        PillTabs(
          labels: const ['1', '2', '3', '4', '5'],
          index: _quality,
          onChanged: (i) => setState(() => _quality = i),
        ),
        _gap(10),
        PillTabs(
          labels: const ['Night', 'Nap'],
          index: _nap ? 1 : 0,
          onChanged: (i) => setState(() => _nap = i == 1),
        ),
        _gap(),
        AppButton.primary(
          'Save sleep',
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
            for (final s in recent.take(5))
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

class _InjuriesCard extends ConsumerStatefulWidget {
  const _InjuriesCard();

  @override
  ConsumerState<_InjuriesCard> createState() => _InjuriesCardState();
}

class _InjuriesCardState extends ConsumerState<_InjuriesCard> {
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
    return TitledCard(
      title: 'Injuries',
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
    final regions =
        ref.watch(bodyRegionsProvider).valueOrNull ?? const <BodyRegion>[];
    final recent =
        ref.watch(recentPainProvider).valueOrNull ?? const <PainEntry>[];
    final names = {for (final r in regions) r.id: r.name};
    return TitledCard(
      title: 'Pain check-in',
      children: [
        const MutedText(
          'A note of where it hurts and how much (0 none, 10 worst). This is a log, not medical advice.',
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
          labels: [for (var i = 0; i <= 10; i++) '$i'],
          index: _level,
          layout: PillLayout.scroll,
          onChanged: (i) => setState(() => _level = i),
        ),
        _gap(10),
        const FieldLabel('Effect on training'),
        PillTabs(
          labels: const ['None', 'Minor', 'Limited', 'Stopped'],
          index: _effect,
          onChanged: (i) => setState(() => _effect = i),
        ),
        _gap(),
        AppButton(
          'Save pain entry',
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
            for (final e in recent.take(4))
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

class _RestrictionsCard extends ConsumerStatefulWidget {
  const _RestrictionsCard();

  @override
  ConsumerState<_RestrictionsCard> createState() => _RestrictionsCardState();
}

class _RestrictionsCardState extends ConsumerState<_RestrictionsCard> {
  String _movement = '';
  int _kind = 0;
  int _reset = 0;
  static const _kinds = ['uncomfortable', 'avoid', 'modify'];

  @override
  Widget build(BuildContext context) {
    final list =
        ref.watch(restrictionsProvider).valueOrNull ??
        const <ExerciseRestriction>[];
    return TitledCard(
      title: 'Restrictions',
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

class _NutritionToday extends ConsumerWidget {
  const _NutritionToday();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = _today();
    final plan =
        ref.watch(mealPlanForProvider(today)).valueOrNull ??
        const <MealPlanEntry>[];
    final meals = {
      for (final m in ref.watch(mealsProvider).valueOrNull ?? const <Meal>[])
        m.id: m,
    };
    final targets = ref.watch(targetsProvider).valueOrNull;
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
    return TitledCard(
      title: 'Nutrition today',
      children: [
        if (plan.isEmpty)
          const MutedText(
            'No meals planned for today. Save a meal below and plan or log it.',
          )
        else
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
        _gap(10),
        MutedText(
          'Tap a meal to mark it eaten. Totals so far: ${_kg(kcal)} kcal · ${_kg(protein)} g protein${estimated ? ' (includes estimates)' : ''}'
          '${targets?.caloriesKcal == null ? '' : ' · target ${_kg(targets!.caloriesKcal!)} kcal'}'
          '${targets?.proteinG == null ? '' : ' / ${_kg(targets!.proteinG!)} g'}',
        ),
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
    return TitledCard(
      title: 'Add a meal',
      children: [
        _field(
          'Meal name',
          (v) => _title = v,
          resetKey: _reset,
          fieldKey: const Key('meal-title'),
        ),
        _gap(10),
        PillTabs(
          labels: [for (final c in mealCategories) _cap(c)],
          index: _category,
          layout: PillLayout.scroll,
          onChanged: (i) => setState(() => _category = i),
        ),
        _gap(10),
        Row(
          children: [
            Expanded(
              child: _field(
                'kcal',
                (v) => _kcal = v,
                keyboard: _decimal,
                resetKey: _reset,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                'protein g',
                (v) => _protein = v,
                keyboard: _decimal,
                resetKey: _reset,
              ),
            ),
          ],
        ),
        _gap(10),
        PillTabs(
          labels: const ['Values are exact', 'Values are estimates'],
          index: _estimate ? 1 : 0,
          onChanged: (i) => setState(() => _estimate = i == 1),
        ),
        _gap(),
        ButtonPair(
          AppButton('Save meal', onPressed: () => _run(eaten: false)),
          AppButton.primary(
            'Save and log eaten',
            onPressed: () => _run(eaten: true),
          ),
        ),
      ],
    );
  }
}

class _SavedMeals extends ConsumerWidget {
  const _SavedMeals();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meals = ref.watch(mealsProvider).valueOrNull ?? const <Meal>[];
    return TitledCard(
      title: 'Saved meals',
      children: [
        if (meals.isEmpty)
          const MutedText('Meals you save appear here.')
        else
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
    String? shown(num? v) => v == null ? null : _kg(v.toDouble());
    return TitledCard(
      title: 'Targets',
      children: [
        MutedText(
          t == null
              ? 'No targets set yet.'
              : 'Protein ${shown(t.proteinG) ?? '–'} g · ${shown(t.caloriesKcal) ?? '–'} kcal · water ${t.waterMl ?? '–'} ml · steps ${t.stepTarget ?? '–'}',
        ),
        _gap(10),
        Row(
          children: [
            Expanded(
              child: _field(
                'protein g',
                (v) => _protein = v,
                keyboard: _decimal,
                resetKey: _reset,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                'kcal',
                (v) => _kcal = v,
                keyboard: _decimal,
                resetKey: _reset,
              ),
            ),
          ],
        ),
        _gap(10),
        Row(
          children: [
            Expanded(
              child: _field(
                'water ml',
                (v) => _water = v,
                keyboard: TextInputType.number,
                resetKey: _reset,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                'steps',
                (v) => _steps = v,
                keyboard: TextInputType.number,
                resetKey: _reset,
              ),
            ),
          ],
        ),
        _gap(),
        AppButton(
          'Save new targets',
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
          'Only the boxes you fill are changed. Earlier targets stay in the history.',
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
    return TitledCard(
      title: 'Supplements today',
      children: [
        if (supplements.isEmpty)
          const MutedText('No supplements added yet.')
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
    return TitledCard(
      title: 'Add a supplement',
      children: [
        const MutedText(
          'Your own schedule, as you take it. Nothing here is a recommendation.',
        ),
        _gap(10),
        _field(
          'Name',
          (v) => _name = v,
          resetKey: _reset,
          fieldKey: const Key('supplement-name'),
        ),
        _gap(10),
        Row(
          children: [
            Expanded(
              child: _field(
                'Dose',
                (v) => _dose = v,
                keyboard: _decimal,
                resetKey: _reset,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                'Unit (g, mg…)',
                (v) => _unit = v,
                resetKey: _reset,
              ),
            ),
          ],
        ),
        _gap(10),
        const FieldLabel('Times per day'),
        PillTabs(
          labels: const ['1', '2', '3', '4'],
          index: _times,
          onChanged: (i) => setState(() => _times = i),
        ),
        _gap(),
        AppButton.primary(
          'Save supplement',
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

class _StepsCard extends ConsumerStatefulWidget {
  const _StepsCard();

  @override
  ConsumerState<_StepsCard> createState() => _StepsCardState();
}

class _StepsCardState extends ConsumerState<_StepsCard> {
  String _steps = '';
  int _reset = 0;

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final steps = ref.watch(stepsForProvider(today)).valueOrNull;
    final targets = ref.watch(targetsProvider).valueOrNull;
    final target = steps?.targetSteps ?? targets?.stepTarget;
    final count = steps?.steps;
    return TitledCard(
      title: 'Steps',
      children: [
        Text(
          count == null
              ? 'No steps entered today'
              : (target == null ? '$count steps' : '$count / $target steps'),
          style: TextStyle(
            color: context.pal.text,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (count != null && target != null) ...[
          _gap(10),
          MeterBar(value: (count / target).clamp(0, 1).toDouble()),
        ],
        _gap(10),
        const MutedText(
          'Entered by hand for now. Phone step counting is added later as another source.',
        ),
        _gap(10),
        Row(
          children: [
            Expanded(
              child: _field(
                'Steps today',
                (v) => _steps = v,
                keyboard: TextInputType.number,
                resetKey: _reset,
                fieldKey: const Key('steps-field'),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 110,
              child: AppButton(
                'Save',
                onPressed: () async {
                  final n = int.tryParse(_steps.trim());
                  if (n == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Enter the number of steps.'),
                      ),
                    );
                    return;
                  }
                  if (await _save(
                    context,
                    () => ref.read(lifestyleServiceProvider).setSteps(n),
                  )) {
                    setState(() {
                      _steps = '';
                      _reset++;
                    });
                  }
                },
              ),
            ),
          ],
        ),
      ],
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
  int _intensity = -1;
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
    return TitledCard(
      title: 'Log cardio',
      children: [
        PillTabs(
          labels: [for (final a in cardioActivities) _cap(a)],
          index: _activity,
          layout: PillLayout.scroll,
          onChanged: (i) => setState(() => _activity = i),
        ),
        if (isCustom) ...[
          _gap(10),
          _field('Activity name', (v) => _custom = v, resetKey: _reset),
        ],
        _gap(10),
        Row(
          children: [
            Expanded(
              child: _field(
                'minutes',
                (v) => _minutes = v,
                keyboard: _decimal,
                resetKey: _reset,
                fieldKey: const Key('cardio-minutes'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _field(
                'km (optional)',
                (v) => _km = v,
                keyboard: _decimal,
                resetKey: _reset,
              ),
            ),
          ],
        ),
        _gap(10),
        PillTabs(
          labels: const ['Low', 'Moderate', 'High'],
          index: _intensity,
          onChanged: (i) => setState(() => _intensity = i),
        ),
        _gap(),
        AppButton.primary(
          'Save cardio',
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
                    intensity: _intensity < 0 ? null : _intensities[_intensity],
                  ),
            );
            if (ok && mounted) {
              setState(() {
                _minutes = _km = _custom = '';
                _intensity = -1;
                _reset++;
              });
            }
          },
        ),
        if (recent.isNotEmpty) ...[
          _gap(),
          RowList([
            for (final c in recent.take(5))
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
