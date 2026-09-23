import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session.dart';
import 'dashboard_screen.dart';
import 'students_list_screen.dart';
import 'staff_directory_screen.dart';
import 'account_screen.dart';

class AdminShell extends ConsumerStatefulWidget {
  const AdminShell({super.key});

  @override
  ConsumerState<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends ConsumerState<AdminShell> {
  var _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(meProvider);

    final screens = [
      const AdminDashboardScreen(),
      const AdminStudentsListScreen(),
      const StaffDirectoryScreen(),
      const AdminAccountScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(user?.name ?? ''),
        elevation: 0,
      ),
      body: screens[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'الرئيسية'),
          NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people_rounded), label: 'الطلاب'),
          NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group_rounded), label: 'الفريق'),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person_rounded), label: 'الحساب'),
        ],
      ),
    );
  }
}
