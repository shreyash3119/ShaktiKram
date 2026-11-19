# Launch picture (`splash_img`)

The picture lives at:

    application/branding/splash_img.png

Preferred format: **PNG** with a transparent background, portrait (about 1080 x 1920 px or larger). Not SVG.

How it is shown: the app draws it **full-screen** (as large as the screen allows, with a small side margin, never
stretched or cropped) on the navy background while it starts. It is listed under `assets:` in `pubspec.yaml`, so run
`flutter pub get` after replacing it. It is on screen only for as long as start-up really takes, no longer.

The Android system launch screen (the instant before the app draws) is only the plain navy colour. Android 12 and newer
can only show a small icon there, never a large picture, so a big model cannot be shown natively. Nothing here changes
the app logo or the launcher icon.

`tools/prepare_splash.py` and `branding/splash_img_android12.png` are no longer used and can be deleted.
