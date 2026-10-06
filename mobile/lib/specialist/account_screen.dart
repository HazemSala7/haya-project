import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/session.dart';
import '../core/theme.dart';
import '../core/widgets/ui.dart';
import '../shared/delete_account_screen.dart';

class SpecialistAccountScreen extends ConsumerWidget {
  const SpecialistAccountScreen({super.key});

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
              if (user?.title != null) InfoRow(label: 'الوظيفة', value: user?.title),
              if (user?.specialty != null) InfoRow(label: 'التخصص', value: user?.specialtyLabel),
              InfoRow(label: 'البريد', value: user?.email, ltr: true),
              if (user?.phone != null) InfoRow(label: 'الهاتف', value: user?.phone, ltr: true),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
          child: OutlinedButton.icon(
            onPressed: () => ref.read(sessionProvider.notifier).signOut(),
            icon: const Icon(Icons.logout_rounded, size: 18),
            label: const Text('تسجيل خروج'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
        ),

        /*
         * Closing the account, quietly placed.
         *
         * Both stores require it to be reachable from inside the app, and
         * neither requires it to be loud. It sits under signing out, in plain
         * text rather than as a button, because the person who wants it will
         * look for it and nobody else should meet it by accident.
         */
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
            ),
            child: Text(
              'حذف الحساب',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: AppColors.bad),
            ),
          ),
        ),
      ],
    );
  }
}
