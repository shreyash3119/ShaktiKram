import 'package:flutter/material.dart';

import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';

/// Recovery, sleep, supplements, meals and activity. Needs backend Stage 3.
class LifestyleScreen extends StatelessWidget {
  const LifestyleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffold(
      title: 'Lifestyle',
      children: [
        EmptyView(
          icon: Icons.self_improvement_outlined,
          title: 'Nothing to show yet',
          message: 'Recovery, sleep, supplements, meals and activity will appear here.',
        ),
      ],
    );
  }
}
