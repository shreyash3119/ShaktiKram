import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// A bare app shown instead of the real one when the build is misconfigured or start-up fails.
class StartupProblemApp extends StatelessWidget {
  const StartupProblemApp({super.key, required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppTheme.pagePadding * 1.5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) => Text(title, style: Theme.of(context).textTheme.titleLarge),
                ),
                const SizedBox(height: 12),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
