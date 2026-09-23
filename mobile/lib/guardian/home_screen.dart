import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'child_detail_screen.dart';

/*
 * What a mother opens at ten at night.
 *
 * The API says it plainly where `unread_reports` is built: that is the number
 * the whole app is arranged around, and every other figure on this screen is
 * context for it. So it is the first thing drawn, in words rather than as a
 * counter — «١٦ تقريراً لم تقرئيهم بعد» is a sentence a tired person reads in
 * one pass, and a red 16 in a corner is a thing she has to go and interpret.
 *
 * Everything under it belongs to one child, inside one card, because a parent
 * of two thinks about two children and not about eight figures.
 */
class GuardianHomeScreen extends ConsumerWidget {
  const GuardianHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final me = ref.watch(meProvider);

    return AsyncView(
      value: dashboard,
      onRetry: () => reload(ref, dashboardProvider.future),
      data: (data) {
        final children = J.list(data['children'], (m) => m);
        final messages = J.int0(data['unread_messages']);
        final unread = children.fold<int>(0, (n, c) => n + J.int0(c['unread_reports']));

        return RefreshIndicator(
          onRefresh: () => reload(ref, dashboardProvider.future),
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              HomeHero(
                name: me?.name ?? '',
                line: _line(children, unread),
              ),

              const SizedBox(height: 16),

              if (messages > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: ActionBanner(
                    icon: Icons.forum_rounded,
                    title: '${Fmt.messages(messages)} من الأكاديمية',
                    body: 'لم تُقرأ بعد.',
                    tone: 'info',
                  ),
                ),

              if (children.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: AppEmpty(
                    icon: Icons.child_care_rounded,
                    title: 'لا يوجد أطفال على حسابك',
                    hint: 'راجعي إدارة الأكاديمية لربط ملف طفلك.',
                  ),
                )
              else
                for (final child in children)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: _ChildCard(
                      child: child,
                      onTap: () => Navigator.of(context)
                          .push(MaterialPageRoute(
                            builder: (_) => ChildDetailScreen(studentId: J.int0(child['id'])),
                          ))
                          .then((_) => reload(ref, dashboardProvider.future)),
                    ),
                  ),

              const SizedBox(height: 28),
            ],
          ),
        );
      },
    );
  }

  /// The one sentence the hero carries.
  static String _line(List<Map<String, dynamic>> children, int unread) {
    if (children.isEmpty) return 'لا يوجد ملف مرتبط بحسابك بعد.';
    if (unread == 0) return 'ما في تقارير جديدة — قرأتِ كل شيء.';

    final name = J.s(children.first['name']).split(' ').first;
    /*
     * No adjective after the count.
     *
     * «١٦ تقريراً جديدة» disagrees — the counted noun turns singular at eleven
     * and the adjective has to follow it, so «جديدة» is right after «٣ تقارير»
     * and wrong after «١٦ تقريراً». Rather than carry a second set of forms for
     * every adjective the app might use, the sentence says what the reports are
     * by what has not happened to them.
     */
    return children.length == 1
        ? '${Fmt.reports(unread)} عن $name لم تقرئيها بعد.'
        : '${Fmt.reports(unread)} عن أطفالك لم تُقرأ بعد.';
  }
}

/// One child, whole.
class _ChildCard extends StatelessWidget {
  const _ChildCard({required this.child, required this.onTap});

  final Map<String, dynamic> child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    final name = J.s(child['name']);
    final unread = J.int0(child['unread_reports']);
    final summary = J.map(child['summary']) ?? const {};
    final attendance = J.map(summary['attendance']) ?? const {};
    final goals = J.map(summary['goals']) ?? const {};
    final last = J.map(summary['last_session']);
    final programmes = J.list(child['programmes'], (m) => m);

    final rate = J.intOrNull(attendance['rate']);

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Head: who this is, and whether there is anything new about him.
          Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
            decoration: const BoxDecoration(
              color: AppColors.brandSoft,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Avatar(name: name, seed: J.int0(child['id']), size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                        '${J.s(child['age_label'])} · ملف ${J.s(child['file_number'])}',
                        style: text.bodySmall,
                      ),
                    ],
                  ),
                ),

                /*
                 * The badge is a word and a number, not a number alone. «١٦
                 * جديد» tells a parent what to do with it; a bare 16 on a disc
                 * is a puzzle she has to open the app further to solve.
                 */
                if (unread > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.brand,
                      borderRadius: AppShape.chip,
                    ),
                    child: Text(
                      '$unread جديد',
                      style: text.labelLarge?.copyWith(color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Figure(
                        value: rate == null ? '—' : '$rate%',
                        label: 'حضور آخر ٣ شهور',
                        tone: rate == null
                            ? 'muted'
                            : rate >= 85
                                ? 'good'
                                : rate >= 70
                                    ? 'warn'
                                    : 'bad',
                      ),
                    ),
                    Container(width: 1, height: 34, color: AppColors.lineSoft),
                    Expanded(
                      child: _Figure(
                        value: '${J.int0(goals['active'])}',
                        label: 'أهداف يشتغل عليها',
                        tone: 'brand',
                      ),
                    ),
                    Container(width: 1, height: 34, color: AppColors.lineSoft),
                    Expanded(
                      child: _Figure(
                        value: '${J.int0(goals['achieved'])}',
                        label: 'أهداف تحقّقت',
                        tone: J.int0(goals['achieved']) > 0 ? 'good' : 'muted',
                      ),
                    ),
                  ],
                ),

                if (programmes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(height: 1, color: AppColors.lineSoft),
                  const SizedBox(height: 12),

                  // Who is actually working with him. A parent remembers the
                  // specialist's name long before she remembers the programme's.
                  for (final p in programmes)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 7),
                      child: Row(
                        children: [
                          SpecialtyTag(J.str(p['specialty'])),
                          const Spacer(),
                          Text(
                            J.s(p['specialist']),
                            style: text.bodySmall?.copyWith(color: AppColors.inkSoft),
                          ),
                        ],
                      ),
                    ),
                ],

                if (last != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.history_rounded, size: 15, color: AppColors.faint),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'آخر جلسة ${Fmt.relative(J.str(last['scheduled_at']))}',
                          style: text.bodySmall,
                        ),
                      ),
                      ToneChip(
                        Labels.sessionStatus[J.str(last['status'])] ?? '—',
                        tone: switch (J.str(last['status'])) {
                          'held' => 'good',
                          'absent' => 'bad',
                          'excused' => 'warn',
                          _ => 'muted',
                        },
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One figure under a child's name.
class _Figure extends StatelessWidget {
  const _Figure({required this.value, required this.label, required this.tone});

  final String value;
  final String label;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Text(
          value,
          style: text.titleLarge?.copyWith(
            color: AppColors.byName(tone),
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          textAlign: TextAlign.center,
          style: text.labelSmall,
        ),
      ],
    );
  }
}
