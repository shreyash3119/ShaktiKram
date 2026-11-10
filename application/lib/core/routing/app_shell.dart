import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';

class _NavItem {
  const _NavItem(this.label, this.icon, this.selectedIcon);
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// Floating bottom bar with the six sections. The order must match the branch order in app_router.dart.
class AppBottomBar extends StatelessWidget {
  const AppBottomBar({super.key, required this.currentIndex, required this.onSelected});

  final int currentIndex;
  final ValueChanged<int> onSelected;

  static const _items = <_NavItem>[
    _NavItem('Home', Icons.home_outlined, Icons.home_rounded),
    _NavItem('Training', Icons.fitness_center, Icons.fitness_center),
    _NavItem('Progress', Icons.trending_up, Icons.trending_up),
    _NavItem('Lifestyle', Icons.favorite_border, Icons.favorite_rounded),
    _NavItem('Reports', Icons.bar_chart_rounded, Icons.bar_chart_rounded),
    _NavItem('Settings', Icons.tune, Icons.tune),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(34)),
        child: Row(children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(i),
                child: _NavButton(item: _items[i], selected: i == currentIndex),
              ),
            ),
        ]),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.item, required this.selected});
  final _NavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final color = selected ? p.link : p.muted;
    return Container(
      height: 62,
      decoration: BoxDecoration(
        color: selected ? p.tile : Colors.transparent,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(selected ? item.selectedIcon : item.icon, size: 22, color: color),
        SizedBox(
          height: 6,
          child: selected
              ? Center(child: Container(width: 4, height: 4, decoration: BoxDecoration(color: p.link, shape: BoxShape.circle)))
              : null,
        ),
        Text(
          item.label,
          maxLines: 1,
          style: TextStyle(color: color, fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500),
        ),
      ]),
    );
  }
}

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: AppBottomBar(
        currentIndex: navigationShell.currentIndex,
        // Tapping the current tab returns to that section's first screen.
        onSelected: (index) => navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex),
      ),
    );
  }
}
