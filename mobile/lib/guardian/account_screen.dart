import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session.dart';
import '../core/widgets/ui.dart';

class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(meProvider);

    return RefreshList(
      onRefresh: () => ref.read(sessionProvider.notifier).refreshUser(),
      children: [
        SectionCard(
          title: 'الحساب',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InfoRow(label: 'الاسم', value: user?.name),
              InfoRow(label: 'البريد', value: user?.email, ltr: true),
              if (user?.phone != null) InfoRow(label: 'الهاتف', value: user?.phone, ltr: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: OutlinedButton.icon(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('تسجيل خروج'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
        ),
      ],
    );
  }
}
