import 'package:flutter/material.dart';

import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';

/// Strength, body measurements, muscle development and goals. Needs backend Stages 3 and 4.
class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffold(
      title: 'Progress',
      children: [
        EmptyView(
          icon: Icons.trending_up_outlined,
          title: 'Nothing to show yet',
          message: 'Strength, body measurements, muscle ratings and goals will appear here.',
        ),
      ],
    );
  }
}
