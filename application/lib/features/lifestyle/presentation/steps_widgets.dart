import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/time/local_stamp.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../training/presentation/training_dialogs.dart' show ModalCard;
import '../data/lifestyle_providers.dart';
import 'steps_format.dart';

String _todayKey() => localStampOf(DateTime.now()).localDate;

/// Activity tab: today's steps and a tiny seven-day chart. Tapping it opens the Steps History screen.
class StepsSummaryCard extends ConsumerWidget {
  const StepsSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final today = parseDateKey(_todayKey());
    final history = ref.watch(stepHistoryProvider).valueOrNull ?? const [];
    final targets = ref.watch(targetsProvider).valueOrNull;
    final byDay = {for (final d in history) d.localDate: d};
    final todayRow = byDay[dateKey(today)];
    final target = todayRow?.targetSteps ?? targets?.stepTarget;
    final days = [for (var i = 6; i >= 0; i--) addDays(today, -i)];
    final values = [for (final d in days) (byDay[dateKey(d)]?.steps ?? 0)];
    var top = target ?? 0;
    for (final v in values) {
      if (v > top) top = v;
    }
    if (top <= 0) top = 1;

    return AppCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: const Key('steps-card'),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap: () => context.push(AppRoutes.steps),
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.cardPadding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.directions_walk, size: 18, color: p.link),
                        const SizedBox(width: 6),
                        Text(
                          'Steps',
                          style: TextStyle(
                            color: p.muted,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Icon(Icons.chevron_right, size: 18, color: p.muted),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      todayRow == null ? '–' : formatSteps(todayRow.steps),
                      key: const Key('steps-today'),
                      style: TextStyle(
                        color: p.text,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                        height: 1.05,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      todayRow == null
                          ? (target == null
                              ? 'No steps yet today'
                              : 'Goal ${formatSteps(target)}')
                          : (target == null
                              ? 'today'
                              : 'of ${formatSteps(target)} today'),
                      style: TextStyle(color: p.muted, fontSize: 14),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 132,
                height: 76,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < days.length; i++)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Container(
                              width: 10,
                              height:
                                  values[i] == 0
                                      ? 3
                                      : (50 * values[i] / top)
                                          .clamp(3, 50)
                                          .toDouble(),
                              decoration: BoxDecoration(
                                color:
                                    i == days.length - 1
                                        ? p.primary
                                        : (values[i] == 0
                                            ? p.tile
                                            : p.primary.withValues(
                                              alpha: 0.45,
                                            )),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dayInitial(days[i]),
                              style: TextStyle(color: p.faint, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The compact "Manual log" button. Opens a centred dialog, never a full page.
class ManualLogButton extends StatelessWidget {
  const ManualLogButton({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.card,
      borderRadius: BorderRadius.circular(AppTheme.cardRadius),
      child: InkWell(
        key: const Key('manual-steps'),
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        onTap:
            () => showDialog<void>(
              context: context,
              builder: (_) => const ManualStepsDialog(),
            ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit_outlined, size: 18, color: p.text),
              const SizedBox(width: 8),
              Text(
                'Manual log',
                style: TextStyle(
                  color: p.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centred dialog to type a day's step count. Saving again for the same day edits that day's record.
class ManualStepsDialog extends ConsumerStatefulWidget {
  const ManualStepsDialog({super.key});

  @override
  ConsumerState<ManualStepsDialog> createState() => _ManualStepsDialogState();
}

class _ManualStepsDialogState extends ConsumerState<ManualStepsDialog> {
  late DateTime _day = parseDateKey(_todayKey());
  String _text = '';

  Future<void> _pickDay() async {
    final today = parseDateKey(_todayKey());
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(today.year - 3),
      lastDate: today,
    );
    if (picked != null) setState(() => _day = dateOnly(picked));
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final n = int.tryParse(_text.trim().replaceAll(',', ''));
    if (n == null || n < 0) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Enter the number of steps.')),
      );
      return;
    }
    try {
      await ref
          .read(lifestyleServiceProvider)
          .setSteps(n, localDate: dateKey(_day));
    } on ArgumentError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('${e.message}')));
      return;
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Saved on this phone. It will sync when online.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final isToday = dateKey(_day) == _todayKey();
    final existing = ref.watch(stepsForProvider(dateKey(_day))).valueOrNull;
    return ModalCard(
      title: 'Log steps',
      subtitle: isToday ? 'Today' : longDay(_day),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          const FieldLabel('Steps'),
          FieldBox(
            // A fresh box per day so the field never shows another day's text.
            key: ValueKey(dateKey(_day)),
            hint: '0',
            keyboard: TextInputType.number,
            fieldKey: const Key('steps-field'),
            onChanged: (v) => _text = v,
          ),
          const SizedBox(height: 8),
          if (existing != null)
            MutedText(
              'Replaces ${formatSteps(existing.steps)} steps already saved for this day.',
              size: 13,
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              key: const Key('steps-change-day'),
              onTap: _pickDay,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Change day',
                  style: TextStyle(color: p.link, fontSize: 15),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AppButton.primary(
            'Save',
            key: const Key('steps-save'),
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
