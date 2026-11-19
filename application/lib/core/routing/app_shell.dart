import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../widgets/sub_tab_registry.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.accent);
  final String label;
  final IconData icon;

  /// The colour of the selected pill: icon, label, tinted fill and border.
  final Color accent;
}

/// Floating pill-shaped bottom bar with the six sections. The selected section grows into a coloured pill that shows
/// its icon and name; the others stay as muted icons. The order must match the branch order in app_router.dart.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const _items = <_NavItem>[
    _NavItem('Home', Icons.home_rounded, Color(0xFF4C8DFF)),
    _NavItem('Training', Icons.fitness_center, Color(0xFFB57BFF)),
    _NavItem('Progress', Icons.show_chart_rounded, Color(0xFF34D399)),
    _NavItem('Lifestyle', Icons.monitor_heart_rounded, Color(0xFFFF6B81)),
    _NavItem('Reports', Icons.align_horizontal_left_rounded, Color(0xFFFBBF24)),
    _NavItem('Settings', Icons.tune_rounded, Color(0xFF22D3EE)),
  ];

  static const _inactiveWidth = 44.0;
  static const _pillHeight = 54.0;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF0F1420) : p.card,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: p.divider.withValues(alpha: 0.5)),
        ),
        child: LayoutBuilder(
          builder: (context, c) {
            // The selected pill takes whatever the five compact icons leave.
            final activeWidth = c.maxWidth - _inactiveWidth * (_items.length - 1);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (var i = 0; i < _items.length; i++)
                  _NavButton(
                    item: _items[i],
                    selected: i == currentIndex,
                    width: i == currentIndex ? activeWidth : _inactiveWidth,
                    onTap: () => onSelected(i),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.width,
    required this.onTap,
  });

  final _NavItem item;
  final bool selected;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = selected ? item.accent : p.muted;
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: GestureDetector(
        key: Key('nav-${item.label}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          width: width,
          height: AppBottomBar._pillHeight,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: selected ? item.accent.withValues(alpha: 0.18) : null,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: selected
                  ? item.accent.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 24, color: color),
                  if (selected) ...[
                    const SizedBox(width: 6),
                    Text(
                      item.label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(
                        color: color,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The six sections around the bottom bar. It also owns two gestures:
///
/// * a horizontal swipe moves between the sub-tabs of the section being shown, or, when the section has none (Home,
///   Settings), between the main sections. One recognizer decides, so a swipe never does both;
/// * the Android Back button: sub-tab other than the first -> first sub-tab; another main section -> Home; on Home a
///   second press within two seconds leaves the app. A dialog, a bottom sheet, a pushed page or the workout screen
///   on top keeps the normal Back behaviour (they close first; the workout screen asks before leaving).
///
/// Every section stays alive in the indexed stack, so its sub-tab, scroll position and screen state survive switching.
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const _exitWindow = Duration(seconds: 2);
  static const _swipeDistance = 80.0;
  static const _flingDistance = 40.0;
  static const _flingSpeed = 800.0;

  final SubTabRegistry _subTabs = SubTabRegistry();
  double _drag = 0;
  DateTime? _lastBack;

  StatefulNavigationShell get _shell => widget.navigationShell;

  void _onSwipeEnd(DragEndDetails d) {
    final dx = _drag;
    _drag = 0;
    final v = d.primaryVelocity ?? 0;
    final far = dx.abs() >= _swipeDistance;
    final fast = v.abs() >= _flingSpeed && dx.abs() >= _flingDistance;
    if (!far && !fast) return; // a small finger movement
    final direction = dx < 0 ? 1 : -1; // swipe left -> next
    if (_subTabs.step(direction)) return; // the section has sub-tabs: they own the swipe
    final next = _shell.currentIndex + direction;
    if (next < 0 || next >= AppBottomBar._items.length) return;
    _shell.goBranch(next);
  }

  Future<bool> _onBack() async {
    // Something is above the sections (dialog, sheet, workout screen) or a page is pushed inside one: normal Back.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return false;
    if (GoRouter.of(context).canPop()) return false;

    if (_subTabs.backToDefault()) return true;
    if (_shell.currentIndex != 0) {
      _lastBack = null;
      _shell.goBranch(0);
      return true;
    }
    final now = DateTime.now();
    final last = _lastBack;
    if (last != null && now.difference(last) <= _exitWindow) {
      return false; // second press in time: let the app exit
    }
    _lastBack = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit.'),
          duration: _exitWindow,
        ),
      );
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return SubTabScope(
      registry: _subTabs,
      child: BackButtonListener(
        onBackButtonPressed: _onBack,
        child: Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => _drag = 0,
            onHorizontalDragUpdate: (d) => _drag += d.delta.dx,
            onHorizontalDragCancel: () => _drag = 0,
            onHorizontalDragEnd: _onSwipeEnd,
            child: _shell,
          ),
          bottomNavigationBar: AppBottomBar(
            currentIndex: _shell.currentIndex,
            // Tapping the current tab returns to that section's first screen.
            onSelected:
                (index) => _shell.goBranch(
                  index,
                  initialLocation: index == _shell.currentIndex,
                ),
          ),
        ),
      ),
    );
  }
}
