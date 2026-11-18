import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/section_widgets.dart';
import '../data/lifestyle_models.dart';
import '../data/lifestyle_providers.dart';
import 'steps_format.dart';

enum _Range { day, week, month }

/// Opened from the Steps card. Day, Week and Month views of the step counts already on the phone (typed by hand or
/// imported from Health Connect), with previous/next navigation, a total, a bar chart and a date-wise list.
class StepsHistoryScreen extends ConsumerStatefulWidget {
  const StepsHistoryScreen({super.key});

  @override
  ConsumerState<StepsHistoryScreen> createState() => _StepsHistoryScreenState();
}

class _StepsHistoryScreenState extends ConsumerState<StepsHistoryScreen> {
  _Range _range = _Range.week;
  late DateTime _anchor = parseDateKey(localStampOf(DateTime.now()).localDate);

  DateTime get _today => parseDateKey(localStampOf(DateTime.now()).localDate);

  /// First and last day of the period being looked at.
  (DateTime, DateTime) get _period {
    switch (_range) {
      case _Range.day:
        return (_anchor, _anchor);
      case _Range.week:
        final start = mondayOf(_anchor);
        return (start, addDays(start, 6));
      case _Range.month:
        return (
          DateTime(_anchor.year, _anchor.month, 1),
          DateTime(_anchor.year, _anchor.month + 1, 0),
        );
    }
  }

  void _step(int dir) {
    setState(() {
      switch (_range) {
        case _Range.day:
          _anchor = addDays(_anchor, dir);
        case _Range.week:
          _anchor = addDays(_anchor, 7 * dir);
        case _Range.month:
          _anchor = DateTime(_anchor.year, _anchor.month + dir, 1);
      }
    });
  }

  String _periodLabel() {
    final (start, end) = _period;
    switch (_range) {
      case _Range.day:
        if (start == _today) return 'Today';
        if (start == addDays(_today, -1)) return 'Yesterday';
        return longDay(start);
      case _Range.week:
        return '${shortDay(start)} – ${shortDay(end)}';
      case _Range.month:
        return '${monthNames[start.month - 1]} ${start.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final history =
        ref.watch(stepHistoryProvider).valueOrNull ?? const <DailySteps>[];
    final target = ref.watch(targetsProvider).valueOrNull?.stepTarget;
    final byDay = {for (final d in history) d.localDate: d};
    final today = _today;
    final (start, end) = _period;

    // The Day tab has only one number per day, so its chart shows the week that ends on the chosen day.
    final chartDays = <DateTime>[];
    if (_range == _Range.day) {
      for (var i = 6; i >= 0; i--) {
        chartDays.add(addDays(start, -i));
      }
    } else {
      for (var d = start; !d.isAfter(end); d = addDays(d, 1)) {
        chartDays.add(d);
      }
    }
    int stepsOn(DateTime d) => byDay[dateKey(d)]?.steps ?? 0;

    final periodDays = [
      for (var d = start; !d.isAfter(end); d = addDays(d, 1))
        if (!d.isAfter(today)) d,
    ];
    final total = periodDays.fold<int>(0, (a, d) => a + stepsOn(d));
    final withData =
        periodDays.where((d) => byDay.containsKey(dateKey(d))).length;
    final average = withData == 0 ? 0 : (total / withData).round();

    final listDays = [
      for (final d in chartDays.reversed)
        if (!d.isAfter(today) && byDay.containsKey(dateKey(d))) d,
    ];
    final canNext = end.isBefore(today);

    return ScreenFrame(
      title: 'Steps',
      subtitle: 'Daily history',
      leading: HeaderIconButton(
        key: const Key('steps-back'),
        icon: Icons.chevron_left,
        tooltip: 'Back',
        onTap: () {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go(AppRoutes.lifestyle);
          }
        },
      ),
      children: [
        PillTabs(
          labels: const ['Day', 'Week', 'Month'],
          index: _range.index,
          container: true,
          onChanged:
              (i) => setState(() {
                _range = _Range.values[i];
                // Keep the anchor inside today's period when switching so the view never lands in the future.
                if (_anchor.isAfter(today)) _anchor = today;
              }),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    key: const Key('steps-prev'),
                    tooltip: 'Previous',
                    onPressed: () => _step(-1),
                    icon: Icon(Icons.chevron_left, color: p.text),
                  ),
                  Expanded(
                    child: Text(
                      _periodLabel(),
                      key: const Key('steps-period'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: p.text,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('steps-next'),
                    tooltip: 'Next',
                    onPressed: canNext ? () => _step(1) : null,
                    icon: Icon(
                      Icons.chevron_right,
                      color: canNext ? p.text : p.faint,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Center(
                child: Column(
                  children: [
                    Text(
                      formatSteps(total),
                      key: const Key('steps-total'),
                      style: TextStyle(
                        color: p.text,
                        fontSize: 40,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _range == _Range.day
                          ? 'steps'
                          : 'steps · avg ${formatSteps(average)} a day',
                      style: TextStyle(color: p.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _StepsBars(
                days: chartDays,
                steps: [
                  for (final d in chartDays) d.isAfter(today) ? 0 : stepsOn(d),
                ],
                target: target,
                highlight: _range == _Range.day ? start : null,
                month: _range == _Range.month,
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'By date',
                style: TextStyle(
                  color: p.text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              if (listDays.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: NoteRow('No steps saved for these days.'),
                )
              else
                for (var i = 0; i < listDays.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: p.divider),
                  _DayRow(
                    day: listDays[i],
                    record: byDay[dateKey(listDays[i])]!,
                    target: target,
                    onTap:
                        _range == _Range.day
                            ? null
                            : () => setState(() {
                              _range = _Range.day;
                              _anchor = listDays[i];
                            }),
                  ),
                ],
            ],
          ),
        ),
        const MutedText(
          'A day you type in by hand is never overwritten by a Health Connect import.',
          size: 13,
        ),
      ],
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({
    required this.day,
    required this.record,
    required this.target,
    this.onTap,
  });

  final DateTime day;
  final DailySteps record;
  final int? target;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final goal = record.targetSteps ?? target;
    final met = goal != null && record.steps >= goal;
    return InkWell(
      key: Key('steps-row-${dateKey(day)}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    longDay(day),
                    style: TextStyle(
                      color: p.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    record.source == 'device_import'
                        ? 'Health Connect'
                        : (record.source == 'estimate'
                            ? 'Estimate'
                            : 'Typed by hand'),
                    style: TextStyle(color: p.muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            if (met)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.check_circle, size: 16, color: p.green),
              ),
            Text(
              '${formatSteps(record.steps)} steps',
              style: TextStyle(
                color: p.text,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bars for each day, a dashed goal line and a few date labels underneath.
/// Google Fit-inspired chart with a consistent 10,000-step scale,
/// horizontal reference lines, and daily bars.
class _StepsBars extends StatelessWidget {
  const _StepsBars({
    required this.days,
    required this.steps,
    required this.target,
    required this.highlight,
    required this.month,
  });

  final List<DateTime> days;
  final List<int> steps;
  final int? target;
  final DateTime? highlight;
  final bool month;

  static const double _plot = 180;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;

    // Keep the scale at 10,000 instead of stretching the tallest bar.
    var top = 10000;

    if (target != null && target! > top) {
      top = target!;
    }

    for (final value in steps) {
      if (value > top) top = value;
    }

    final goal = target ?? 10000;
    final goalTop = _plot * (1 - goal / top);

    String label(int i) {
      final d = days[i];

      if (!month) {
        return weekdayNames[d.weekday - 1].substring(0, 3);
      }

      return (d.day == 1 || (d.day - 1) % 7 == 0) && d.day <= 29
          ? '${d.day}'
          : '';
    }

    return Column(
      children: [
        SizedBox(
          height: _plot,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    // Horizontal reference lines.
                    Positioned.fill(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(height: 1, color: p.divider),
                          Container(height: 1, color: p.divider),
                          Container(height: 2, color: p.divider),
                        ],
                      ),
                    ),

                    // Dashed step goal line.
                    Positioned(
                      top: goalTop.clamp(0.0, _plot - 1),
                      left: 0,
                      right: 0,
                      child: Row(
                        children: [
                          for (var i = 0; i < 36; i++)
                            Expanded(
                              child: Container(
                                height: 1,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                ),
                                color:
                                    i.isEven
                                        ? p.muted.withValues(alpha: 0.7)
                                        : Colors.transparent,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Daily bars.
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          for (var i = 0; i < days.length; i++)
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: Container(
                                  key: Key('steps-bar-${dateKey(days[i])}'),
                                  width: month ? 5 : 18,
                                  height:
                                      steps[i] == 0
                                          ? 2
                                          : (_plot * steps[i] / top)
                                              .clamp(2, _plot)
                                              .toDouble(),
                                  decoration: BoxDecoration(
                                    color:
                                        steps[i] == 0
                                            ? p.tile
                                            : (highlight == null ||
                                                    days[i] == highlight
                                                ? p.primary
                                                : p.primary.withValues(
                                                  alpha: 0.65,
                                                )),
                                    borderRadius: BorderRadius.circular(
                                      month ? 2 : 5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Right-side scale labels.
              SizedBox(
                width: 46,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatSteps(top),
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
                    Text(
                      formatSteps(top ~/ 2),
                      style: TextStyle(color: p.muted, fontSize: 11),
                    ),
                    Text('0', style: TextStyle(color: p.muted, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // Day labels aligned with their respective bars.
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < days.length; i++)
                    Expanded(
                      child: SizedBox(
                        height: 18,
                        child: Center(
                          child: Text(
                            label(i),
                            softWrap: false,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: p.faint,
                              fontSize: 11,
                              fontWeight:
                                  highlight == days[i]
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 46),
          ],
        ),

        if (target != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Goal ${formatSteps(target!)}',
              style: TextStyle(color: p.green, fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
