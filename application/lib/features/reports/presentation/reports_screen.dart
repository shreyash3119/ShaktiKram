import 'package:flutter/material.dart';

import '../../../core/widgets/screen_scaffold.dart';
import '../../../core/widgets/state_views.dart';

/// Reports, Excel and PDF exports, historical analysis. Needs backend Stage 5.
class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenScaffold(
      title: 'Reports',
      children: [
        EmptyView(
          icon: Icons.assessment_outlined,
          title: 'Reports are not available yet',
          message: 'Monthly and yearly reports with Excel and PDF export arrive with backend Stage 5.',
        ),
      ],
    );
  }
}
