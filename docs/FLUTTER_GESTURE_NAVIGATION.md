# Swipe navigation and Android Back

## How navigation worked before
go_router `StatefulShellRoute.indexedStack` with six branches (Home, Training, Progress, Lifestyle, Reports, Settings) inside `AppShell`, which draws `AppBottomBar`. Every branch stays alive, so a section already keeps its sub-tab, scroll position and loaded data when you leave and return. Sub-tabs are local state in Training, Progress, Lifestyle and Reports, drawn by the shared `UnderlineTabs`. Pages such as Settings → Account, Steps history and the workout screen are pushed routes; the workout screen already confirms before leaving (`PopScope`). There was no swipe and no Back handling for tabs.

## What changed (UI untouched)
- `core/widgets/sub_tab_registry.dart` (new): `SubTabRegistry`, a handle per row of sub-tabs, and `SubTabScope`.
- `core/widgets/section_widgets.dart`: `UnderlineTabs` registers itself (index, count, onChanged, whether its section is the visible one). Nothing it draws changed, and it does nothing outside the shell.
- `core/routing/app_shell.dart`: `AppShell` is now stateful and adds one horizontal-drag recognizer and one `BackButtonListener`. The bottom bar and its tap behaviour are unchanged.

## Sliding transition (follows the finger)
- `core/widgets/slide_driver.dart` (new): a continuous page position (like a `PageController`, without a `PageView`). Page `i` is drawn at `(i - pos) * width`, so the current page slides out while the next slides in beside it, with no fading, rotation or overlap. On release it settles on the nearest page: a drag past 35% of the width, or a quick flick of at least 40 px, goes to the next page; otherwise it slides back.
- Sub-tabs: `core/widgets/tab_slider.dart` (new) holds the content under the tab row (`TabSlider`). Only that content slides; the tab row stays put and changes when the swipe settles. In Training, Progress, Lifestyle and Reports, `..._content()` became `TabSlider(builder: (i) => TabSlider.page(_content(i)))`; the page spacing is the same as before. Tapping a tab (or Back) still switches at once.
- Main tabs: the router now uses `StatefulShellRoute(navigatorContainerBuilder: ...)` with `core/routing/branch_pager.dart` instead of `StatefulShellRoute.indexedStack`. It keeps every section alive exactly as the indexed stack did (hidden ones are off stage with tickers paused) and draws the current section and its neighbour side by side while a swipe is under way.
- `UnderlineTabs` is unchanged again; the sliders register with the shell instead.

## Swipes
One recognizer in the shell decides, so a swipe can never do both: if the visible section has sub-tabs it moves one sub-tab (and stops at the first/last); otherwise (Home, Settings) it moves one main tab (and stops at the ends). Needs 80 px, or 40 px with a fast fling, so taps and small movements are ignored. Horizontally scrolling children (such as the tab strip) and vertical lists win the gesture when the touch starts on them. Bottom bar and sub-tab selection follow because they are driven by the same state.

## Back
Order: dialog/sheet/pushed page/workout screen on top → normal Back (they close first; the workout screen still asks before leaving). Otherwise sub-tab other than the first → first sub-tab; another main tab → Home (no message); on Home the first press shows "Press back again to exit." and a second within 2 s exits.
`BackButtonListener` (the Router's own Back mechanism) is used instead of `PopScope` because the sections live in go_router's nested navigators and a `PopScope` there is not guaranteed to be asked. Dialogs and sheets use the root navigator, so they are seen as "something on top".

## Limits of the sliding effect
- A main section that has never been opened has no content yet, so it is blank while the first swipe towards it is under way (it appears once the swipe settles). Sections already visited slide in fully.
- Tapping a bottom-bar item or a tab switches instantly; only swipes slide.
- The bottom bar and the tab row change when the swipe settles (about a quarter of a second after release), not while dragging.
- While a swipe is in progress, a sub-tab page taller than the current one is cut off below the current page's height.

## Not done / not verified
- Not compiled or run (no Flutter SDK); tests are in `test/gesture_navigation_test.dart`. Please check on a device: gesture conflicts with charts, and Back with a bottom sheet.
- A workout in progress is stored on the phone; Back on Home with one running only shows the exit message and never discards it.
- Sub-tabs inside screens that are not one of the four section roots (for example PillTabs) are not swipe targets.
