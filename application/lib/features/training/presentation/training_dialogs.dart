import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../../../core/widgets/editor_sheet.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import '../data/workout_session_service.dart';
import 'training_format.dart';
import 'workout_session_screen.dart';

/// A centred card with a title, an optional subtitle and a close button, used for the short "what do you want to do
/// with this day or workout" questions.
class ModalCard extends StatelessWidget {
  const ModalCard({super.key, required this.title, this.subtitle, required this.child});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Dialog(
      backgroundColor: p.card,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.cardRadius + 4), side: BorderSide(color: p.divider)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: TextStyle(color: p.text, fontSize: 26, fontWeight: FontWeight.w800, height: 1.15)),
                    if (subtitle != null) ...[const SizedBox(height: 2), Text(subtitle!, style: TextStyle(color: p.muted, fontSize: 17))],
                  ]),
                ),
              ),
              IconButton(key: const Key('dialog-close'), tooltip: 'Close', onPressed: () => Navigator.of(context).pop(), icon: Icon(Icons.close, color: p.muted)),
            ]),
            const SizedBox(height: 16),
            Padding(padding: const EdgeInsets.only(right: 8), child: child),
          ]),
        ),
      ),
    );
  }
}

/// A tinted box with a warning icon, a bold line and a sentence.
class WarningBox extends StatelessWidget {
  const WarningBox({super.key, required this.title, required this.text});
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: p.amber.withAlpha(36), borderRadius: BorderRadius.circular(AppTheme.radius), border: Border.all(color: p.amber.withAlpha(110))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.warning_amber_rounded, size: 20, color: p.amber),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(color: p.amber, fontSize: 17, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 6),
        Text(text, style: TextStyle(color: p.text, fontSize: 15, height: 1.35)),
      ]),
    );
  }
}

// ---- A finished workout ----

/// One finished workout. A workout with logged sets shows its totals and exercises. One without says it is not counted
/// and offers to resume, keep or discard it.
Future<void> showSessionDetail(BuildContext context, String sessionId) {
  return showDialog<void>(context: context, builder: (_) => _SessionDialog(sessionId: sessionId, screenContext: context));
}

/// Asks before throwing a workout away, then does it. Returns true when it was discarded.
Future<bool> confirmDiscardSession(BuildContext context, WidgetRef ref, String sessionId, {required bool counted}) async {
  final sure = await askChoice(
    context,
    title: 'Discard this workout?',
    body: counted ? 'Its sets are removed from your history and records. This cannot be undone.' : 'It has no sets, so nothing of yours is lost. This cannot be undone.',
    choices: const [('keep', 'Keep it', ButtonKind.tonal), ('discard', 'Discard', ButtonKind.danger)],
  );
  if (sure != 'discard') return false;
  await ref.read(workoutSessionServiceProvider).discardSession(sessionId);
  return true;
}

class _SessionDialog extends ConsumerWidget {
  const _SessionDialog({required this.sessionId, required this.screenContext});

  final String sessionId;

  /// The screen the dialog was opened from. It outlives the dialog, so it can open the workout after the dialog closes.
  final BuildContext screenContext;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final detail = ref.watch(sessionDetailProvider(sessionId)).valueOrNull;
    if (detail == null) {
      return const ModalCard(title: 'Workout', child: MutedText('This workout is not on this phone.'));
    }
    final names = {for (final e in ref.watch(exerciseLibraryProvider).valueOrNull ?? const <Exercise>[]) e.id: e.name};
    final session = detail.session;
    final counted = detail.summary.workingSets > 0;
    final finished = !session.isActive;

    Future<void> resume() async {
      final messenger = ScaffoldMessenger.of(screenContext);
      try {
        await ref.read(workoutSessionServiceProvider).reopenSession(sessionId);
      } on SessionAlreadyActive {
        messenger.showSnackBar(const SnackBar(content: Text('Another workout is in progress. Finish or discard it first.')));
        return;
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(saveErrorText(e))));
        return;
      }
      if (context.mounted) Navigator.of(context).pop();
      if (screenContext.mounted) await startOrContinueWorkout(screenContext, ref);
    }

    Future<void> discard() async {
      final messenger = ScaffoldMessenger.of(screenContext);
      try {
        final done = await confirmDiscardSession(context, ref, sessionId, counted: counted);
        if (done && context.mounted) Navigator.of(context).pop();
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(saveErrorText(e))));
      }
    }

    if (!counted) {
      return ModalCard(
        title: dateText(session.localDate),
        subtitle: 'Workout history',
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const WarningBox(title: 'No sets logged', text: 'Workouts with no logged sets are listed but not counted in your totals, streaks or records.'),
          const SizedBox(height: 16),
          Text(finished ? 'Resume this workout to add sets, or discard it to clean up your history.' : 'This workout is still in progress.', style: TextStyle(color: p.text, fontSize: 16, height: 1.35)),
          const SizedBox(height: 16),
          if (finished) ...[
            AppButton.primary('Resume workout', onPressed: resume),
            const SizedBox(height: 12),
            AppButton('Keep for now', onPressed: () => Navigator.of(context).pop()),
            const SizedBox(height: 16),
            Divider(color: p.divider, height: 1),
            const SizedBox(height: 16),
            AppButton('Discard workout', kind: ButtonKind.danger, onPressed: discard),
            const SizedBox(height: 8),
            Center(child: Text('Discarding can’t be undone.', style: TextStyle(color: p.muted, fontSize: 14))),
          ] else
            AppButton.primary('Continue workout', onPressed: () async {
              Navigator.of(context).pop();
              if (screenContext.mounted) await startOrContinueWorkout(screenContext, ref);
            }),
        ]),
      );
    }

    return ModalCard(
      title: session.name ?? 'Workout',
      subtitle: '${dateText(session.localDate)} · ${session.status == 'completed' ? 'Finished' : session.status}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: StatBlock(minutesText(detail.summary.durationSeconds).isEmpty ? '–' : minutesText(detail.summary.durationSeconds), 'Duration')),
          Expanded(child: StatBlock('${kgText(detail.summary.volumeKg)} kg', 'Volume')),
          Expanded(child: StatBlock('${detail.summary.workingSets}', 'Sets')),
        ]),
        const SizedBox(height: 14),
        if (detail.exercises.isNotEmpty)
          RowList([
            for (final e in detail.exercises)
              RowItem(
                title: names[e.exercise.exerciseId] ?? 'Exercise',
                subtitle: e.exercise.isSkipped
                    ? 'Skipped'
                    : (e.sets.isEmpty ? 'No sets' : [for (final s in e.sets) if (s.isWorking) '${s.weightKg == null ? '–' : kgText(s.weightKg!)}×${s.reps ?? '–'}'].join(' · ')),
              ),
          ]),
        if (session.postNotes != null && session.postNotes!.isNotEmpty) ...[const SizedBox(height: 12), MutedText(session.postNotes!)],
        if (finished) ...[
          const SizedBox(height: 16),
          AppButton('Discard workout', kind: ButtonKind.danger, onPressed: discard),
        ],
      ]),
    );
  }
}

// ---- A day on the schedule ----

/// Plans one date: a workout from a template, a day of the active split, a rest day, or nothing. [onOpenSplits] is
/// called when the person chooses "Activate a split" (the Training screen then shows its Splits tab).
Future<void> showScheduleDay(BuildContext context, String localDate, {VoidCallback? onOpenSplits}) {
  return showDialog<void>(context: context, builder: (_) => _ScheduleDayDialog(localDate: localDate, screenContext: context, onOpenSplits: onOpenSplits));
}

class _ScheduleDayDialog extends ConsumerWidget {
  const _ScheduleDayDialog({required this.localDate, required this.screenContext, this.onOpenSplits});

  final String localDate;
  final BuildContext screenContext;
  final VoidCallback? onOpenSplits;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final split = ref.watch(activeSplitProvider).valueOrNull;
    final plan = ref.watch(todayPlanProvider(localDate)).valueOrNull ?? const TodayPlan();
    final service = ref.read(trainingManagementServiceProvider);

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
        if (context.mounted) Navigator.of(context).pop();
      } catch (e) {
        if (screenContext.mounted) ScaffoldMessenger.of(screenContext).showSnackBar(SnackBar(content: Text(saveErrorText(e))));
      }
    }

    Future<void> pickTemplate() async {
      final templates = await ref.read(currentTemplatesProvider.future);
      if (templates.isEmpty) {
        ScaffoldMessenger.of(screenContext).showSnackBar(const SnackBar(content: Text('You have no templates yet. Create one in the Splits tab first.')));
        return;
      }
      final picked = await showDialog<TemplateVersion>(
        context: context,
        builder: (d) => ModalCard(
          title: 'Choose a template',
          subtitle: dateText(localDate),
          child: RowList([for (final t in templates) RowItem(title: t.name, subtitle: 'Version ${t.version}', chevron: true, onTap: () => Navigator.of(d).pop(t))]),
        ),
      );
      if (picked == null) return;
      await run(() => service.assignTemplate(localDate, picked));
    }

    final String subtitle;
    if (plan.isRest) {
      subtitle = 'Rest day';
    } else if (plan.hasPlan) {
      subtitle = 'Planned · ${plan.title ?? 'Workout'}${plan.entry!.status == 'planned' ? '' : ' (${plan.entry!.status})'}';
    } else {
      subtitle = 'Unplanned day';
    }

    return ModalCard(
      title: dateText(localDate),
      subtitle: subtitle,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: p.tile, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.calendar_today_outlined, size: 18, color: p.text),
            const SizedBox(width: 8),
            Text(split == null ? 'No split active' : 'Split: ${split.name}', style: TextStyle(color: p.text, fontSize: 16)),
          ]),
        ),
        const SizedBox(height: 14),
        Text(
          plan.hasPlan
              ? 'You can replace this day, or clear it.'
              : (split == null
                  ? 'Nothing is planned for this day. Activate a split to plan days automatically, or add a one-off session or a rest day.'
                  : 'Nothing is planned for this day. Plan it from your split, add a one-off session or a rest day.'),
          style: TextStyle(color: p.text, fontSize: 16, height: 1.4),
        ),
        const SizedBox(height: 16),
        AppButton.primary('+ Assign workout template', onPressed: pickTemplate),
        const SizedBox(height: 12),
        AppButton('Mark as rest day', onPressed: () => run(() => service.setScheduleDay(localDate, split: split, rest: true))),
        if (split != null) ...[
          const SizedBox(height: 16),
          const FieldLabel('Plan from your active split'),
          RowList([
            for (final d in split.days)
              RowItem(title: d.isRest ? 'Rest · ${d.label}' : d.label, subtitle: 'Day ${d.position}', onTap: () => run(() => service.setScheduleDay(localDate, split: split, day: d))),
          ]),
        ],
        if (plan.hasPlan) ...[
          const SizedBox(height: 12),
          AppButton('Clear this day', kind: ButtonKind.danger, onPressed: () => run(() => service.clearScheduleDay(localDate))),
        ],
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          if (split == null && onOpenSplits != null)
            LinkText('Activate a split →', onTap: () {
              Navigator.of(context).pop();
              onOpenSplits!();
            })
          else
            const SizedBox.shrink(),
          LinkText('Dismiss', color: p.muted, onTap: () => Navigator.of(context).pop()),
        ]),
      ]),
    );
  }
}
