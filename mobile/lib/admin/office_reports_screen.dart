import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'office_data.dart';

/// Periodic reports across the academy.
///
/// The office's question on this screen is one question: which families are
/// waiting. So drafts are the default filter, not "all" — a list that opens on
/// everything makes the four that matter indistinguishable from the ninety
/// that are done.
class OfficeReportsScreen extends ConsumerStatefulWidget {
  const OfficeReportsScreen({super.key});

  @override
  ConsumerState<OfficeReportsScreen> createState() => _OfficeReportsScreenState();
}

class _OfficeReportsScreenState extends ConsumerState<OfficeReportsScreen> {
  String _status = 'draft';

  Future<void> _refresh() => reload(ref, allReportsProvider(_status).future);

  @override
  Widget build(BuildContext context) {
    final reports = ref.watch(allReportsProvider(_status));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('تقارير التقدّم')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                for (final (value, label) in const [
                  ('draft', 'مسوّدات'),
                  ('published', 'وصلت الأهل'),
                  ('', 'الكل'),
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
          Expanded(
            child: AsyncView<List<ProgressReport>>(
              value: reports,
              onRetry: _refresh,
              data: (list) => list.isEmpty
                  ? AppEmpty(
                      icon: Icons.assignment_turned_in_outlined,
                      title: _status == 'draft' ? 'ما في مسوّدات' : 'ما في تقارير',
                      hint: _status == 'draft'
                          ? 'كل التقارير وصلت الأهل.'
                          : 'بتنكتب من ملف الطفل.',
                    )
                  : RefreshList(
                      onRefresh: _refresh,
                      children: [
                        for (final report in list)
                          AppCard(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                            onTap: () => _open(report),
                            onLongPress: () => _menu(report),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(report.student?.name ?? '—', style: text.titleSmall),
                                      Text(
                                        '${Fmt.date(report.periodStart)} — ${Fmt.date(report.periodEnd)}',
                                        style: text.bodySmall?.copyWith(color: AppColors.muted),
                                      ),
                                      if (report.author != null)
                                        Text(
                                          report.author!.name,
                                          style: text.labelSmall?.copyWith(color: AppColors.muted),
                                        ),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    ToneChip(
                                      Labels.reportStatus[report.status] ?? report.status,
                                      tone: Labels.reportTone[report.status] ?? 'muted',
                                    ),
                                    if (report.status == 'draft')
                                      TextButton(
                                        onPressed: () => _publish(report),
                                        child: const Text('انشره'),
                                      ),
                                  ],
                                ),
                                RowMenu(onTap: () => _menu(report)),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// What the office may do to one report.
  ///
  /// A published report is frozen by the server — append-only, a correction
  /// goes under it as an addendum — so both the edit and the delete are shown
  /// switched off with that sentence rather than hidden.
  Future<void> _menu(ProgressReport report) {
    final published = report.status == 'published';
    const frozen = 'التقرير وصل الأهل — ما بينعدّل ولا بينحذف.';

    return showActions(
      context,
      title: report.student?.name ?? 'التقرير',
      subtitle: '${Fmt.date(report.periodStart)} — ${Fmt.date(report.periodEnd)}',
      actions: [
        SheetAction(
          label: 'افتح التقرير',
          icon: Icons.description_outlined,
          onTap: () => _open(report),
        ),
        SheetAction(
          label: 'عدّل المسوّدة',
          icon: Icons.edit_outlined,
          disabledReason: published ? frozen : null,
          onTap: () async {
            final saved = await openProgressReportEdit(context, ref, report);
            if (saved) await _refresh();
          },
        ),
        SheetAction(
          label: 'انشره للأهل',
          icon: Icons.send_rounded,
          tone: 'good',
          disabledReason: published ? 'انبعت من قبل.' : null,
          onTap: () => _publish(report),
        ),
        SheetAction(
          label: 'احذف المسوّدة',
          icon: Icons.delete_outline_rounded,
          tone: 'bad',
          disabledReason: published ? frozen : null,
          onTap: () async {
            final sure = await confirm(
              context,
              title: 'احذف تقرير ${report.student?.name ?? ''}؟',
              body: 'مسوّدة ${Fmt.date(report.periodStart)} — ${Fmt.date(report.periodEnd)} '
                  'بتنشال خالص.',
              confirmLabel: 'احذف',
              danger: true,
            );
            if (!sure) return;

            try {
              await ref.read(apiProvider).delete('/progress-reports/${report.id}');
              if (!mounted) return;
              showToast(context, 'انحذفت المسوّدة.');
              await _refresh();
            } on ApiException catch (error) {
              if (mounted) showFailure(context, error);
            }
          },
        ),
      ],
    );
  }

  /// The report itself, and the one button that matters on it.
  ///
  /// A sheet rather than a screen: the app has no progress-report page — the
  /// guardian's `ReportScreen` is the *session* report — and inventing a
  /// second full page for the office to read the same four paragraphs is how
  /// two renderings of one report come to exist.
  Future<void> _open(ProgressReport report) async {
    await showFormSheet<void>(
      context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(report.student?.name ?? '—', style: Theme.of(context).textTheme.titleLarge),
              Text(
                '${Fmt.date(report.periodStart)} — ${Fmt.date(report.periodEnd)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final (label, body) in [
                ('الملخّص', report.summary),
                ('اللي تحقّق', report.achieved),
                ('التوصيات', report.recommendations),
                ('البرنامج البيتي', report.homeProgram),
              ])
                if (body != null && body.isNotEmpty) ...[
                  SectionTitle(label),
                  Text(body, style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 10),
                ],
              if (report.status == 'draft')
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(sheetContext).pop();
                    _publish(report);
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('انشره للأهل'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _publish(ProgressReport report) async {
    final sure = await confirm(
      context,
      title: 'انشر تقرير ${report.student?.name ?? ''}؟',
      // Publishing is the point of no return in this system: from here the
      // text is append-only, and a correction becomes an addendum under it.
      body: 'بيوصل الأهل فوراً. بعد النشر ما بينعدّل — التصحيح بينضاف كملحق تحته.',
      confirmLabel: 'انشر',
    );
    if (!sure) return;

    try {
      await ref.read(apiProvider).post('/progress-reports/${report.id}/publish');
      if (!mounted) return;
      showToast(context, 'وصل الأهل.');
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) showFailure(context, error);
    }
  }
}


/// Correcting a draft before it is sent. Resolves to true when saved.
///
/// Only the four paragraphs and the period: who the report is about and which
/// programme it belongs to are decided when it is created, and the server
/// will not take them on an update either.
Future<bool> openProgressReportEdit(
  BuildContext context,
  WidgetRef ref,
  ProgressReport report,
) async {
  final done = await showFormSheet<bool>(
    context,
    builder: (_) => _ReportEdit(report: report),
  );
  return done == true;
}

class _ReportEdit extends ConsumerStatefulWidget {
  const _ReportEdit({required this.report});

  final ProgressReport report;

  @override
  ConsumerState<_ReportEdit> createState() => _ReportEditState();
}

class _ReportEditState extends ConsumerState<_ReportEdit> {
  late final _summary = TextEditingController(text: widget.report.summary);
  late final _achieved = TextEditingController(text: widget.report.achieved ?? '');
  late final _recommendations = TextEditingController(text: widget.report.recommendations ?? '');
  late final _homeProgram = TextEditingController(text: widget.report.homeProgram ?? '');
  late DateTime _from = Fmt.at(widget.report.periodStart) ?? DateTime.now();
  late DateTime _to = Fmt.at(widget.report.periodEnd) ?? DateTime.now();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_summary, _achieved, _recommendations, _homeProgram]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_summary.text.trim().isEmpty) {
      setState(() => _error = 'الملخّص مطلوب.');
      return;
    }
    if (_to.isBefore(_from)) {
      setState(() => _error = 'نهاية الفترة قبل بدايتها.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    String? trimmed(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

    try {
      await ref.read(apiProvider).put('/progress-reports/${widget.report.id}', body: {
        'period_start': Fmt.isoDate(_from),
        'period_end': Fmt.isoDate(_to),
        'summary': _summary.text.trim(),
        'achieved': trimmed(_achieved),
        'recommendations': trimmed(_recommendations),
        'home_program': trimmed(_homeProgram),
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(context, 'انحفظت المسوّدة.');
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: 'تعديل المسوّدة',
      subtitle: widget.report.student?.name,
      submitLabel: 'احفظ',
      busy: _busy,
      error: _error,
      onSubmit: _save,
      children: [
        const NoteBox(
          'هاي مسوّدة — ما حدا من الأهل شافها. بعد «انشره» بتتجمّد.',
          tone: 'info',
          icon: Icons.edit_note_rounded,
        ),
        DateField(
          label: 'من',
          value: _from,
          required: true,
          onChanged: (value) => setState(() => _from = value ?? _from),
        ),
        DateField(
          label: 'إلى',
          value: _to,
          required: true,
          onChanged: (value) => setState(() => _to = value ?? _to),
        ),
        AppTextField(controller: _summary, label: 'الملخّص', required: true, maxLines: 6, minLines: 3),
        AppTextField(controller: _achieved, label: 'اللي تحقّق', maxLines: 5, minLines: 2),
        AppTextField(controller: _recommendations, label: 'التوصيات', maxLines: 5, minLines: 2),
        AppTextField(controller: _homeProgram, label: 'البرنامج البيتي', maxLines: 5, minLines: 2),
      ],
    );
  }
}
