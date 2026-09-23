import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/// Admin dashboard: stats, alerts, quick actions.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return dashboard.when(
      data: (data) {
        final stats = data['stats'] as Map<String, dynamic>? ?? {};
        final silentFamilies = (data['silent_families'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final unwrittenReports = (data['unwritten_reports'] as List?)?.cast<Map<String, dynamic>>() ?? [];

        return RefreshList(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          children: [
            // Key metrics grid
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle('اليوم'),
                  StatGrid(children: [
                    StatTile(
                      label: 'جلسات مجدولة',
                      value: '${stats['sessions_today'] ?? 0}',
                      tone: 'brand',
                    ),
                    StatTile(
                      label: 'منها تمت',
                      value: '${stats['sessions_held'] ?? 0}',
                      tone: 'good',
                    ),
                    StatTile(
                      label: 'تقاريرها تمتأ',
                      value: '${unwrittenReports.length}',
                      tone: 'warn',
                    ),
                  ]),
                ],
              ),
            ),

            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SectionTitle('الأرقام'),
                  StatGrid(children: [
                    StatTile(
                      label: 'الطلاب',
                      value: '${stats['students'] ?? 0}',
                      caption: 'نشط',
                      tone: 'info',
                    ),
                    StatTile(
                      label: 'الأخصائيات',
                      value: '${stats['specialists'] ?? 0}',
                      tone: 'info',
                    ),
                    StatTile(
                      label: 'الأولياء',
                      value: '${stats['guardians'] ?? 0}',
                      tone: 'info',
                    ),
                  ]),
                ],
              ),
            ),

            // Unwritten reports alert
            if (unwrittenReports.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle('تقاريرتخلفة', count: unwrittenReports.length),
                    for (final report in unwrittenReports.take(3))
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              report['student']?['name'] ?? '',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              'جلسة #${report['number']}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'أخصائية: ${report['specialist']?['name'] ?? '—'}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    if (unwrittenReports.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                          label: Text('و${unwrittenReports.length - 3} تقارير أخرى'),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            // Silent families
            if (silentFamilies.isNotEmpty) ...[
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SectionTitle('عائلات لم تفتح التطبيق', count: silentFamilies.length),
                    for (final family in silentFamilies.take(3))
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(family['name'] ?? '', style: Theme.of(context).textTheme.titleSmall),
                            if (family['phone'] != null)
                              Text(
                                family['phone'],
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            const SizedBox(height: 4),
                            Text(
                              'آخر ظهور: ${family['last_seen'] ?? '—'}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
          ],
        );
      },
      loading: () => const AppLoading(),
      error: (error, _) => AppError(
        error: error,
        onRetry: () => ref.refresh(dashboardProvider.future),
      ),
    );
  }
}
