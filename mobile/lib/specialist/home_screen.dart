import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'session_report_screen.dart';

/*
 * A specialist's day.
 *
 * The screen this replaces opened on «جلسات اليوم ٠ · منها تمت ٠», which is
 * what an empty afternoon looks like and also what a broken app looks like.
 * Meanwhile the three facts that actually needed her — three unwritten
 * reports, the oldest of them a month old, two unread messages from families
 * — were either buried below or not drawn at all.
 *
 * So the order here is what is owed first, the day second, and the totals
 * last. `today` is drawn as the diary it is rather than counted, because a
 * list of four names and four times answers "what is my day" in one look and
 * the number 4 does not.
 */
class SpecialistHomeScreen extends ConsumerWidget {
  const SpecialistHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final me = ref.watch(meProvider);

    return AsyncView(
      value: dashboard,
      onRetry: () => reload(ref, dashboardProvider.future),
      data: (data) {
        final stats = J.map(data['stats']) ?? const {};
        final today = J.list(data['today'], (m) => m);
        final queue = J.list(data['queue'], (m) => m);

        final total = J.int0(stats['today_total']);
        final held = J.int0(stats['today_held']);
        final unwritten = J.int0(stats['unwritten']);
        final oldest = J.str(stats['oldest_unwritten']);
        final messages = J.int0(stats['unread_messages']);

        return RefreshIndicator(
          onRefresh: () => reload(ref, dashboardProvider.future),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              HomeHero(
                name: me?.name ?? '',
                subtitle: me?.title,
                line: _dayLine(total, held),
                trailing: total > 0
                    ? HeroFigure(value: '$held/$total', label: 'تمّت')
                    : null,
              ),

              const SizedBox(height: 16),

              // What is waiting for her, before anything she might merely
              // like to know.
              if (unwritten > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: ActionBanner(
                    icon: Icons.edit_note_rounded,
                    title: '${Fmt.reports(unwritten)} بانتظارك',
                    body: oldest == null
                        ? 'جلسات تمّت ولم يصل أهلها تقريرها بعد.'
                        : 'أقدمها جلسة ${Fmt.relative(oldest)} — والأسرة تنتظرها منذ ذلك اليوم.',
                    actionLabel: 'اكتبها الآن',
                    tone: 'warn',
                    onTap: () => _openFirst(context, ref, queue),
                  ),
                ),

              if (messages > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: ActionBanner(
                    icon: Icons.forum_rounded,
                    title: '${Fmt.messages(messages)} غير مقروءة',
                    body: 'من أهالي أطفالك.',
                    tone: 'info',
                  ),
                ),

              const SizedBox(height: 6),
              SectionTitle('جلسات اليوم', count: total == 0 ? null : total),

              if (today.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: AppEmpty(
                    icon: Icons.self_improvement_rounded,
                    title: 'لا جلسات اليوم',
                    hint: 'يوم بلا موعد — فرصة لتقرير متأخّر.',
                  ),
                )
              else
                for (final session in today)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _DiaryRow(session: session),
                  ),

              const SizedBox(height: 14),
              SectionTitle('تقارير لم تُكتب', count: queue.isEmpty ? null : queue.length),

              if (queue.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: AppEmpty(
                    icon: Icons.task_alt_rounded,
                    title: 'لا شيء متأخّر',
                    hint: 'كل جلسة تمّت وصل تقريرها إلى أهلها.',
                  ),
                )
              else
                for (final session in queue)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: _QueueRow(
                      session: session,
                      onTap: () => _open(context, ref, session),
                    ),
                  ),

              const SizedBox(height: 28),
            ],
          ),
        );
      },
    );
  }

  /// The day in one sentence, so the hero says something even at zero.
  static String _dayLine(int total, int held) {
    if (total == 0) return 'ما في جلسات مجدولة اليوم.';
    if (held == 0) return 'عندك ${Fmt.sessions(total)} اليوم، لسّا ما بلّشت.';
    if (held >= total) return 'خلّصت جلسات اليوم كلها. اليوم صافي.';
    return 'تمّت $held من $total، وضلّ ${total - held}.';
  }

  void _openFirst(BuildContext context, WidgetRef ref, List<Map<String, dynamic>> queue) {
    if (queue.isNotEmpty) _open(context, ref, queue.first);
  }

  void _open(BuildContext context, WidgetRef ref, Map<String, dynamic> session) {
    final student = J.map(session['student']);

    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => SessionReportScreen(
            sessionId: J.int0(session['id']),
            studentName: J.s(student?['name']),
          ),
        ))
        .then((_) => reload(ref, dashboardProvider.future));
  }
}

/// One appointment in the day's diary.
class _DiaryRow extends StatelessWidget {
  const _DiaryRow({required this.session});

  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final student = J.map(session['student']);
    final status = J.str(session['status']);
    final alert = J.str(student?['medical_alert']);

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The time is the spine of a diary, so it is set as a column of its
          // own rather than as a line of small print inside the row.
          SizedBox(
            width: 52,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Fmt.time(J.str(session['scheduled_at'])),
                  style: text.titleSmall?.copyWith(color: AppColors.brand),
                ),
                Text('${J.int0(session['duration_minutes'])}د', style: text.labelSmall),
              ],
            ),
          ),

          Container(
            width: 2,
            height: 38,
            margin: const EdgeInsets.only(left: 12, right: 2),
            decoration: BoxDecoration(
              color: SpecialtyColors.of(J.str(session['specialty'])),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(J.s(student?['name']), style: text.titleSmall),
                const SizedBox(height: 3),
                SpecialtyTag(J.str(session['specialty'])),

                // The one thing on this row that can matter more than the
                // appointment itself.
                if (alert != null && alert.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(Icons.warning_rounded, size: 14, color: AppColors.bad),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          alert,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.labelMedium?.copyWith(color: AppColors.bad),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          if (status != null) ToneChip(Labels.sessionStatus[status] ?? status, tone: _tone(status)),
        ],
      ),
    );
  }

  static String _tone(String status) => switch (status) {
        'held' => 'good',
        'absent' => 'bad',
        'excused' => 'warn',
        _ => 'muted',
      };
}

/// A session whose family is still waiting.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.session, required this.onTap});

  final Map<String, dynamic> session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final student = J.map(session['student']);
    final at = J.str(session['scheduled_at']);
    final days = _daysSince(at);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Avatar(name: J.s(student?['name']), seed: J.int0(student?['id'])),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(J.s(student?['name']), style: text.titleSmall),
                Text(Fmt.dayDate(at), style: text.bodySmall),
              ],
            ),
          ),

          // Lateness is the sort order and the only reason one of these rows
          // matters more than another, so it is the thing drawn.
          if (days != null)
            ToneChip(
              days == 0 ? 'اليوم' : 'من ${Fmt.days(days)}',
              tone: days >= 7 ? 'bad' : days >= 3 ? 'warn' : 'muted',
            ),

          const SizedBox(width: 6),
          const Icon(Icons.chevron_left_rounded, size: 20, color: AppColors.faint),
        ],
      ),
    );
  }

  static int? _daysSince(String? value) {
    final when = Fmt.at(value);
    if (when == null) return null;
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .difference(DateTime(when.year, when.month, when.day))
        .inDays;
  }
}
