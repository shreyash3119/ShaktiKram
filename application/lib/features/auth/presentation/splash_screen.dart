import 'package:flutter/material.dart';

/// The route used while the app reads what is stored on this device. The Android launch screen already covers that
/// moment (the first frame is held back in `main.dart` until it is over), so this draws nothing of its own: no logo,
/// text or spinner. It only exists so the sign-in state machine keeps its "checking" location.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.shrink());
}
