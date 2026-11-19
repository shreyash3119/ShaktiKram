import 'package:flutter/widgets.dart';

/// One row of sub-tabs on screen (the shared [UnderlineTabs]). It reports its selected tab and how to change it, so the
/// app shell can move between sub-tabs on a horizontal swipe and on the Back button.
class SubTabHandle {
  SubTabHandle();

  int index = 0;
  int count = 0;
  ValueChanged<int> onChanged = _ignore;

  /// False while the section is hidden behind another main tab (its widgets stay alive but are off screen).
  bool active = false;

  static void _ignore(int _) {}

  /// The section's first sub-tab, which Back returns to.
  static const defaultIndex = 0;
}

/// All sub-tab rows currently alive. Only the active one answers swipes and Back.
class SubTabRegistry {
  final List<SubTabHandle> _handles = [];

  void add(SubTabHandle h) => _handles.add(h);
  void remove(SubTabHandle h) => _handles.remove(h);

  /// The sub-tabs of the section being shown, or null when it has none (Home, Settings).
  SubTabHandle? get active {
    for (final h in _handles.reversed) {
      if (h.active && h.count > 1) return h;
    }
    return null;
  }

  /// Moves one sub-tab left (-1) or right (+1). Does nothing past the first or last tab.
  bool step(int direction) {
    final h = active;
    if (h == null) return false;
    final next = h.index + direction;
    if (next < 0 || next >= h.count) return true; // the swipe belongs to the sub-tabs even at their ends
    h.onChanged(next);
    return true;
  }

  /// Back from a sub-tab other than the first returns to the first. False when already there (or none).
  bool backToDefault() {
    final h = active;
    if (h == null || h.index == SubTabHandle.defaultIndex) return false;
    h.onChanged(SubTabHandle.defaultIndex);
    return true;
  }
}

/// Gives [UnderlineTabs] below it the shell's registry. Without one (tests, other screens) they simply do not register.
class SubTabScope extends InheritedWidget {
  const SubTabScope({super.key, required this.registry, required super.child});

  final SubTabRegistry registry;

  static SubTabRegistry? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<SubTabScope>()?.registry;

  @override
  bool updateShouldNotify(SubTabScope old) => registry != old.registry;
}
