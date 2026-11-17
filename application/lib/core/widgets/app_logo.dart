import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Where the logo lives. Add `shaktikram_logo.png` (and the `.svg` master) to this folder.
const appLogoAsset = 'assets/branding/shaktikram_logo.png';

/// The ShaktiKram logo. Shows a plain dumbbell mark until the PNG has been added to `assets/branding/`.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 88});

  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Image.asset(
      appLogoAsset,
      key: const Key('app-logo'),
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'ShaktiKram logo',
      errorBuilder:
          (_, _, _) => SizedBox(
            width: size,
            height: size,
            child: Icon(Icons.fitness_center, size: size * 0.6, color: p.link),
          ),
    );
  }
}
