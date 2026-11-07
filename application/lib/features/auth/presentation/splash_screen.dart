import 'package:flutter/material.dart';

import '../../../core/widgets/state_views.dart';

/// Shown for a moment while the app reads what is stored on this device.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: LoadingView(message: 'Starting…'));
  }
}
