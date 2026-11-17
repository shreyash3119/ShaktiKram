# ShaktiKram logo

Put the two logo files in this folder with exactly these names:

| File | Used for |
|---|---|
| `shaktikram_logo.png` | The app icon, the launch screen and the logo inside the app (sign-in screen) |
| `shaktikram_logo.svg` | The master copy for later edits. The app does not load it, so nothing needs the SVG at build time |

PNG requirements:
- Square, 1024 x 1024 px, transparent background.
- Keep the artwork inside the centre 66% (about 680 px) so Android's round or squircle icon mask never cuts it off.
- Light artwork works best, because the icon and launch screen background is the app's dark navy (`#0B111D`).

After adding the PNG, from the `application/` folder:

```
flutter pub get
dart run flutter_launcher_icons
dart run flutter_native_splash:create
```

The first command writes the launcher icons into `android/app/src/main/res/mipmap-*`, including the adaptive icon. The second
writes the launch screen. Until `shaktikram_logo.png` exists the app still builds and shows a plain dumbbell mark instead
of the logo; the two generator commands need the file.
