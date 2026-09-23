import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/*
 * One session, read by the mother it was written for.
 *
 * This is the screen the app exists to deliver. Everything else — the counts,
 * the cards, the attendance percentage — is scaffolding around four paragraphs
 * a specialist wrote about somebody's child, and they are set here as prose:
 * reading sizes, generous leading, one column, no chrome competing with the
 * words. The dashboard's own stylesheet says the same thing about its report
 * page, and this follows it rather than inventing a second opinion.
 *
 * The four sections are not equal and are not ordered by the form that
 * produced them. «كيف كان معنا اليوم» comes first because that is the question
 * being asked. «شو بتعملوا بالبيت» comes last because it is the only part that
 * asks her to do something, and a request reads better after its reason.
 */
class ReportScreen extends ConsumerWidget {
  const ReportScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider(sessionId));

    return Scaffold(
      appBar: AppBar(title: const Text('تقرير الجلسة')),
      body: AsyncView(
        value: session,
        onRetry: () => reload(ref, sessionProvider(sessionId).future),
        data: (s) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (s.student?.medicalAlert != null && s.student!.medicalAlert!.isNotEmpty) ...[
              MedicalAlert(s.student!.medicalAlert!),
              const SizedBox(height: 14),
            ],

            _Masthead(session: s),
            const SizedBox(height: 18),

            if (s.status != 'held')
              NoteBox(
                s.status == 'absent'
                    ? 'ما حضر الجلسة.'
                    : 'الجلسة كانت بعذر ولم تُعقد.',
                tone: s.status == 'absent' ? 'bad' : 'warn',
                icon: Icons.event_busy_rounded,
              )
            else ...[
              _Passage(
                title: 'كيف كان معنا اليوم',
                body: s.progress,
                icon: Icons.favorite_rounded,
                tone: 'good',
              ),
              _Passage(
                title: 'شو عملنا بالجلسة',
                body: s.activities,
                icon: Icons.extension_rounded,
                tone: 'brand',
              ),
              _Passage(
                title: 'شو صعب عليه',
                body: s.difficulties,
                icon: Icons.trending_down_rounded,
                tone: 'warn',
              ),

              if (s.ratings.isNotEmpty) ...[
                const SizedBox(height: 4),
                SectionTitle('الأهداف اليوم', count: s.ratings.length),
                for (final rating in s.ratings)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _GoalRow(rating: rating),
                  ),
              ],

              if (s.attachments.isNotEmpty) ...[
                const SizedBox(height: 4),
                SectionTitle('من الجلسة', count: s.attachments.length),
                AttachmentGrid(items: s.attachments),
                const SizedBox(height: 14),
              ],

              // Last, and loudest, because it is the only ask.
              if (s.homePlan != null && s.homePlan!.trim().isNotEmpty)
                _HomePlan(text: s.homePlan!),
            ],

            if (s.addenda.isNotEmpty) ...[
              const SizedBox(height: 18),
              SectionTitle('إضافات لاحقة', count: s.addenda.length),
              for (final addendum in s.addenda)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          addendum.body,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.9),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${addendum.author?.name ?? ''} · ${Fmt.relative(addendum.createdAt)}',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Who wrote this, about which session, and how he was that day.
class _Masthead extends StatelessWidget {
  const _Masthead({required this.session});

  final TherapySession session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final face = Labels.moodFace[session.mood];

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SpecialtyTag(session.specialty, full: true),
                    const SizedBox(height: 6),
                    Text(Fmt.dayDate(session.scheduledAt), style: text.titleMedium),
                    Text(
                      '${Fmt.time(session.scheduledAt)} · ${session.durationMinutes} دقيقة',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),

              /*
               * The mood as its face, large.
               *
               * It is the first thing a parent looks for and the last thing
               * she would want to hunt for in a row of chips — «كيف كان
               * مزاجه؟» is most of the question «كيف كان يومه؟».
               */
              if (face != null)
                Column(
                  children: [
                    Text(face, style: const TextStyle(fontSize: 38)),
                    const SizedBox(height: 2),
                    Text(Labels.mood[session.mood] ?? '', style: text.labelMedium),
                  ],
                ),
            ],
          ),

          if (session.specialist != null) ...[
            const SizedBox(height: 14),
            const Divider(height: 1, color: Colors.white),
            const SizedBox(height: 12),
            Row(
              children: [
                Avatar(
                  name: session.specialist!.name,
                  seed: session.specialist!.id,
                  size: 36,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(session.specialist!.name, style: text.titleSmall),
                      if (session.specialist!.title != null)
                        Text(session.specialist!.title!, style: text.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One of the written passages, set to be read rather than scanned.
class _Passage extends StatelessWidget {
  const _Passage({
    required this.title,
    required this.body,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String? body;
  final IconData icon;
  final String tone;

  @override
  Widget build(BuildContext context) {
    if (body == null || body!.trim().isEmpty) return const SizedBox.shrink();

    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: AppColors.byName(tone)),
              const SizedBox(width: 7),
              Text(
                title,
                style: text.titleSmall?.copyWith(color: AppColors.byName(tone)),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            body!.trim(),
            // 1.9 rather than the app's 1.6: this is the only place in the
            // product where somebody reads more than two lines at a time.
            style: text.bodyLarge?.copyWith(height: 1.9, color: AppColors.ink),
          ),
        ],
      ),
    );
  }
}

/// The one thing the report asks the family to do.
class _HomePlan extends StatelessWidget {
  const _HomePlan({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final styles = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.sageSoft,
        borderRadius: AppShape.card,
        border: Border.all(color: AppColors.sage.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.home_rounded, size: 18, color: AppColors.brandDeep),
              const SizedBox(width: 7),
              Text(
                'شو بتعملوا بالبيت',
                style: styles.titleSmall?.copyWith(color: AppColors.brandDeep),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(text.trim(), style: styles.bodyLarge?.copyWith(height: 1.9)),
        ],
      ),
    );
  }
}

/// A goal, and how much help he needed with it today.
class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.rating});

  final GoalRating rating;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  rating.goalTitle ?? '—',
                  style: text.titleSmall?.copyWith(height: 1.6),
                ),
              ),
              const SizedBox(width: 8),
              LevelChip(rating.level),
            ],
          ),

          if (rating.note != null && rating.note!.trim().isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(rating.note!.trim(), style: text.bodySmall?.copyWith(height: 1.7)),
          ],

          if (rating.trials != null && rating.trials! > 0) ...[
            const SizedBox(height: 7),
            Text(
              '${rating.successes ?? 0} من ${rating.trials} محاولات',
              style: text.labelMedium,
            ),
          ],
        ],
      ),
    );
  }
}
