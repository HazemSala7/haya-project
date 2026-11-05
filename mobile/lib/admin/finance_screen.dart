import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'office_data.dart';
import 'student_billing_sheet.dart';

/// The money: what is owed, what came in, and issuing the month.
///
/// Issuing is a button and not a clock — there is no scheduler on this host —
/// and pressing it twice charges nobody twice; the server is idempotent per
/// child per month. Which is why the button can sit here plainly instead of
/// behind a warning nobody reads.
class FinanceScreen extends ConsumerStatefulWidget {
  const FinanceScreen({super.key});

  @override
  ConsumerState<FinanceScreen> createState() => _FinanceScreenState();
}

class _FinanceScreenState extends ConsumerState<FinanceScreen> {
  String _status = 'outstanding';
  bool _issuing = false;

  ({String status, String period}) get _filter =>
      (status: _status == 'outstanding' ? '' : _status, period: '');

  Future<void> _refresh() async {
    ref.invalidate(billingSummaryProvider);
    await reload(ref, invoicesProvider(_filter).future);
  }

  /// The row's ⋮ — قبض، تعديل، حذف — the same three the student's own
  /// account sheet offers, so a person learns them once.
  Future<void> _invoiceMenu(Invoice invoice) async {
    await showActions(
      context,
      title: invoice.studentName,
      subtitle: '${invoice.periodLabel} · ${invoice.number}',
      actions: invoiceActions(context, ref, invoice, onChanged: _refresh),
    );
  }

  Future<void> _issue(Map<String, dynamic> summary) async {
    final pending = J.intOrNull(summary['pending']) ?? 0;
    final unpriced = J.intOrNull(summary['unpriced']) ?? 0;
    final label = J.s(summary['period_label']);

    final sure = await confirm(
      context,
      title: 'أصدِر فواتير $label؟',
      body: [
        'رح تنصدر $pending فاتورة.',
        if (unpriced > 0)
          'في $unpriced طفل بلا رسوم محدّدة — ما رح تنصدرلهم فواتير. '
              'حدّد رسومهم من ملفاتهم إذا لازم.',
        'الإصدار مرّتين ما بيحاسب حدا مرّتين.',
      ].join('\n\n'),
      confirmLabel: 'أصدِر',
    );
    if (!sure) return;

    setState(() => _issuing = true);

    try {
      final data = await ref.read(apiProvider).post('/billing/issue', body: {
        'period': J.s(summary['period']),
      });

      if (!mounted) return;
      final created = J.intOrNull(J.map(data)?['created']) ?? 0;
      showToast(context, created == 0 ? 'ما في إشي جديد ينصدر.' : 'انصدرت $created فاتورة.');
      await _refresh();
    } on ApiException catch (error) {
      if (mounted) showFailure(context, error);
    } finally {
      if (mounted) setState(() => _issuing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(billingSummaryProvider);
    final invoices = ref.watch(invoicesProvider(_filter));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('المالية')),
      body: RefreshList(
        onRefresh: _refresh,
        children: [
          summary.when(
            loading: () => const AppLoading(),
            error: (error, _) => AppError(
              error: error,
              onRetry: () => reload(ref, billingSummaryProvider.future),
            ),
            data: (data) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                StatGrid(
                  children: [
                    StatTile(
                      label: 'مستحقّ على الأهل',
                      value: Fmt.number(J.doubleOrNull(data['outstanding_total']) ?? 0),
                      caption: '${J.intOrNull(data['outstanding_count']) ?? 0} فاتورة',
                      tone: (J.doubleOrNull(data['outstanding_total']) ?? 0) > 0 ? 'bad' : 'good',
                    ),
                    StatTile(
                      label: 'انصدر هذا الشهر',
                      value: Fmt.number(J.doubleOrNull(data['issued_total']) ?? 0),
                      caption: '${J.intOrNull(data['issued']) ?? 0} فاتورة',
                    ),
                    StatTile(
                      label: 'لسه ما انصدر',
                      value: Fmt.number(J.doubleOrNull(data['pending_total']) ?? 0),
                      caption: '${J.intOrNull(data['pending']) ?? 0} طفل',
                      tone: 'warn',
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // The office's most useful warning: children the monthly run
                // will skip because nobody agreed a fee for them.
                if ((J.intOrNull(data['unpriced']) ?? 0) > 0)
                  NoteBox(
                    'في ${J.intOrNull(data['unpriced'])} طفل بلا رسوم محدّدة — '
                    'ما بينصدرلهم فواتير. حدّد الرسوم من ملف كل واحد.',
                    tone: 'warn',
                    icon: Icons.price_change_outlined,
                  ),

                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _issuing ? null : () => _issue(data),
                  icon: _issuing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Icon(Icons.receipt_long_rounded),
                  label: Text('أصدِر فواتير ${J.s(data['period_label'])}'),
                ),
              ],
            ),
          ),

          const SectionTitle('الفواتير'),

          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (value, label) in const [
                  ('outstanding', 'المستحقّة'),
                  ('paid', 'المدفوعة'),
                  ('overdue', 'المتأخّرة'),
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
          const SizedBox(height: 10),

          invoices.when(
            loading: () => const AppLoading(),
            error: (error, _) => AppError(
              error: error,
              onRetry: () => reload(ref, invoicesProvider(_filter).future),
            ),
            data: (list) {
              final shown = _status == 'outstanding'
                  ? list.where((invoice) => !invoice.settled).toList()
                  : list;

              if (shown.isEmpty) {
                return const NoteBox(
                  'ما في فواتير هون.',
                  tone: 'muted',
                  icon: Icons.receipt_long_outlined,
                );
              }

              return Column(
                children: [
                  for (final invoice in shown)
                    AppCard(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      onTap: () async {
                        await openInvoiceSheet(context, ref, invoice);
                        await _refresh();
                      },
                      onLongPress: () => _invoiceMenu(invoice),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(invoice.studentName, style: text.titleSmall),
                                Text(
                                  '${invoice.periodLabel} · ${invoice.number}',
                                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                Fmt.number(invoice.settled ? invoice.total : invoice.due),
                                style: text.titleSmall,
                              ),
                              ToneChip(
                                invoice.statusLabel,
                                tone: Labels.invoiceTone[invoice.status] ?? 'brand',
                              ),
                            ],
                          ),
                          RowMenu(onTap: () => _invoiceMenu(invoice)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
