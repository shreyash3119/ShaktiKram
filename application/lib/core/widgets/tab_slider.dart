import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import 'slide_driver.dart';
import 'sub_tab_registry.dart';

/// The content under a row of sub-tabs. Only this part slides: the tab row above it stays where it is. While a swipe is
/// in progress the current tab and the next one sit side by side and move with the finger; on release the nearest tab
/// settles into place and [onChanged] is called with it. Taps on the tab row (and Back) switch at once, as before.
///
/// [builder] must only create widgets for tab `i` (no `ref.watch`): it is also asked for the neighbouring tab.
class TabSlider extends StatefulWidget {
  const TabSlider({
    super.key,
    required this.index,
    required this.count,
    required this.onChanged,
    required this.builder,
  });

  final int index;
  final int count;
  final ValueChanged<int> onChanged;
  final Widget Function(int index) builder;

  /// Lays [children] out as a screen does, one under another with the usual gap, full width.
  static Widget page(List<Widget> children) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < children.length; i++) ...[
        if (i > 0) const SizedBox(height: AppTheme.gap),
        children[i],
      ],
    ],
  );

  @override
  State<TabSlider> createState() => _TabSliderState();
}

class _TabSliderState extends State<TabSlider>
    with SingleTickerProviderStateMixin {
  late final SlideDriver _driver;
  final SubTabHandle _handle = SubTabHandle();
  SubTabRegistry? _registry;
  final Map<int, Widget> _pages = {};
  double _width = 0;

  @override
  void initState() {
    super.initState();
    _driver = SlideDriver(
      vsync: this,
      initial: widget.index,
      count: widget.count,
      onSettled: (i) => widget.onChanged(i),
    );
    _handle
      ..dragStart = _driver.dragStart
      ..dragUpdate = ((dx) => _driver.dragUpdate(dx, _width))
      ..dragEnd = ((v) => _driver.dragEnd(v, _width));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = SubTabScope.maybeOf(context);
    if (!identical(registry, _registry)) {
      _registry?.remove(_handle);
      _registry = registry?..add(_handle);
    }
  }

  @override
  void didUpdateWidget(TabSlider old) {
    super.didUpdateWidget(old);
    _driver.count = widget.count;
    // A tab chosen some other way (tapping the tab row, Back) shows at once.
    if (widget.index != _driver.base && !_driver.animating) {
      _driver.jumpTo(widget.index);
    }
  }

  @override
  void dispose() {
    _registry?.remove(_handle);
    _driver.dispose();
    super.dispose();
  }

  Widget _page(int i) => _pages.putIfAbsent(i, () => widget.builder(i));

  @override
  Widget build(BuildContext context) {
    _handle
      ..index = widget.index
      ..count = widget.count
      ..onChanged = widget.onChanged
      ..active = TickerMode.of(context);
    // Fresh widgets for the tabs whenever the screen rebuilds; reused while only the position changes.
    _pages.clear();
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        _width = w + SlideDriver.gap;
        // Rebuilt only when the pair of pages changes. Moving the pages is paint-only (a layer offset), so a swipe
        // does not re-layout or repaint the tab content frame after frame.
        return ListenableBuilder(
          listenable: _driver.layout,
          builder: (context, _) {
            final base = _driver.layout.base;
            final other = _driver.layout.other;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                _Slide(driver: _driver, index: base, extent: _width, child: _page(base)),
                if (other != null)
                  Positioned(
                    key: const ValueKey('tab-slider-neighbor'),
                    left: 0,
                    top: 0,
                    width: w,
                    child: _Slide(driver: _driver, index: other, extent: _width, child: _page(other)),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Draws page [index] at `(index - pos) * extent`. Listens to the driver itself, so only this transform updates.
class _Slide extends StatelessWidget {
  const _Slide({required this.driver, required this.index, required this.extent, required this.child});

  final SlideDriver driver;
  final int index;
  final double extent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: driver,
      child: RepaintBoundary(child: child),
      builder: (context, child) => Transform.translate(
        offset: Offset((index - driver.pos) * extent, 0),
        child: child,
      ),
    );
  }
}
