import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/widgets/nav_bar.dart';
import 'dashboard_screen.dart';
import 'students_list_screen.dart';
import 'office_more_screen.dart';
import 'staff_directory_screen.dart';
import 'account_screen.dart';

/// The office's five doors.
///
/// The shell carries no bar of its own any more. It used to show the signed-in
/// name above every tab — and every tab but the home one brings its own title,
/// so «الطلاب» sat under «Zaid Zalloum» in two stacked bars and the list lost
/// a hundred pixels to chrome that said nothing. The home tab greets by name
/// in its own hero instead, where there is room to do it properly.
class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  var _index = 0;

  // Built once and kept, so switching tabs does not throw away a half-scrolled
  // list or a filter somebody just set.
  final _screens = const [
    AdminDashboardScreen(),
    AdminStudentsListScreen(),
    StaffDirectoryScreen(),
    OfficeMoreScreen(),
    AdminAccountScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: TabBody(index: _index, children: _screens),
      bottomNavigationBar: AppNavBar(
        index: _index,
        onSelect: (i) => setState(() => _index = i),
        items: const [
          NavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'الرئيسية'),
          NavItem(icon: Icons.people_outline, selectedIcon: Icons.people_rounded, label: 'الطلاب'),
          NavItem(icon: Icons.group_outlined, selectedIcon: Icons.group_rounded, label: 'الفريق'),
          // The sessions, the money, the reports, the settings and the sync —
          // five sections that had no screen at all, so the office could only
          // reach them from a laptop.
          NavItem(icon: Icons.apps_outlined, selectedIcon: Icons.apps_rounded, label: 'المزيد'),
          NavItem(icon: Icons.person_outline, selectedIcon: Icons.person_rounded, label: 'الحساب'),
        ],
      ),
    );
  }
}
