# Exercise details fixes, app logo and new bottom navbar

Not compiled or run here (no Flutter SDK); run `flutter analyze` and `flutter test`.

## Exercise details
- The Edit button sat in a 72 px slot, narrower than the button, so its label wrapped ("Edi / t"). The side slots are now 92 px, the button has a 0 minimum width and 20 px side padding, and the label is one line.
- Long muscle names overflowed the muscle chips. `MuscleChip` now lets its label wrap inside the available width.

## App logo
Put `shaktikram_logo.png` and `shaktikram_logo.svg` in `application/assets/branding/` (see the README there).
- `pubspec.yaml`: the asset folder, plus `flutter_launcher_icons` and `flutter_native_splash` settings pointing at the PNG.
- `AppLogo` (`lib/core/widgets/app_logo.dart`) shows it on the sign-in screen; a dumbbell mark shows until the file exists.
- Android app name is now "ShaktiKram".
- After adding the PNG: `flutter pub get`, `dart run flutter_launcher_icons`, `dart run flutter_native_splash:create`.
- The SVG is only the editable master; the app does not load it (no `flutter_svg` dependency added).

## Bottom navbar
`AppBottomBar` is now a dark capsule. The selected section expands into a tinted, outlined pill with its icon and name; the other five are muted icons.
Colours: Home blue, Training purple, Progress green, Lifestyle pink/red, Reports amber, Settings cyan. The pill animates its width.
Icons: house, dumbbell, line chart, heart with pulse, horizontal bars, sliders.
Inactive tabs have no text, so tests tap them by key (`nav-<label>`); screen readers still get each name.
