# Swipe navigation and Android Back

## How navigation worked before
go_router `StatefulShellRoute.indexedStack` with six branches (Home, Training, Progress, Lifestyle, Reports, Settings) inside `AppShell`, which draws `AppBottomBar`. Every branch stays alive, so a section already keeps its sub-tab, scroll position and loaded data when you leave and return. Sub-tabs are local state in Training, Progress, Lifestyle and Reports, drawn by the shared `UnderlineTabs`. Pages such as Settings → Account, Steps history and the workout screen are pushed routes; the workout screen already confirms before leaving (`PopScope`). There was no swipe and no Back handling for tabs.

## What changed (UI untouched)
- `core/widgets/sub_tab_registry.dart` (new): `SubTabRegistry`, a handle per row of sub-tabs, and `SubTabScope`.
- `core/widgets/section_widgets.dart`: `UnderlineTabs` registers itself (index, count, onChanged, whether its section is the visible one). Nothing it draws changed, and it does nothing outside the shell.
- `core/routing/app_shell.dart`: `AppShell` is now stateful and adds one horizontal-drag recognizer and one `BackButtonListener`. The bottom bar and its tap behaviour are unchanged.

## Swipes
One recognizer in the shell decides, so a swipe can never do both: if the visible section has sub-tabs it moves one sub-tab (and stops at the first/last); otherwise (Home, Settings) it moves one main tab (and stops at the ends). Needs 80 px, or 40 px with a fast fling, so taps and small movements are ignored. Horizontally scrolling children (such as the tab strip) and vertical lists win the gesture when the touch starts on them. Bottom bar and sub-tab selection follow because they are driven by the same state.

## Back
Order: dialog/sheet/pushed page/workout screen on top → normal Back (they close first; the workout screen still asks before leaving). Otherwise sub-tab other than the first → first sub-tab; another main tab → Home (no message); on Home the first press shows "Press back again to exit." and a second within 2 s exits.
`BackButtonListener` (the Router's own Back mechanism) is used instead of `PopScope` because the sections live in go_router's nested navigators and a `PopScope` there is not guaranteed to be asked. Dialogs and sheets use the root navigator, so they are seen as "something on top".

## Not done / not verified
- Not compiled or run (no Flutter SDK); tests are in `test/gesture_navigation_test.dart`. Please check on a device: gesture conflicts with charts, and Back with a bottom sheet.
- No swipe animation: sections switch instantly (an indexed stack, not a `PageView`), which keeps all state without a second navigation structure.
- A workout in progress is stored on the phone; Back on Home with one running only shows the exit message and never discards it.
- Sub-tabs inside screens that are not one of the four section roots (for example PillTabs) are not swipe targets.
