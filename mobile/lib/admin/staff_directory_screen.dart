import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/// Directory of all staff accounts: specialists, managers, admins.
class StaffDirectoryScreen extends ConsumerWidget {
  const StaffDirectoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final specialists = ref.watch(specialistsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('الفريق'),
        centerTitle: false,
      ),
      body: specialists.when(
        data: (list) {
          if (list.isEmpty) {
            return const AppEmpty(
              icon: Icons.people_outline,
              title: 'لا توجد أخصائيات',
              hint: 'سيظهرن هنا عند الإضافة.',
            );
          }

          return ListView.builder(
            itemCount: list.length,
            padding: const EdgeInsets.all(16),
            itemBuilder: (context, i) {
              final account = list[i];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: StaffCard(account: account),
              );
            },
          );
        },
        loading: () => const AppLoading(),
        error: (error, _) => AppError(
          error: error,
          onRetry: () => ref.refresh(specialistsProvider.future),
        ),
      ),
    );
  }
}

/// One staff member card.
class StaffCard extends StatelessWidget {
  const StaffCard({super.key, required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      child: Row(
        children: [
          Avatar(name: account.name, seed: account.id, size: 50),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.name, style: text.titleSmall),
                if (account.title != null && account.title!.isNotEmpty)
                  Text(account.title!, style: text.bodySmall?.copyWith(color: AppColors.muted)),
                if (account.specialty != null && account.specialty!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SpecialtyTag(account.specialty!),
                ],
              ],
            ),
          ),
          Column(
            children: [
              ToneChip(
                account.isActive ? 'نشط' : 'خامل',
                tone: account.isActive ? 'good' : 'muted',
                solid: account.isActive,
              ),
              if ((account.childrenCount ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: CountBadge(
                    count: account.childrenCount ?? 0,
                    child: const Icon(Icons.people_alt_rounded, size: 18),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
