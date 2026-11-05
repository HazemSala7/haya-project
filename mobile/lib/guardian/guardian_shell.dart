import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data.dart';
import '../core/models/json.dart';
import '../core/widgets/nav_bar.dart';
import 'home_screen.dart';
import 'messages_screen.dart';
import 'account_screen.dart';

class GuardianShell extends ConsumerStatefulWidget {
  const GuardianShell({super.key});

  @override
  ConsumerState<GuardianShell> createState() => _GuardianShellState();
}

class _GuardianShellState extends ConsumerState<GuardianShell> {
  var _index = 0;

  /*
   * Three tabs, not four.
   *
   * There was an «الأطفال» tab opening `ChildDetailScreen(studentId: 0)` —
   * a placeholder id that belongs to no child, so it could only ever show an
   * error. And it had nothing to show that the home screen does not: the
   * children are the home screen, each as a card that opens its own file.
   */
  final _screens = const [
    GuardianHomeScreen(),
    MessagesScreen(),
    AccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    // The home tab carries its own greeting; the rest want a title.
    const titles = [null, 'الرسائل', 'الحساب'];

    // Unread from the academy, on the tab that holds them — the one figure a
    // parent opens this app for, kept visible from wherever they are.
    final unread = ref.watch(dashboardProvider).maybeWhen(
          data: (data) => J.int0(data['unread_messages']),
          orElse: () => 0,
        );

    return Scaffold(
      appBar: titles[_index] == null ? null : AppBar(title: Text(titles[_index]!)),
      body: TabBody(index: _index, children: _screens),
      bottomNavigationBar: AppNavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
        items: [
          const NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'الرئيسية'),
          NavItem(
            icon: Icons.mail_outline,
            selectedIcon: Icons.mail_rounded,
            label: 'الرسائل',
            badge: unread,
          ),
          const NavItem(icon: Icons.person_outline, selectedIcon: Icons.person_rounded, label: 'الحساب'),
        ],
      ),
    );
  }
}
