import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/cards.dart';
import '../../../core/widgets/controls.dart';
import '../data/training_models.dart';
import '../data/training_providers.dart';
import 'training_format.dart';
import 'training_management_screens.dart';
import 'workout_widgets.dart';

/// The date of the latest finished workout that used any version of [templateId], or null.
final templateLastUsedProvider = FutureProvider.family<String?, String>((
  ref,
  templateId,
) async {
  final sessions = await ref.watch(finishedSessionsProvider.future);
  final repo = ref.watch(trainingRepositoryProvider);
  for (final s in sessions) {
    final versionId = s.session.templateVersionId;
    if (versionId == null) continue;
    final v = await repo.templateVersion(versionId);
    if (v?.templateId == templateId) return s.session.localDate;
  }
  return null;
});

/// Opens the templates list. Returns the template version the person chose with "Use", or null.
Future<TemplateVersion?> pickTemplate(BuildContext context) =>
    Navigator.of(context).push<TemplateVersion>(
      MaterialPageRoute(builder: (_) => const WorkoutTemplatesScreen()),
    );

/// Saved templates; "Use" loads one into the workout being put together.
class WorkoutTemplatesScreen extends ConsumerWidget {
  const WorkoutTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates =
        ref.watch(currentTemplatesProvider).valueOrNull ??
        const <TemplateVersion>[];
    return WorkoutPageScaffold(
      header: WorkoutPageHeader(
        title: 'Templates',
        subtitle: 'Choose one to load its exercises',
        onBack: () => Navigator.of(context).pop(),
      ),
      bottom: AppButton(
        '+ New template',
        key: const Key('new-template'),
        height: 56,
        onPressed: () => showTemplateEditor(context),
      ),
      children: [
        AppCard(
          child:
              templates.isEmpty
                  ? const MutedText(
                    'No templates yet. Create one below, or build a workout and use Save template.',
                  )
                  : RowList([
                    for (final t in templates) _TemplateRow(t, key: Key('template-${t.id}')),
                  ]),
        ),
      ],
    );
  }
}

class _TemplateRow extends ConsumerWidget {
  const _TemplateRow(this.template, {super.key});

  final TemplateVersion template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.pal;
    final count =
        ref.watch(templateExercisesProvider(template.id)).valueOrNull?.length;
    final used = ref.watch(templateLastUsedProvider(template.templateId)).valueOrNull;
    final usedText =
        used == null ? null : 'used ${_short(used)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  template.name,
                  style: TextStyle(
                    color: p.text,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    'v${template.version}',
                    if (count != null) '$count ${count == 1 ? 'exercise' : 'exercises'}',
                    if (usedText != null) usedText,
                  ].join(' · '),
                  style: TextStyle(color: p.muted, fontSize: 15),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          RowButton(
            'Use',
            key: Key('use-template-${template.id}'),
            onPressed: () => Navigator.of(context).pop(template),
          ),
        ],
      ),
    );
  }

  /// `2026-11-04` becomes `Nov 4`.
  static String _short(String localDate) {
    final d = DateTime.tryParse(localDate);
    return d == null ? localDate : '${monthNames[d.month - 1]} ${d.day}';
  }
}
