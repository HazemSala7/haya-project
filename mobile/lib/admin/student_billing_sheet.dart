import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'office_data.dart';

/// The agreed monthly fee, on its own.
///
/// Separate from the student form because it is changed on its own schedule —
/// a fee is renegotiated in March without anybody touching the diagnosis — and
/// because the API gives it its own endpoint for the same reason.
Future<void> openFeeSheet(BuildContext context, WidgetRef ref, Student student) async {
  await showFormSheet<void>(
    context,
    builder: (_) => _FeeSheet(student: student),
  );
}

class _FeeSheet extends ConsumerStatefulWidget {
  const _FeeSheet({required this.student});

  final Student student;

  @override
  ConsumerState<_FeeSheet> createState() => _FeeSheetState();
}

class _FeeSheetState extends ConsumerState<_FeeSheet> {
  /// Opened on what the child is paying now.
  ///
  /// It used to open empty whatever the fee was, and the field means "this
  /// is the fee" rather than "change it by" — so an office that opened the
  /// sheet to look, and saved, wiped a fee it never meant to touch.
  late final _fee = TextEditingController(
    text: widget.student.monthlyFee == null ? '' : widget.student.monthlyFee!.toStringAsFixed(0),
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _fee.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final typed = _fee.text.trim();

    try {
      await ref.read(apiProvider).put('/students/${widget.student.id}/fee', body: {
        // `present, nullable` on the server: an empty box means "no fee", not
        // "leave it alone". Sending null is the whole point of the field.
        'monthly_fee': typed.isEmpty ? null : num.tryParse(typed),
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      showToast(context, 'انحفظت الرسوم.');
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
      title: 'الرسوم الشهرية',
      subtitle: widget.student.name,
      submitLabel: 'احفظ',
      busy: _busy,
      error: _error,
      onSubmit: _submit,
      children: [
        AppTextField(
          controller: _fee,
          label: 'الرسوم بالشيكل',
          help: 'اتركه فاضي إذا الطفل بلا رسوم — صفر وفاضي نفس الإشي.',
          ltr: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        const NoteBox(
          'الرسوم بتنطبّق على الفواتير الجاي إصدارها. الفواتير المصدَّرة ما بتتغيّر لحالها.',
          tone: 'muted',
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }
}

/// One child's account: what he owes, and every invoice on it.
Future<void> openStudentBilling(BuildContext context, WidgetRef ref, Student student) async {
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => StudentBillingScreen(student: student)),
  );
}

class StudentBillingScreen extends ConsumerWidget {
  const StudentBillingScreen({super.key, required this.student});

  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(studentBillingProvider(student.id));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('حساب ${student.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.payments_outlined),
            tooltip: 'الرسوم الشهرية',
            onPressed: () => openFeeSheet(context, ref, student),
          ),
        ],
      ),
      body: AsyncView<StudentAccount>(
        value: account,
        onRetry: () => reload(ref, studentBillingProvider(student.id).future),
        data: (data) {
          final invoices = data.invoices;

          return RefreshList(
            onRefresh: () => reload(ref, studentBillingProvider(student.id).future),
            children: [
              StatGrid(
                children: [
                  StatTile(
                    label: 'المستحقّ',
                    value: Fmt.number(data.due),
                    suffix: ' ₪',
                    icon: Icons.account_balance_wallet_outlined,
                    tone: data.due > 0 ? 'bad' : 'good',
                    caption: data.overdue > 0 ? '${data.overdue} فاتورة متأخّرة' : null,
                  ),
                  StatTile(
                    label: 'المدفوع',
                    value: Fmt.number(data.paid),
                    suffix: ' ₪',
                    icon: Icons.check_circle_outline_rounded,
                    tone: 'good',
                    caption: 'من ${Fmt.number(data.billed)} ₪ مفوترة',
                  ),
                  StatTile(
                    label: 'الرسوم الشهرية',
                    value: data.monthlyFee == null ? '—' : Fmt.number(data.monthlyFee),
                    suffix: data.monthlyFee == null ? '' : ' ₪',
                    icon: Icons.payments_outlined,
                    tone: data.monthlyFee == null ? 'warn' : 'brand',
                    caption: data.monthlyFee == null ? 'اضغط لتحطّها' : null,
                    onTap: () => openFeeSheet(context, ref, student),
                  ),
                ],
              ),
              const SectionTitle('الفواتير'),
              if (invoices.isEmpty)
                const NoteBox(
                  'ما في فواتير على هذا الملف بعد.',
                  tone: 'muted',
                  icon: Icons.receipt_long_outlined,
                )
              else
                for (final invoice in invoices)
                  AppCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    onTap: () => openInvoiceSheet(context, ref, invoice),
                    onLongPress: () => _invoiceMenu(context, ref, invoice, student.id),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(invoice.periodLabel, style: text.titleSmall),
                              Text(
                                'فاتورة ${invoice.number}',
                                style: text.bodySmall?.copyWith(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(Fmt.number(invoice.total), style: text.titleSmall),
                            ToneChip(
                              invoice.statusLabel,
                              tone: switch (invoice.status) {
                                'paid' => 'good',
                                'partial' => 'warn',
                                'overdue' => 'bad',
                                'void' => 'muted',
                                _ => 'brand',
                              },
                            ),
                          ],
                        ),
                        RowMenu(onTap: () => _invoiceMenu(context, ref, invoice, student.id)),
                      ],
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

/// The ⋮ on an invoice row, wherever that row is.
Future<void> _invoiceMenu(BuildContext context, WidgetRef ref, Invoice invoice, int studentId) {
  return showActions(
    context,
    title: 'فاتورة ${invoice.number}',
    subtitle: invoice.periodLabel,
    actions: invoiceActions(
      context,
      ref,
      invoice,
      onChanged: () => ref.invalidate(studentBillingProvider(studentId)),
    ),
  );
}

/* ------------------------------------------------------ one invoice */

/// Everything the office may do to one invoice, from the row it sits on.
///
/// The sheet behind a tap takes money; these are the two things it could not
/// do — correct a figure that was wrong when it was issued, and throw away an
/// invoice that should never have existed. Both are the server's rules: it
/// refuses a total below what has already been paid, and refuses to delete an
/// invoice with payments on it. The reasons are shown here before the tap.
List<SheetAction> invoiceActions(
  BuildContext context,
  WidgetRef ref,
  Invoice invoice, {
  required VoidCallback onChanged,
}) {
  return [
    SheetAction(
      label: invoice.settled ? 'افتح الفاتورة' : 'اقبض',
      icon: invoice.settled ? Icons.receipt_long_rounded : Icons.payments_rounded,
      tone: 'good',
      onTap: () async {
        await openInvoiceSheet(context, ref, invoice);
        onChanged();
      },
    ),
    SheetAction(
      label: 'عدّل الفاتورة',
      icon: Icons.edit_outlined,
      hint: 'القيمة، الخصم، الاستحقاق',
      onTap: () async {
        final saved = await openInvoiceEdit(context, ref, invoice);
        if (saved) onChanged();
      },
    ),
    SheetAction(
      label: 'احذف الفاتورة',
      icon: Icons.delete_outline_rounded,
      tone: 'bad',
      disabledReason: invoice.payments.isNotEmpty || invoice.paid > 0
          ? 'عليها دفعات مسجّلة — احذف الدفعات أول.'
          : null,
      onTap: () async {
        final sure = await confirm(
          context,
          title: 'احذف فاتورة ${invoice.number}؟',
          body: '${invoice.studentName} · ${invoice.periodLabel}. '
              'بتنشال خالص، ومحلّها بيضلّ فاضي بالشهر هذا.',
          confirmLabel: 'احذف',
          danger: true,
        );
        if (!sure || !context.mounted) return;

        try {
          await ref.read(apiProvider).delete('/billing/invoices/${invoice.id}');
          ref.invalidate(studentBillingProvider(invoice.studentId));
          ref.invalidate(billingSummaryProvider);
          onChanged();
          if (context.mounted) showToast(context, 'انحذفت الفاتورة.');
        } on ApiException catch (error) {
          if (context.mounted) showFailure(context, error);
        }
      },
    ),
  ];
}

/// Correcting an invoice that was issued wrong. Resolves to true when saved.
Future<bool> openInvoiceEdit(BuildContext context, WidgetRef ref, Invoice invoice) async {
  final done = await showFormSheet<bool>(
    context,
    builder: (_) => _InvoiceEdit(invoice: invoice),
  );
  return done == true;
}

class _InvoiceEdit extends ConsumerStatefulWidget {
  const _InvoiceEdit({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_InvoiceEdit> createState() => _InvoiceEditState();
}

class _InvoiceEditState extends ConsumerState<_InvoiceEdit> {
  late final _amount = TextEditingController(text: widget.invoice.amount.toStringAsFixed(0));
  late final _discount = TextEditingController(
    text: widget.invoice.discount == 0 ? '' : widget.invoice.discount.toStringAsFixed(0),
  );
  late final _note = TextEditingController(text: widget.invoice.note ?? '');
  late DateTime _dueOn = Fmt.at(widget.invoice.dueOn) ?? DateTime.now();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _discount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = num.tryParse(_amount.text.trim());
    if (amount == null || amount < 0) {
      setState(() => _error = 'اكتب قيمة صحيحة.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(apiProvider).put('/billing/invoices/${widget.invoice.id}', body: {
        'amount': amount,
        'discount': num.tryParse(_discount.text.trim()) ?? 0,
        'due_on': Fmt.isoDate(_dueOn),
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });

      ref.invalidate(studentBillingProvider(widget.invoice.studentId));
      ref.invalidate(billingSummaryProvider);

      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(context, 'انحفظت الفاتورة.');
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
    final paid = widget.invoice.paid;

    return FormSheet(
      title: 'تعديل فاتورة ${widget.invoice.number}',
      subtitle: '${widget.invoice.studentName} · ${widget.invoice.periodLabel}',
      submitLabel: 'احفظ',
      busy: _busy,
      error: _error,
      onSubmit: _save,
      children: [
        // The one rule a person can walk into here, said before they do.
        if (paid > 0)
          NoteBox(
            'انقبض على هالفاتورة ${Fmt.number(paid)}. الإجمالي الجديد ما بصير أقلّ من هيك.',
            tone: 'warn',
            icon: Icons.payments_outlined,
          ),
        AppTextField(
          controller: _amount,
          label: 'القيمة',
          ltr: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        AppTextField(
          controller: _discount,
          label: 'الخصم',
          ltr: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
        ),
        DateField(
          label: 'تاريخ الاستحقاق',
          value: _dueOn,
          required: true,
          onChanged: (value) => setState(() => _dueOn = value ?? _dueOn),
        ),
        AppTextField(controller: _note, label: 'ملاحظة', maxLines: 2),
      ],
    );
  }
}

/// One invoice: what it is for, what came in against it, and taking money.
Future<void> openInvoiceSheet(BuildContext context, WidgetRef ref, Invoice invoice) async {
  await showFormSheet<void>(
    context,
    builder: (_) => _InvoiceSheet(invoice: invoice),
  );
}

class _InvoiceSheet extends ConsumerStatefulWidget {
  const _InvoiceSheet({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_InvoiceSheet> createState() => _InvoiceSheetState();
}

class _InvoiceSheetState extends ConsumerState<_InvoiceSheet> {
  late final _amount = TextEditingController(
    // Pre-filled with what is owed: the overwhelmingly common case is a
    // family paying the whole month, and retyping it is three taps for
    // nothing.
    text: widget.invoice.due <= 0 ? '' : widget.invoice.due.toStringAsFixed(0),
  );
  final _reference = TextEditingController();

  String _method = 'cash';
  DateTime _paidOn = DateTime.now();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _reference.dispose();
    super.dispose();
  }

  Future<void> _pay() async {
    final amount = num.tryParse(_amount.text.trim());

    if (amount == null || amount <= 0) {
      setState(() => _error = 'اكتب مبلغاً أكبر من صفر.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(apiProvider).post('/billing/invoices/${widget.invoice.id}/pay', body: {
        'amount': amount,
        'method': _method,
        'paid_on': Fmt.isoDate(_paidOn),
        'reference': nullIfEmpty(_reference),
      });

      if (!mounted) return;
      ref.invalidate(studentBillingProvider(widget.invoice.studentId));
      ref.invalidate(billingSummaryProvider);
      Navigator.of(context).pop();
      showToast(context, 'انقبض المبلغ.');
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
    final invoice = widget.invoice;
    final text = Theme.of(context).textTheme;
    final settled = invoice.due <= 0;

    return FormSheet(
      title: 'فاتورة ${invoice.number}',
      subtitle: '${invoice.studentName} · ${invoice.periodLabel}',
      submitLabel: settled ? 'تمام' : 'اقبض',
      busy: _busy,
      error: _error,
      onSubmit: settled ? () => Navigator.of(context).pop() : _pay,
      children: [
        AppCard(
          child: Column(
            children: [
              InfoRow(label: 'القيمة', value: Fmt.number(invoice.amount)),
              if (invoice.discount > 0)
                InfoRow(label: 'الخصم', value: Fmt.number(invoice.discount)),
              InfoRow(label: 'الإجمالي', value: Fmt.number(invoice.total)),
              InfoRow(label: 'المدفوع', value: Fmt.number(invoice.paid)),
              InfoRow(label: 'المتبقّي', value: Fmt.number(invoice.due)),
              if (invoice.dueOn != null)
                InfoRow(label: 'الاستحقاق', value: Fmt.date(invoice.dueOn)),
            ],
          ),
        ),

        if (invoice.payments.isNotEmpty) ...[
          const SectionTitle('الدفعات'),
          for (final payment in invoice.payments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const IconTile(Icons.check_rounded, tone: 'good'),
              title: Text(Fmt.number(payment.amount), style: text.titleSmall),
              subtitle: Text(
                '${Fmt.date(payment.paidOn)} · ${Labels.payMethod[payment.method] ?? payment.method}',
                style: text.bodySmall,
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded, color: AppColors.bad),
                tooltip: 'احذف الدفعة',
                onPressed: () async {
                  final sure = await confirm(
                    context,
                    title: 'احذف دفعة ${Fmt.number(payment.amount)}؟',
                    body: 'بترجع الفاتورة مستحقّة بنفس المبلغ.',
                    confirmLabel: 'احذف',
                    danger: true,
                  );
                  if (!sure) return;

                  try {
                    await ref.read(apiProvider).delete('/billing/payments/${payment.id}');
                    if (!context.mounted) return;
                    ref.invalidate(studentBillingProvider(invoice.studentId));
                    ref.invalidate(billingSummaryProvider);
                    Navigator.of(context).pop();
                    showToast(context, 'انحذفت الدفعة.');
                  } on ApiException catch (error) {
                    if (context.mounted) showFailure(context, error);
                  }
                },
              ),
            ),
        ],

        if (!settled) ...[
          const SectionTitle('اقبض'),
          AppTextField(
            controller: _amount,
            label: 'المبلغ',
            ltr: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          ChoiceRow<String>(
            label: 'الطريقة',
            selected: _method,
            options: [for (final e in Labels.payMethod.entries) (e.key, e.value)],
            onSelected: (value) => setState(() => _method = value),
          ),
          DateField(
            label: 'تاريخ الدفع',
            value: _paidOn,
            first: DateTime(2020),
            last: DateTime.now(),
            onChanged: (value) => setState(() => _paidOn = value ?? DateTime.now()),
          ),
          AppTextField(
            controller: _reference,
            label: 'مرجع',
            help: 'رقم حوالة أو شيك — اختياري.',
            ltr: true,
          ),
        ],
      ],
    );
  }
}
