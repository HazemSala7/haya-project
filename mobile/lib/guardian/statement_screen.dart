import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../admin/office_data.dart' show studentBillingProvider;
import '../core/core.dart';

/// كشف الحساب — what a family owes, what it has paid, and for which month.
///
/// The server has always been willing to tell her: `GET /billing/students/
/// {id}` lets a guardian read her own child's account (and refuses a
/// specialist outright). Nothing in the app asked, so a parent could read
/// every report about her son and had no way to see a single invoice — and
/// the office was answering "شو علينا هالشهر؟" on the phone.
///
/// Read-only, deliberately: every write on this endpoint is the office's, and
/// the parent's copy must be the academy's own figures rather than a second
/// place where money can be edited.
class StatementScreen extends ConsumerWidget {
  const StatementScreen({super.key, required this.studentId, required this.studentName});

  final int studentId;
  final String studentName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(studentBillingProvider(studentId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('كشف الحساب'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(22),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 16, bottom: 10),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(studentName, style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        ),
      ),
      body: AsyncView<StudentAccount>(
        value: account,
        onRetry: () => reload(ref, studentBillingProvider(studentId).future),
        data: (data) => RefreshList(
          onRefresh: () => reload(ref, studentBillingProvider(studentId).future),
          children: [
            _Balance(account: data),

            const SizedBox(height: 4),
            SectionTitle('الفواتير', count: data.invoices.isEmpty ? null : data.invoices.length),

            if (data.invoices.isEmpty)
              const NoteBox(
                'ما في فواتير على الملف بعد.',
                tone: 'muted',
                icon: Icons.receipt_long_outlined,
              )
            else
              for (final (i, invoice) in data.invoices.indexed)
                Reveal.at(
                  i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InvoiceCard(invoice: invoice),
                  ),
                ),

            const SizedBox(height: 14),
            const NoteBox(
              'الأرقام هون هي نفسها الي عند الإدارة. لأي استفسار عن الحساب احكوا معهم.',
              tone: 'muted',
            ),
          ],
        ),
      ),
    );
  }
}

/// The one number she opened the screen for, and the two behind it.
class _Balance extends StatelessWidget {
  const _Balance({required this.account});

  final StudentAccount account;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final owing = account.due > 0;

    return Reveal(
      child: AppCard(
        color: owing ? AppColors.badSoft : AppColors.goodSoft,
        border: Border.all(
          color: (owing ? AppColors.bad : AppColors.good).withValues(alpha: 0.25),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              owing ? 'المتبقّي عليكم' : 'الحساب مسدّد',
              style: text.labelMedium?.copyWith(
                color: owing ? AppColors.bad : AppColors.good,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                CountUp(
                  account.due,
                  style: text.displaySmall?.copyWith(
                    color: owing ? AppColors.bad : AppColors.good,
                    height: 1.2,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  '₪',
                  style: text.titleMedium?.copyWith(color: owing ? AppColors.bad : AppColors.good),
                ),
              ],
            ),
            if (account.overdue > 0)
              Text(
                '${Fmt.number(account.overdue)} ${account.overdue == 1 ? 'فاتورة متأخّرة' : 'فواتير متأخّرة'}',
                style: text.bodySmall?.copyWith(color: AppColors.bad),
              ),

            const Divider(height: 20),

            Row(
              children: [
                Expanded(child: _Figure(label: 'المدفوع', value: account.paid, tone: 'good')),
                Expanded(child: _Figure(label: 'المفوتر', value: account.billed, tone: 'muted')),
                Expanded(
                  child: _Figure(
                    label: 'الرسوم بالشهر',
                    value: account.monthlyFee,
                    tone: 'muted',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, required this.tone});

  final String label;
  final double? value;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        Text(
          value == null ? '—' : '${Fmt.number(value)} ₪',
          style: text.titleSmall?.copyWith(color: AppColors.byName(tone)),
        ),
        Text(label, style: text.labelSmall, textAlign: TextAlign.center),
      ],
    );
  }
}

/// One month: what it cost, what came in against it, and when.
class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.invoice});

  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(invoice.periodLabel, style: text.titleSmall),
                    Text(
                      'فاتورة ${invoice.number}'
                      '${invoice.dueOn == null ? '' : ' · الاستحقاق ${Fmt.date(invoice.dueOn)}'}',
                      style: text.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${Fmt.number(invoice.total)} ₪', style: text.titleSmall),
                  ToneChip(
                    invoice.statusLabel,
                    tone: Labels.invoiceTone[invoice.status] ?? 'brand',
                  ),
                ],
              ),
            ],
          ),

          // What is still on this month, when it is not all of it.
          if (invoice.due > 0 && invoice.paid > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'مدفوع ${Fmt.number(invoice.paid)} ₪ · متبقّي ${Fmt.number(invoice.due)} ₪',
                style: text.bodySmall?.copyWith(color: AppColors.warn),
              ),
            ),

          // The receipts, so a family can match what it handed over with what
          // the academy recorded — the whole point of a statement.
          if (invoice.payments.isNotEmpty) ...[
            const Divider(height: 18),
            for (final payment in invoice.payments)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, size: 15, color: AppColors.good),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${Fmt.date(payment.paidOn)} · ${Labels.payMethod[payment.method] ?? payment.method}'
                        '${payment.receiptNo.isEmpty ? '' : ' · وصل ${payment.receiptNo}'}',
                        style: text.bodySmall,
                      ),
                    ),
                    Text('${Fmt.number(payment.amount)} ₪', style: text.labelLarge),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
