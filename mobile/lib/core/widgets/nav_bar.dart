import 'package:flutter/material.dart';

import '../motion.dart';
import '../theme.dart';

/// One destination on the bar.
class NavItem {
  const NavItem({required this.icon, required this.selectedIcon, required this.label, this.badge = 0});

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// A count waiting behind this tab — unread messages, reports owed.
  final int badge;
}

/// The bar at the bottom of every product in this app.
///
/// Material's own `NavigationBar` was doing the job, but it moves in one way
/// only: the pill appears under the new tab and that is that. This one tells
/// the eye where it went — the pill slides across the bar, the icon it lands
/// on swaps to its filled twin with a small spring, and the label it leaves
/// behind fades back to its quiet weight. The thumb lands, the bar answers.
class AppNavBar extends StatelessWidget {
  const AppNavBar({super.key, required this.index, required this.onSelect, required this.items});

  final int index;
  final ValueChanged<int> onSelect;
  final List<NavItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.lineSoft)),
        boxShadow: [BoxShadow(color: Color(0x0F1B6A66), blurRadius: 18, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 66,
          child: Stack(
            children: [
              // The pill, sliding. It lives behind the row rather than inside
              // one item, which is the only way it can travel between them.
              AnimatedAlign(
                duration: Motion.medium,
                curve: Motion.enter,
                alignment: _slot(context),
                child: FractionallySizedBox(
                  widthFactor: 1 / items.length,
                  child: Center(
                    child: Container(
                      width: 56,
                      height: 32,
                      decoration: const BoxDecoration(color: AppColors.brandSoft, borderRadius: AppShape.chip),
                      margin: const EdgeInsets.only(bottom: 18),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (i, item) in items.indexed)
                    Expanded(
                      child: _NavTab(item: item, selected: i == index, onTap: () => onSelect(i)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Where the pill sits, in alignment terms, respecting the page direction —
  /// the first tab is on the right in Arabic.
  Alignment _slot(BuildContext context) {
    if (items.length < 2) return Alignment.center;
    final fraction = index / (items.length - 1);
    final x = -1 + fraction * 2;
    return Alignment(Directionality.of(context) == TextDirection.rtl ? -x : x, 0);
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({required this.item, required this.selected, required this.onTap});

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colour = selected ? AppColors.brand : AppColors.muted;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 40,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 32,
              child: Center(
                child: AnimatedScale(
                  scale: selected ? 1.12 : 1,
                  duration: Motion.medium,
                  curve: Motion.spring,
                  child: Badge(
                    isLabelVisible: item.badge > 0,
                    label: Text(
                      item.badge > 99 ? '99+' : '${item.badge}',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 10.5),
                    ),
                    backgroundColor: AppColors.bad,
                    offset: const Offset(-7, -3),
                    child: AnimatedSwitcher(
                      duration: Motion.fast,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(scale: animation, child: child),
                      ),
                      child: Icon(
                        selected ? item.selectedIcon : item.icon,
                        key: ValueKey(selected),
                        size: 23,
                        color: colour,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: Motion.medium,
              curve: Motion.enter,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 11.5,
                height: 1.2,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w500,
                color: colour,
              ),
              child: Text(item.label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// The body of a shell: keeps every tab alive, fades the one being shown in.
///
/// [IndexedStack] alone is a hard cut. The opacity below animates only the
/// tab that is actually painted, so a switch reads as a dissolve while a
/// half-scrolled list under another tab stays exactly where it was left.
class TabBody extends StatelessWidget {
  const TabBody({super.key, required this.index, required this.children});

  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: index,
      children: [
        for (final (i, child) in children.indexed)
          AnimatedOpacity(
            opacity: i == index ? 1 : 0,
            duration: Motion.medium,
            curve: Motion.enter,
            child: AnimatedScale(
              scale: i == index ? 1 : 0.99,
              duration: Motion.medium,
              curve: Motion.enter,
              child: child,
            ),
          ),
      ],
    );
  }
}
