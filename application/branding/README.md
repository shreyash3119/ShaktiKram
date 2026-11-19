# Launch screen picture (`splash_img`)

Place **one** file here, named exactly:

    application/branding/splash_img.png

Preferred format: **PNG** with a transparent background (RGBA), portrait, about **1080 x 1920 px** (any tall shape works;
about 1920 px high). Not SVG: this is a 3D render, and the Android launch screen is built from bitmaps. This folder is
not bundled into the app, so the file adds no size to it beyond the generated launch drawables.

Then, from `application/`:

```
pip install pillow
python tools/prepare_splash.py      # makes branding/splash_img_android12.png from it
flutter pub get
dart run flutter_native_splash:create
```

What you get:
- **Android 11 and older:** the picture centred at its own aspect ratio, about 480 dp tall for a 1920 px picture (about half to
  two thirds of the screen height; a narrower picture, e.g. 960 px wide, leaves more side margin), on the app's navy background. Nothing is stretched or cropped.
- **Android 12 and newer:** the system draws only an icon, inside a circle, and cannot show a full-height picture. The
  helper script therefore scales the same picture down to sit fully inside that circle, uncropped.

The app logo and launcher icon (`assets/branding/`, `flutter_launcher_icons`) are not touched by any of this. Until the
file exists the old launch screen keeps working: nothing here changes the generated resources by itself.
