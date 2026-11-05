import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../shared/session_actions.dart';
import '../specialist/session_report_screen.dart';
import 'finance_screen.dart';
import 'office_data.dart';
import 'office_reports_screen.dart';
import 'session_form.dart';
import 'settings_screen.dart';
import 'sync_screen.dart';

/// The rest of the building.
///
/// Four tabs cannot hold an academy: the sessions, the money, the reports,
/// the settings and the sync had no screen at all, so the office could only
/// do them from a laptop. Everything the API allows an admin is reachable
/// from here or from a child's file — those are the only two places anybody
/// should have to look.
class OfficeMoreScreen extends ConsumerWidget {
  const OfficeMoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(billingSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المزيد'), centerTitle: false),
      body: RefreshList(
        onRefresh: () => reload(ref, billingSummaryProvider.future),
        children: [
          SectionCard(
            title: 'الشغل',
            child: Column(
              children: [
                _Door(
                  icon: Icons.event_note_rounded,
                  title: 'الجلسات',
                  subtitle: 'كل الجلسات، وجدولة جلسة جديدة',
                  onTap: () => _push(context, const OfficeSessionsScreen()),
                ),
                _Door(
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'تقارير التقدّم',
                  subtitle: 'المسوّدات اللي لسه ما وصلت الأهل',
                  onTap: () => _push(context, const OfficeReportsScreen()),
                ),
                _Door(
                  icon: Icons.insights_rounded,
                  title: 'التحليلات',
                  subtitle: 'الحضور والتقدّم عبر الأسابيع',
                  onTap: () => _push(context, const OfficeAnalyticsScreen()),
                ),
              ],
            ),
          ),

          SectionCard(
            title: 'المالية',
            hint: summary.valueOrNull == null
                ? null
                : 'مستحقّ ${Fmt.number(J.doubleOrNull(summary.value!['due']) ?? 0)} ₪',
            child: Column(
              children: [
                _Door(
                  icon: Icons.account_balance_wallet_rounded,
                  tone: 'good',
                  title: 'الفواتير والقبض',
                  subtitle: 'أصدِر فواتير الشهر، واقبض',
                  onTap: () => _push(context, const FinanceScreen()),
                ),
              ],
            ),
          ),

          SectionCard(
            title: 'الإدارة',
            child: Column(
              children: [
                _Door(
                  icon: Icons.tune_rounded,
                  tone: 'warn',
                  title: 'إعدادات الأكاديمية',
                  subtitle: 'الاسم، الهاتف، وما يُطبع تحت التقارير',
                  onTap: () => _push(context, const OfficeSettingsScreen()),
                ),
                _Door(
                  icon: Icons.sync_rounded,
                  tone: 'warn',
                  title: 'المزامنة مع النظام القديم',
                  subtitle: 'شو وصل وإيمتى، وتوليد التوكن',
                  onTap: () => _push(context, const SyncScreen()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _Door extends StatelessWidget {
  const _Door({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tone = 'brand',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String tone;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: IconTile(icon, tone: tone),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_left_rounded),
      onTap: onTap,
    );
  }
}

/* -------------------------------------------------------------------------
 | Sessions
 |------------------------------------------------------------------------ */

/// Every session in the building, and the way to schedule one.
///
/// The specialist's own sessions screen is scoped to her by the server; this
/// one asks for everything, because the office covers for absences and has to
/// see whose diary is empty.
class OfficeSessionsScreen extends ConsumerStatefulWidget {
  const OfficeSessionsScreen({super.key});

  @override
  ConsumerState<OfficeSessionsScreen> createState() => _OfficeSessionsScreenState();
}

class _OfficeSessionsScreenState extends ConsumerState<OfficeSessionsScreen> {
  final _list = GlobalKey<PagedListState<TherapySession>>();
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الجلسات')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final created = await openSessionForm(context, ref);
          if (created == null || !context.mounted) return;
          showToast(context, 'انجدولت الجلسة.');
          _list.currentState?.reload();
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('جلسة جديدة'),
      ),
      body: PagedList<TherapySession>(
        key: _list,
        filterKey: _status,
        header: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (value, label) in const [
                  ('', 'الكل'),
                  ('scheduled', 'مجدولة'),
                  ('held', 'تمّت'),
                  ('absent', 'ما إجا'),
                  ('cancelled', 'ملغية'),
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _status == value,
                      onSelected: (_) => setState(() => _status = value),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        fetch: (page) async => PageOf.fromEnvelope(
          await ref.read(apiProvider).getEnvelope('/sessions', query: {
            'page': page,
            'per_page': 30,
            if (_status.isNotEmpty) 'status': _status,
          }),
          TherapySession.fromJson,
        ),
        empty: const AppEmpty(
          icon: Icons.event_busy_rounded,
          title: 'ما في جلسات',
          hint: 'اجدول جلسة من الزرّ تحت.',
        ),
        itemBuilder: (context, session) => _SessionRow(
          session: session,
          onMore: () => showActions(
            context,
            title: session.student?.name ?? 'الجلسة',
            subtitle: Fmt.dateTime(session.scheduledAt),
            actions: sessionActions(
              context,
              ref,
              session,
              onChanged: () => _list.currentState?.reload(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SessionRow extends StatelessWidget {
  const _SessionRow({required this.session, required this.onMore});

  final TherapySession session;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => SessionReportScreen(
          sessionId: session.id,
          studentName: session.student?.name ?? '',
        ),
      )),
      onLongPress: onMore,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(session.student?.name ?? '—', style: text.titleSmall),
                Text(
                  Fmt.dateTime(session.scheduledAt),
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    SpecialtyTag(session.specialty),
                    if (session.specialist != null)
                      Text(
                        session.specialist!.name,
                        style: text.labelSmall?.copyWith(color: AppColors.muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ToneChip(
                Labels.sessionStatus[session.status] ?? session.status,
                tone: Labels.sessionTone[session.status] ?? 'muted',
              ),
              const SizedBox(height: 4),
              // The office's actual job on this screen: the sessions that
              // happened and whose report the family has not been sent.
              if (session.status == 'held' && session.reportStatus == 'draft')
                const ToneChip('التقرير مسوّدة', tone: 'warn', icon: Icons.edit_note_rounded),
            ],
          ),
          RowMenu(onTap: onMore),
        ],
      ),
    );
  }
}

/* -------------------------------------------------------------------------
 | Analytics
 |------------------------------------------------------------------------ */

class OfficeAnalyticsScreen extends ConsumerStatefulWidget {
  const OfficeAnalyticsScreen({super.key});

  @override
  ConsumerState<OfficeAnalyticsScreen> createState() => _OfficeAnalyticsScreenState();
}

class _OfficeAnalyticsScreenState extends ConsumerState<OfficeAnalyticsScreen> {
  int _weeks = 12;

  @override
  Widget build(BuildContext context) {
    final analytics = ref.watch(analyticsProvider(_weeks));

    return Scaffold(
      appBar: AppBar(title: const Text('التحليلات')),
      body: AsyncView<Map<String, dynamic>>(
        value: analytics,
        onRetry: () => reload(ref, analyticsProvider(_weeks).future),
        data: (data) => RefreshList(
          onRefresh: () => reload(ref, analyticsProvider(_weeks).future),
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final weeks in const [4, 8, 12, 26])
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text('$weeks أسبوع'),
                        selected: _weeks == weeks,
                        onSelected: (_) => setState(() => _weeks = weeks),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            StatGrid(
              children: [
                StatTile(
                  label: 'الحضور',
                  value: Fmt.percent(J.doubleOrNull(data['attendance_rate'])),
                  tone: 'good',
                ),
                StatTile(
                  label: 'الجلسات',
                  value: Fmt.number(J.intOrNull(data['sessions']) ?? 0),
                ),
                StatTile(
                  label: 'التقارير',
                  value: Fmt.number(J.intOrNull(data['reports']) ?? 0),
                ),
              ],
            ),
            // The server shapes the series; the chart widget reads it. Kept
            // deliberately thin — a second place that computes an average is
            // a second answer to "how is he doing".
            const SizedBox(height: 8),
            const NoteBox(
              'التفصيل الكامل بالرسوم على لوحة الويب. هون الأرقام اللي بتلزم بسرعة.',
              tone: 'muted',
              icon: Icons.info_outline_rounded,
            ),
          ],
        ),
      ),
    );
  }
}
