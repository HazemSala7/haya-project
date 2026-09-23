import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'report_screen.dart';

/*
 * A child's file, as his family reads it.
 *
 * The medical band sits above everything, every time — «حساسية من الفول
 * السوداني» is the one line on this screen that can matter within the hour,
 * and a screen that makes it earn its place among the figures has already
 * failed at the only thing it could fail at.
 *
 * Below it the sessions are a feed, newest first, and each row says at a
 * glance whether there is anything to read: a published report he has not
 * opened is marked, a session with no report yet says so plainly rather than
 * pretending to be empty.
 */
class ChildDetailScreen extends ConsumerWidget {
  const ChildDetailScreen({super.key, required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(studentProvider(studentId));
    final sessions = ref.watch(studentSessionsProvider(studentId));

    return Scaffold(
      appBar: AppBar(title: const Text('ملف الطفل')),
      body: AsyncView(
        value: file,
        onRetry: () => reload(ref, studentProvider(studentId).future),
        data: (f) {
          final student = f.student;
          final summary = f.summary;

          return RefreshIndicator(
            onRefresh: () async {
              await reload(ref, studentProvider(studentId).future);
              await reload(ref, studentSessionsProvider(studentId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (student.medicalAlert != null && student.medicalAlert!.isNotEmpty) ...[
                  MedicalAlert(student.medicalAlert!),
                  const SizedBox(height: 14),
                ],

                _Head(student: student),

                const SizedBox(height: 14),
                _Numbers(summary: summary),

                if (student.diagnosis != null && student.diagnosis!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SectionCard(
                    title: 'التشخيص',
                    icon: Icons.medical_information_rounded,
                    child: Text(
                      student.diagnosis!,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.8),
                    ),
                  ),
                ],

                const SizedBox(height: 18),
                SectionTitle('سجلّ الجلسات'),

                sessions.when(
                  loading: () => const AppLoading(),
                  error: (error, _) => AppError(
                    error: error,
                    onRetry: () => reload(ref, studentSessionsProvider(studentId).future),
                  ),
                  data: (list) => list.isEmpty
                      ? const AppEmpty(
                          icon: Icons.calendar_today_rounded,
                          title: 'لا جلسات بعد',
                          hint: 'أول تقرير بيوصلك هون.',
                        )
                      : Column(
                          children: [
                            for (final session in list)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: _SessionRow(
                                  session: session,
                                  onTap: session.reportStatus == 'published'
                                      ? () => Navigator.of(context)
                                          .push(MaterialPageRoute(
                                            builder: (_) => ReportScreen(sessionId: session.id),
                                          ))
                                          .then((_) {
                                            reload(ref, studentSessionsProvider(studentId).future);
                                            reload(ref, dashboardProvider.future);
                                          })
                                      : null,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Head extends StatelessWidget {
  const _Head({required this.student});

  final Student student;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [AppColors.brandSoft, AppColors.skySoft],
        ),
        borderRadius: AppShape.card,
      ),
      child: Row(
        children: [
          Avatar(name: student.name, seed: student.id, size: 58),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.name, style: text.titleLarge),
                const SizedBox(height: 3),
                Text(
                  '${student.ageLabel} · ملف ${student.fileNumber}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The three figures a parent actually asks about.
class _Numbers extends StatelessWidget {
  const _Numbers({required this.summary});

  final StudentSummary summary;

  @override
  Widget build(BuildContext context) {
    final rate = summary.attendance.rate;

    return Row(
      children: [
        Expanded(
          child: StatTile(
            label: 'الحضور',
            value: rate == null ? '—' : '$rate%',
            caption: '${summary.attendance.held} من ${summary.attendance.expected} جلسة',
            tone: rate == null
                ? 'muted'
                : rate >= 85
                    ? 'good'
                    : rate >= 70
                        ? 'warn'
                        : 'bad',
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StatTile(
            label: 'أهداف يشتغل عليها',
            value: '${summary.goalsActive}',
            caption: '${summary.goalsMoving} منها تتحرّك',
            tone: 'brand',
          ),
        ),
      ],
    );
  }
}

/// One session in the feed.
class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.onTap});

  final TherapySession session;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final published = session.reportStatus == 'published';
    final unread = published && session.isRead == false;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      // An unread report is the only row worth tinting; the rest are history.
      color: unread ? AppColors.brandSoft : null,
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                Fmt.shortDate(session.scheduledAt),
                style: text.titleSmall?.copyWith(
                  color: unread ? AppColors.brandDeep : AppColors.ink,
                ),
              ),
              Text(Fmt.time(session.scheduledAt), style: text.labelSmall),
            ],
          ),

          Container(
            width: 2,
            height: 34,
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
                SpecialtyTag(session.specialty),
                const SizedBox(height: 4),
                Text(_state(session), style: text.bodySmall),
              ],
            ),
          ),

          if (unread)
            const ToneChip('جديد', tone: 'brand', solid: true)
          else if (published)
            const Icon(Icons.chevron_left_rounded, size: 20, color: AppColors.faint)
          else if (session.status == 'absent')
            const ToneChip('ما حضر', tone: 'bad')
          else
            const ToneChip('التقرير لسّا', tone: 'muted'),
        ],
      ),
    );
  }

  /// What this row is, in the words a family uses.
  static String _state(TherapySession session) {
    if (session.reportStatus == 'published') return 'التقرير جاهز للقراءة';
    if (session.status == 'absent') return 'ما حضر الجلسة';
    if (session.status == 'excused') return 'غياب بعذر';
    return 'الجلسة تمّت، والتقرير لم يُنشر بعد';
  }
}
