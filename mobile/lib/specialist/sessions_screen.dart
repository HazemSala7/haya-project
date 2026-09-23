import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'session_report_screen.dart';

/*
 * Every session, newest first, filtered by what is left to do about it.
 *
 * «تحتاج تقرير» is the default because it is the only filter that describes
 * work rather than history: a specialist opening this tab is almost always
 * looking for the session she has not written up yet, not for a session from
 * March. The other two filters exist for the times she is.
 */
class SessionsScreen extends ConsumerStatefulWidget {
  const SessionsScreen({super.key});

  @override
  ConsumerState<SessionsScreen> createState() => _SessionsScreenState();
}

enum _Filter { owed, published, all }

class _SessionsScreenState extends ConsumerState<SessionsScreen> {
  var _filter = _Filter.owed;

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(sessionsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              for (final f in _Filter.values)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: ChoiceChip(
                    label: Text(_label(f)),
                    selected: _filter == f,
                    onSelected: (_) => setState(() => _filter = f),
                    labelStyle: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _filter == f ? AppColors.brand : AppColors.inkSoft,
                    ),
                    side: BorderSide(
                      color: _filter == f ? AppColors.brand : AppColors.line,
                    ),
                  ),
                ),
            ],
          ),
        ),

        Expanded(
          child: AsyncView(
            value: sessions,
            onRetry: () => reload(ref, sessionsProvider.future),
            data: (list) {
              final shown = [
                for (final s in list)
                  if (_keep(s)) s,
              ];

              if (shown.isEmpty) {
                return AppEmpty(
                  icon: _filter == _Filter.owed
                      ? Icons.task_alt_rounded
                      : Icons.calendar_today_rounded,
                  title: _filter == _Filter.owed ? 'ما في شي متأخّر' : 'لا جلسات',
                  hint: _filter == _Filter.owed
                      ? 'كل جلسة تمّت وصل تقريرها إلى أهلها.'
                      : 'ما في جلسات بهذا الفلتر.',
                );
              }

              return RefreshIndicator(
                onRefresh: () => reload(ref, sessionsProvider.future),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _Row(
                      session: shown[i],
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                            builder: (_) => SessionReportScreen(
                              sessionId: shown[i].id,
                              studentName: shown[i].student?.name ?? '',
                            ),
                          ))
                          .then((_) {
                            reload(ref, sessionsProvider.future);
                            reload(ref, dashboardProvider.future);
                          }),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  bool _keep(TherapySession s) => switch (_filter) {
        _Filter.owed => s.status == 'held' && s.reportStatus != 'published',
        _Filter.published => s.reportStatus == 'published',
        _Filter.all => true,
      };

  static String _label(_Filter f) => switch (f) {
        _Filter.owed => 'تحتاج تقرير',
        _Filter.published => 'انبعتت',
        _Filter.all => 'الكل',
      };
}

class _Row extends StatelessWidget {
  const _Row({required this.session, required this.onTap});

  final TherapySession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(Fmt.shortDate(session.scheduledAt), style: text.titleSmall),
              Text(Fmt.time(session.scheduledAt), style: text.labelSmall),
            ],
          ),

          Container(
            width: 2,
            height: 36,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: SpecialtyColors.of(session.specialty),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.student?.name ?? '—', style: text.titleSmall),
                const SizedBox(height: 3),
                SpecialtyTag(session.specialty),
              ],
            ),
          ),

          _badge(),
        ],
      ),
    );
  }

  Widget _badge() {
    if (session.reportStatus == 'published') {
      return const ToneChip('انبعت', tone: 'good', icon: Icons.check_rounded);
    }
    if (session.status == 'absent') return const ToneChip('ما حضر', tone: 'bad');
    if (session.status == 'excused') return const ToneChip('بعذر', tone: 'warn');
    if (session.status == 'held') {
      return const ToneChip('بدّه تقرير', tone: 'warn', solid: true);
    }
    return const ToneChip('مجدولة', tone: 'muted');
  }
}
