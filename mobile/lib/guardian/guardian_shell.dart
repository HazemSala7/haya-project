import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  @override
  Widget build(BuildContext context) {
    /*
     * Three tabs, not four.
     *
     * There was an «الأطفال» tab opening `ChildDetailScreen(studentId: 0)` —
     * a placeholder id that belongs to no child, so it could only ever show an
     * error. And it had nothing to show that the home screen does not: the
     * children are the home screen, each as a card that opens its own file.
     */
    final screens = [
      const GuardianHomeScreen(),
      const MessagesScreen(),
      const AccountScreen(),
    ];

    // The home tab carries its own greeting; the rest want a title.
    const titles = [null, 'الرسائل', 'الحساب'];

    return Scaffold(
      appBar: titles[_index] == null
          ? null
          : AppBar(title: Text(titles[_index]!), elevation: 0),
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.mail_outline), selectedIcon: Icon(Icons.mail_rounded), label: 'الرسائل'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person_rounded), label: 'الحساب'),
        ],
      ),
    );
  }
}
