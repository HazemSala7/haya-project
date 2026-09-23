import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'home_screen.dart';
import 'students_screen.dart';
import 'sessions_screen.dart';
import 'account_screen.dart';

class SpecialistShell extends ConsumerStatefulWidget {
  const SpecialistShell({super.key});

  @override
  ConsumerState<SpecialistShell> createState() => _SpecialistShellState();
}

class _SpecialistShellState extends ConsumerState<SpecialistShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {

    final screens = [
      const SpecialistHomeScreen(),
      const StudentsScreen(),
      const SessionsScreen(),
      const SpecialistAccountScreen(),
    ];

    /*
     * No bar over the home tab.
     *
     * Its hero already carries her name, her title and the date, and a bar
     * above it repeated the first two in smaller type — two greetings stacked,
     * and thirty fewer pixels for the day itself. The other tabs still want a
     * title, so they keep one.
     */
    const titles = [null, 'الطلاب', 'الجلسات', 'الحساب'];

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
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people_rounded), label: 'الطلاب'),
          NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment_rounded), label: 'الجلسات'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person_rounded), label: 'الحساب'),
        ],
      ),
    );
  }
}
