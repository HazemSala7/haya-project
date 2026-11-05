import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'office_data.dart';
import 'staff_form.dart' show showPasswordOnce;

/// The one-way sync from the old system on qadrs.com.
///
/// The screen exists for one reason: a sync with no visible log is a sync
/// nobody knows has stopped. It breaks one night — a token expired, a column
/// changed, a disk filled — and the office keeps seeing data that looks right,
/// because it *is* right up to that night. This is where the silence becomes
/// visible.
class SyncScreen extends ConsumerWidget {
  const SyncScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('المزامنة')),
      body: AsyncView<Map<String, dynamic>>(
        value: status,
        onRetry: () => reload(ref, syncStatusProvider.future),
        data: (data) {
          final configured = J.boolean(data['configured']);
          final reviewed = J.boolean(data['schema_reviewed']);
          final runs = J.map(data['schema']);
          final log = (data['runs'] as List?) ?? const [];

          return RefreshList(
            onRefresh: () => reload(ref, syncStatusProvider.future),
            children: [
              SectionCard(
                title: 'الحالة',
                child: Column(
                  children: [
                    InfoRow(label: 'الباب', value: configured ? 'مفتوح' : 'مسكّر'),
                    InfoRow(label: 'الخريطة', value: runs == null ? 'ما وصلت' : 'وصلت'),
                    InfoRow(label: 'الاستيراد', value: reviewed ? 'شغّال' : 'موقوف'),
                  ],
                ),
              ),

              if (!configured)
                const NoteBox(
                  'الباب مسكّر: أي محاولة دفع من النظام القديم بترجع ٤٠٤. '
                  'ولّد توكناً والصقه في haya_sync.php على qadrs.com.',
                  tone: 'muted',
                  icon: Icons.lock_outline_rounded,
                )
              else if (!reviewed)
                const NoteBox(
                  'الاستيراد موقوف لحتى توصل خريطة الأعمدة ويُكتب المقابل. '
                  'شغّل على الخادم القديم: php haya_sync.php schema',
                  tone: 'warn',
                  icon: Icons.schema_outlined,
                ),

              SectionCard(
                title: 'التوكن',
                hint: 'بينعرض مرّة وحدة بس',
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const IconTile(Icons.key_rounded, tone: 'warn'),
                      title: const Text('ولّد توكناً جديداً'),
                      subtitle: const Text('بيبطّل القديم فوراً'),
                      onTap: () => _rotate(context, ref),
                    ),
                    if (configured)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const IconTile(Icons.block_rounded, tone: 'bad'),
                        title: const Text('سكّر الباب', style: TextStyle(color: AppColors.bad)),
                        subtitle: const Text('المزامنة بتوقف لحتى تولّد توكناً من جديد'),
                        onTap: () => _disable(context, ref),
                      ),
                  ],
                ),
              ),

              if (runs != null) _SchemaCard(schema: runs),

              SectionCard(
                title: 'آخر التشغيلات',
                child: log.isEmpty
                    ? const NoteBox(
                        'ما وصل إشي بعد.',
                        tone: 'muted',
                        icon: Icons.sync_disabled_rounded,
                      )
                    : Column(
                        children: [
                          for (final entry in log.take(20))
                            _RunRow(run: J.map(entry) ?? const {}),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _rotate(BuildContext context, WidgetRef ref) async {
    final sure = await confirm(
      context,
      title: 'ولّد توكن مزامنة جديد؟',
      body: 'التوكن القديم بيبطل فوراً، والمزامنة بتوقف لحتى تحطّ الجديد '
          'في haya_sync.php على qadrs.com.',
      confirmLabel: 'ولّد',
    );
    if (!sure) return;

    try {
      final data = await ref.read(apiProvider).postEnvelope('/sync/token');
      final token = J.str(J.map(data['data'])?['token']);

      if (!context.mounted) return;
      ref.invalidate(syncStatusProvider);

      if (token == null) {
        showToast(context, 'انولّد التوكن.');
        return;
      }

      await showPasswordOnce(context, name: 'المزامنة', password: token);
    } on ApiException catch (error) {
      if (context.mounted) showFailure(context, error);
    }
  }

  Future<void> _disable(BuildContext context, WidgetRef ref) async {
    final sure = await confirm(
      context,
      title: 'سكّر باب المزامنة؟',
      body: 'النظام القديم ما بيعود يقدر يبعت. البيانات اللي وصلت بتضلّ.',
      confirmLabel: 'سكّر',
      danger: true,
    );
    if (!sure) return;

    try {
      await ref.read(apiProvider).delete('/sync/token');
      if (!context.mounted) return;
      ref.invalidate(syncStatusProvider);
      showToast(context, 'انسكّر الباب.');
    } on ApiException catch (error) {
      if (context.mounted) showFailure(context, error);
    }
  }
}

/// What the old database actually holds — the report the mapping is written
/// against.
class _SchemaCard extends StatelessWidget {
  const _SchemaCard({required this.schema});

  final Map<String, dynamic> schema;

  @override
  Widget build(BuildContext context) {
    final tables = (schema['tables'] as List?) ?? const [];
    final text = Theme.of(context).textTheme;

    return SectionCard(
      title: 'خريطة النظام القديم',
      hint: 'وصلت ${Fmt.relative(J.str(schema['received_at']))}',
      child: Column(
        children: [
          for (final entry in tables)
            if (J.map(entry) case final table?)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        J.s(table['name']),
                        style: text.bodyMedium,
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    Text(
                      Fmt.number(J.intOrNull(table['rows']) ?? 0),
                      style: text.labelMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});

  final Map<String, dynamic> run;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final problems = (run['problems'] as List?) ?? const [];
    final skipped = J.intOrNull(run['skipped']) ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    J.s(run['kind']),
                    if (J.str(run['table_name']) != null) J.s(run['table_name']),
                  ].join(' · '),
                  style: text.bodyMedium,
                ),
              ),
              Text(
                Fmt.relative(J.str(run['created_at'])),
                style: text.labelSmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
          Text(
            'وصل ${J.intOrNull(run['received']) ?? 0} · '
            'جديد ${J.intOrNull(run['created']) ?? 0} · '
            'محدَّث ${J.intOrNull(run['updated']) ?? 0}'
            '${skipped > 0 ? ' · متروك $skipped' : ''}',
            style: text.labelSmall?.copyWith(
              color: skipped > 0 ? AppColors.warn : AppColors.muted,
            ),
          ),
          // Shown rather than counted: "twelve rows were skipped" is a number
          // nobody can act on, and the reason is usually one sentence.
          for (final problem in problems.take(3))
            Text(
              '— ${J.s(problem)}',
              style: text.labelSmall?.copyWith(color: AppColors.bad),
            ),
        ],
      ),
    );
  }
}
