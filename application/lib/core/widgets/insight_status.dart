import 'package:flutter/material.dart';

import '../insights/insight_repository.dart';
import '../theme/app_theme.dart';
import 'controls.dart';

/// "Updated 5 min ago" style age for a cached answer.
String ageText(DateTime? since, {DateTime? now}) {
  if (since == null) return 'never';
  final d = (now ?? DateTime.now()).difference(since);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// One line under a card that shows server-calculated values: where they come from, how old they are, and what to do
/// when they could not be updated. The values themselves stay on screen whenever an older answer exists.
class InsightStatusLine extends StatelessWidget {
  const InsightStatusLine({super.key, required this.snapshot, this.onRefresh, this.now});

  final InsightSnapshot snapshot;
  final VoidCallback? onRefresh;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final String text;
    var warn = false;
    if (snapshot.refreshing) {
      text = 'Updating from the server…';
    } else if (!snapshot.hasData) {
      text = snapshot.isOffline ? 'Not loaded yet. Connect to the internet to load this.' : (snapshot.error != null ? 'Could not load this yet.' : 'Not loaded yet.');
      warn = snapshot.error != null;
    } else if (snapshot.error != null) {
      text = snapshot.isOffline
          ? 'Offline. Showing the answer from ${ageText(snapshot.fetchedAt, now: now)}.'
          : 'Could not update. Showing the answer from ${ageText(snapshot.fetchedAt, now: now)}.';
      warn = true;
    } else if (snapshot.freshness == InsightFreshness.stale) {
      text = 'Calculated by the server ${ageText(snapshot.fetchedAt, now: now)}. May be out of date.';
    } else {
      text = 'Calculated by the server ${ageText(snapshot.fetchedAt, now: now)}.';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(children: [
        Expanded(child: Text(text, key: const Key('insight-status'), style: TextStyle(color: warn ? p.amber : p.muted, fontSize: 13))),
        if (onRefresh != null && !snapshot.refreshing) LinkText('Refresh', onTap: onRefresh!),
      ]),
    );
  }
}
