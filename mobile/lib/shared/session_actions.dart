import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../specialist/session_report_screen.dart';

/*
 * What can be done to one session, from the row it sits on.
 *
 * Shared by the office's list and the specialist's, because they are the same
 * five things done by two people — and because a sheet that offers «احذف» in
 * one place and hides it in the other teaches nobody anything.
 *
 * Rescheduling is not here: the server has no route for it. `PUT /sessions/
 * {id}` writes the report, and `scheduled_at` is only ever read from `store`.
 * Moving a session to another hour means deleting it and booking it again —
 * which is what the office does today, and what the delete below is for.
 */

/// The actions, for a row menu.
List<SheetAction> sessionActions(
  BuildContext context,
  WidgetRef ref,
  TherapySession session, {
  required VoidCallback onChanged,
}) {
  final published = session.reportStatus == 'published';

  return [
    SheetAction(
      label: published ? 'اقرأ التقرير' : 'اكتب التقرير',
      icon: Icons.description_outlined,
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SessionReportScreen(
            sessionId: session.id,
            studentName: session.student?.name ?? '',
          ),
        ));
        onChanged();
      },
    ),
    SheetAction(
      label: 'علّم الحضور',
      icon: Icons.how_to_reg_rounded,
      tone: 'good',
      hint: 'تمّت، ما إجا، بعذر، ملغية',
      // The server refuses to move a published report off «تمّت», and says so
      // in its own words; this says it before the tap rather than after.
      disabledReason: published ? 'التقرير انبعت — الحضور ما بينغيّر بعده.' : null,
      onTap: () => openAttendanceSheet(context, ref, session, onChanged: onChanged),
    ),
    SheetAction(
      label: 'احذف الجلسة',
      icon: Icons.delete_outline_rounded,
      tone: 'bad',
      disabledReason: published ? 'التقرير انبعت للأهل — بينضاف عليه تصحيح ولا بينحذف.' : null,
      onTap: () async {
        final sure = await confirm(
          context,
          title: 'احذف جلسة ${session.student?.name ?? ''}؟',
          body: 'جلسة ${Fmt.dateTime(session.scheduledAt)} بتنشال من الجدول. '
              'إذا كان إلها مسوّدة تقرير بتروح معها.',
          confirmLabel: 'احذف',
          danger: true,
        );
        if (!sure || !context.mounted) return;

        try {
          await ref.read(apiProvider).delete('/sessions/${session.id}');
          onChanged();
          if (context.mounted) showToast(context, 'انحذفت الجلسة.');
        } on ApiException catch (error) {
          if (context.mounted) showFailure(context, error);
        }
      },
    ),
  ];
}

/// Marking the diary: who came, who did not, and why.
///
/// The app could only ever say «تمّت» — from inside the report screen — so a
/// child who did not turn up stayed «مجدولة» for ever, and the absence that
/// the whole attendance figure is built on was never recorded by anybody.
Future<void> openAttendanceSheet(
  BuildContext context,
  WidgetRef ref,
  TherapySession session, {
  required VoidCallback onChanged,
}) async {
  final done = await showFormSheet<bool>(
    context,
    builder: (_) => _AttendanceSheet(session: session),
  );

  if (done == true) onChanged();
}

class _AttendanceSheet extends ConsumerStatefulWidget {
  const _AttendanceSheet({required this.session});

  final TherapySession session;

  @override
  ConsumerState<_AttendanceSheet> createState() => _AttendanceSheetState();
}

class _AttendanceSheetState extends ConsumerState<_AttendanceSheet> {
  late String _status = widget.session.status;
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  /// The two states that are not «he came» want a word about why — it is what
  /// the office reads back to the family at the end of the month.
  bool get _wantsReason => _status == 'absent' || _status == 'excused' || _status == 'cancelled';

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(apiProvider).post('/sessions/${widget.session.id}/attendance', body: {
        'status': _status,
        if (_wantsReason && _reason.text.trim().isNotEmpty) 'absence_reason': _reason.text.trim(),
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
      showToast(context, 'انسجّل الحضور.');
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
      title: 'حضور الجلسة',
      subtitle: '${widget.session.student?.name ?? ''} · ${Fmt.dateTime(widget.session.scheduledAt)}',
      submitLabel: 'احفظ',
      busy: _busy,
      error: _error,
      onSubmit: _save,
      children: [
        ChoiceRow<String>(
          label: 'شو صار',
          required: true,
          selected: _status,
          options: const [
            ('scheduled', 'مجدولة'),
            ('held', 'تمّت'),
            ('absent', 'ما إجا'),
            ('excused', 'بعذر'),
            ('cancelled', 'ملغية'),
          ],
          onSelected: (value) => setState(() => _status = value),
        ),
        if (_wantsReason)
          AppTextField(
            controller: _reason,
            label: 'السبب',
            hint: 'مريض، سفر، ما وصلت المواصلة…',
            maxLines: 2,
          ),
      ],
    );
  }
}
