import 'package:flutter/material.dart';

import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';

/// Splits, exercises, templates and workout history. First vertical slice (build step 4).
class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffold(
      title: 'Training',
      children: [
        EmptyView(
          icon: Icons.fitness_center_outlined,
          title: 'No training data yet',
          message: 'Exercises, templates, splits and workout history will appear here.',
        ),
      ],
    );
  }
}
