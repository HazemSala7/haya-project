import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/core.dart';
import 'office_more_screen.dart';
import 'student_office_screen.dart';
import 'students_list_screen.dart';
import 'staff_directory_screen.dart';

/*
 * The office's morning.
 *
 * What was here before showed six figures, three of which the server never
 * sends — `sessions_held` and `unwritten_reports` are not keys of this
 * payload, so «منها تمت» and «تقاريرها تمتأ» were hard zeros on every screen
 * in the building, every day. Meanwhile the three failures the dashboard
 * exists to catch — reports nobody wrote, programmes with no specialist,
 * families whose messages nobody answered — were not drawn at all.
 *
 * So: what is owed first, in words and in the colour of its urgency; then the
 * week's attendance; then the counts, which are context and not news; and the
 * quiet failure last, because it is the one nobody would think to look for.
 */
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final me = ref.watch(meProvider);

    return dashboard.when(
      skipLoadingOnRefresh: true,
      loading: () => const _DashboardSkeleton(),
      error: (error, _) => Padding(
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        child: AppError(error: error, onRetry: () => reload(ref, dashboardProvider.future)),
      ),
      data: (data) {
        final stats = J.map(data['stats']) ?? const {};
        final queue = J.list(data['queue'], (row) => row);
        final silent = J.list(data['silent_families'], (row) => row);

        final today = J.int0(stats['sessions_today']);
        final unwritten = J.int0(stats['unwritten']);
        final unassigned = J.int0(stats['unassigned']);
        final unanswered = J.int0(stats['unanswered']);
        final rate = J.intOrNull(stats['attendance_rate']);

        // The banners are the point of the screen; the rest is context.
        final waiting = <Widget>[
          if (unwritten > 0)
            ActionBanner(
              icon: Icons.edit_note_rounded,
              tone: 'warn',
              title: '${Fmt.reports(unwritten)} ما انكتبت',
              body: queue.isEmpty
                  ? 'جلسات تمّت وأهلها لسّه ما وصلهم تقريرها.'
                  : 'أقدمها جلسة ${J.map(queue.first['student'])?['name'] ?? ''} ${Fmt.relative(J.str(queue.first['scheduled_at']))}.',
              actionLabel: 'شوف الطابور',
              onTap: () => openScreen(context, const OfficeSessionsScreen()),
            ),
          if (unassigned > 0)
            ActionBanner(
              icon: Icons.person_search_rounded,
              tone: 'bad',
              title: '$unassigned ${unassigned == 1 ? 'برنامج' : 'برامج'} بلا أخصائية',
              body: 'الطفل مسجّل بالبرنامج وما في حدا مسؤول عنه — ما بتنجدوَل له جلسة.',
              actionLabel: 'وزّعها',
              onTap: () => openScreen(context, const AdminStudentsListScreen()),
            ),
          if (unanswered > 0)
            ActionBanner(
              icon: Icons.forum_rounded,
              tone: 'info',
              title: '$unanswered ${unanswered == 1 ? 'رسالة' : 'رسائل'} من الأهل بلا ردّ',
              body: 'الأهل بيسألوا عن ولادهم وبينتظروا جواب.',
              actionLabel: 'افتح المراسلات',
              onTap: () => openScreen(context, const AdminStudentsListScreen()),
            ),
        ];

        var step = 0;

        return HeroPage(
          child: RefreshIndicator(
          onRefresh: () => reload(ref, dashboardProvider.future),
          color: AppColors.brand,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 28),
            children: [
              Reveal(
                from: const Offset(0, -0.12),
                child: HomeHero(
                  name: me?.name ?? '',
                  subtitle: 'إدارة الأكاديمية',
                  line: _dayLine(today, J.int0(stats['students'])),
                  trailing: rate == null
                      ? null
                      : _RateRing(percent: rate),
                ),
              ),

              const SizedBox(height: 14),

              if (waiting.isNotEmpty) ...[
                _Heading('لازم انتباهك', step: step++),
                for (final banner in waiting)
                  Reveal.at(
                    step++,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: banner,
                    ),
                  ),
                const SizedBox(height: 6),
              ] else
                Reveal.at(
                  step++,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: NoteBox(
                      'كل التقارير مكتوبة، وكل برنامج إله أخصائية، وما في رسالة بلا ردّ.',
                      tone: 'good',
                      icon: Icons.verified_rounded,
                    ),
                  ),
                ),

              _Heading('الأكاديمية اليوم', step: step++),
              Reveal.at(
                step++,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: StatGrid(
                    children: [
                      StatTile(
                        label: 'جلسات اليوم',
                        value: '$today',
                        icon: Icons.event_available_rounded,
                        tone: 'brand',
                        onTap: () => openScreen(context, const OfficeSessionsScreen()),
                      ),
                      StatTile(
                        label: 'الحضور هالأسبوع',
                        value: rate == null ? '—' : '$rate',
                        suffix: rate == null ? '' : '٪',
                        caption: rate == null
                            ? 'ما في جلسات هالأسبوع'
                            : 'غياب ${Fmt.number(J.int0(stats['absent_week']))} جلسة',
                        icon: Icons.insights_rounded,
                        tone: rate == null || rate >= 80 ? 'good' : 'warn',
                      ),
                      StatTile(
                        label: 'الطلاب',
                        value: '${J.int0(stats['students'])}',
                        caption: 'نشط',
                        icon: Icons.child_care_rounded,
                        tone: 'info',
                        onTap: () => openScreen(context, const AdminStudentsListScreen()),
                      ),
                      StatTile(
                        label: 'الأخصائيات',
                        value: '${J.int0(stats['specialists'])}',
                        icon: Icons.psychology_rounded,
                        tone: 'leaf',
                        onTap: () => openScreen(context, const StaffDirectoryScreen()),
                      ),
                      StatTile(
                        label: 'الأولياء',
                        value: '${J.int0(stats['guardians'])}',
                        caption: 'إلهم حساب',
                        icon: Icons.family_restroom_rounded,
                        tone: 'info',
                      ),
                    ],
                  ),
                ),
              ),

              if (queue.isNotEmpty) ...[
                _Heading('طابور التقارير', step: step++, count: unwritten),
                for (final session in queue.take(4))
                  Reveal.at(
                    step++,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _QueueRow(session: session),
                    ),
                  ),
                if (unwritten > 4)
                  Reveal.at(
                    step++,
                    child: _MoreLink(
                      label: 'وكمان ${Fmt.number(unwritten - 4)} — افتح كل الجلسات',
                      onTap: () => openScreen(context, const OfficeSessionsScreen()),
                    ),
                  ),
              ],

              if (silent.isNotEmpty) ...[
                _Heading('عائلات ما بتفتح التطبيق', step: step++, count: silent.length),
                Reveal.at(
                  step++,
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: NoteBox(
                      'التقارير منشورة وما حدا قراها من ثلاث أسابيع. دقّوا عليهم.',
                      tone: 'warn',
                      icon: Icons.notifications_off_rounded,
                    ),
                  ),
                ),
                for (final family in silent.take(5))
                  Reveal.at(
                    step++,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: _SilentRow(family: family),
                    ),
                  ),
              ],
            ],
          ),
          ),
        );
      },
    );
  }

  /// One sentence about the day, in place of two figures that say less.
  static String _dayLine(int today, int students) {
    if (today == 0) return 'ما في جلسات مجدولة اليوم.';
    return 'اليوم ${Fmt.number(today)} ${today == 1 ? 'جلسة' : 'جلسة'} على جدول الأكاديمية، و${Fmt.number(students)} طفل نشط عندنا.';
  }
}

/// A section heading that arrives with its section.
class _Heading extends StatelessWidget {
  const _Heading(this.title, {required this.step, this.count});

  final String title;
  final int step;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Reveal.at(
      step,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SectionTitle(title, count: count),
      ),
    );
  }
}

/// The week's attendance as a ring on the hero's own colour.
///
/// A ring rather than a number because it is a proportion, and because it is
/// the one figure on this screen that can be read without being read: a ring
/// that is nearly closed is a good week.
class _RateRing extends StatelessWidget {
  const _RateRing({required this.percent});

  final int percent;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 66,
      height: 66,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: percent / 100),
        duration: Motion.count,
        curve: Motion.enter,
        builder: (context, value, _) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 66,
              height: 66,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 5,
                strokeCap: StrokeCap.round,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(value * 100).round()}٪',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.1,
                  ),
                ),
                const Text(
                  'حضور',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Colors.white70, height: 1.2),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One session waiting for its report.
class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.session});

  final Map<String, dynamic> session;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final student = J.map(session['student']) ?? const {};
    final specialist = J.map(session['specialist']) ?? const {};
    final name = J.s(student['name']);

    return AppCard(
      onTap: () {
        final id = J.intOrNull(student['id']);
        if (id != null) openScreen(context, StudentOfficeScreen(studentId: id));
      },
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Avatar(name: name, seed: J.int0(student['id']), size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: text.titleSmall?.copyWith(color: AppColors.ink)),
                Text(
                  '${J.s(specialist['name'])} · ${Fmt.relative(J.str(session['scheduled_at']))}',
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const ToneChip('ما انكتب', tone: 'warn'),
        ],
      ),
    );
  }
}

/// A family the app has not seen in three weeks, with the phone right there —
/// the only thing anybody can actually do about it.
class _SilentRow extends StatelessWidget {
  const _SilentRow({required this.family});

  final Map<String, dynamic> family;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = J.s(family['name']);
    final phone = J.str(family['phone']);
    final children = J.list(family['children'], (child) => J.s(child['name']));
    final seen = J.str(family['last_seen_at']);

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Avatar(name: name, seed: J.int0(family['id']), size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: text.titleSmall?.copyWith(color: AppColors.ink)),
                Text(
                  children.isEmpty ? '—' : children.join('، '),
                  style: text.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  seen == null ? 'ما فتح التطبيق ولا مرة' : 'آخر مرة ${Fmt.relative(seen)}',
                  style: text.labelSmall,
                ),
              ],
            ),
          ),
          if (phone != null)
            IconButton(
              tooltip: 'اتصل',
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''))),
              icon: const Icon(Icons.phone_rounded, color: AppColors.brand),
              style: IconButton.styleFrom(backgroundColor: AppColors.brandSoft),
            ),
        ],
      ),
    );
  }
}

class _MoreLink extends StatelessWidget {
  const _MoreLink({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.arrow_back_rounded, size: 16),
          label: Text(label),
        ),
      ),
    );
  }
}

/// The page's own shape while it loads, instead of a spinner on an empty
/// canvas: the hero's band, two rows of tiles, three rows of cards.
class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          Container(
            height: 190 + MediaQuery.paddingOf(context).top,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SkeletonBox(width: 120, height: 16),
          ),
          const SizedBox(height: 12),
          for (var row = 0; row < 2; row++)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Row(
                children: [
                  Expanded(child: SkeletonBox(height: 92, radius: 18)),
                  SizedBox(width: 10),
                  Expanded(child: SkeletonBox(height: 92, radius: 18)),
                ],
              ),
            ),
          const SkeletonList(rows: 3, padding: EdgeInsets.fromLTRB(16, 8, 16, 0)),
        ],
      ),
    );
  }
}
