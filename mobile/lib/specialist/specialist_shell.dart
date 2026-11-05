import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/data.dart';
import '../core/models/json.dart';
import '../core/widgets/nav_bar.dart';
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

  final _screens = const [
    SpecialistHomeScreen(),
    StudentsScreen(),
    SessionsScreen(),
    SpecialistAccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    /*
     * No bar over the home tab.
     *
     * Its hero already carries her name, her title and the date, and a bar
     * above it repeated the first two in smaller type — two greetings stacked,
     * and thirty fewer pixels for the day itself. The other tabs still want a
     * title, so they keep one.
     */
    const titles = [null, 'الطلاب', 'الجلسات', 'الحساب'];

    /*
     * What she owes, on the tab that holds it.
     *
     * The home screen says it in words; the badge keeps saying it after she
     * has moved on to another tab, which is the whole point of a badge. It
     * reads the dashboard the home tab already loaded, so it costs no call.
     */
    final owed = ref.watch(dashboardProvider).maybeWhen(
          data: (data) => J.int0(J.map(data['stats'])?['unwritten']),
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
          const NavItem(icon: Icons.people_outline, selectedIcon: Icons.people_rounded, label: 'الطلاب'),
          NavItem(
            icon: Icons.assessment_outlined,
            selectedIcon: Icons.assessment_rounded,
            label: 'الجلسات',
            badge: owed,
          ),
          const NavItem(icon: Icons.person_outline, selectedIcon: Icons.person_rounded, label: 'الحساب'),
        ],
      ),
    );
  }
}
