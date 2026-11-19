import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../widgets/slide_driver.dart';

/// Gives the sections' pager the shell's [SlideDriver].
class MainSlideScope extends InheritedWidget {
  const MainSlideScope({super.key, required this.driver, required super.child});

  final SlideDriver driver;

  static SlideDriver of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MainSlideScope>()!.driver;

  @override
  bool updateShouldNotify(MainSlideScope old) => driver != old.driver;
}

/// Lays the six sections out side by side. Only the current one is shown, as in an indexed stack, until a swipe starts:
/// then the current section and its neighbour are both drawn, moving with the finger. Every section stays alive, so its
/// sub-tab, scroll position and screen state are kept exactly as before. (A section that has never been opened has no
/// content yet; it appears blank while the first swipe towards it is under way.)
class BranchPager extends StatelessWidget {
  const BranchPager({super.key, required this.shell, required this.children});

  final StatefulNavigationShell shell;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final driver = MainSlideScope.of(context);
    driver.count = children.length;
    return AnimatedBuilder(
      animation: driver,
      builder: (context, _) {
        final pos = driver.pos;
        return LayoutBuilder(
          builder: (context, c) {
            return Stack(
              fit: StackFit.expand,
              children: [
                for (var i = 0; i < children.length; i++)
                  Offstage(
                    key: ValueKey('branch-$i'),
                    offstage: (i - pos).abs() >= 1,
                    child: TickerMode(
                      enabled: i == shell.currentIndex,
                      child: Transform.translate(
                        offset: Offset((i - pos) * c.maxWidth, 0),
                        child: children[i],
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
