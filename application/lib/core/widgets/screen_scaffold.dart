import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'sync_status_chip.dart';

/// Common page frame: app bar with the sync indicator and a scrolling, padded body.
class ScreenScaffold extends StatelessWidget {
  const ScreenScaffold({super.key, required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: const [SyncStatusChip()]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.pagePadding),
          children: [
            for (final child in children) ...[child, const SizedBox(height: AppTheme.gap)],
          ],
        ),
      ),
    );
  }
}
