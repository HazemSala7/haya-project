import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'office_data.dart';

/// A programme: which specialty, whose caseload, how often.
///
/// This is the row that decides everything downstream — who may open the
/// child's file, who the sessions belong to, which goals he is scored on. A
/// child with no programme is a child nobody is scheduled to see, which is
/// why the file screen says so in red rather than leaving a blank card.
///
/// Ending one is here too, and it is a status change rather than a delete:
/// a child who did speech, stopped, and came back has several ended rows, and
/// the old goals hang off them.
Future<Enrollment?> openEnrollmentForm(
  BuildContext context,
  WidgetRef ref, {
  required Student student,
  Enrollment? enrollment,
}) {
  return showFormSheet<Enrollment>(
    context,
    builder: (_) => _EnrollmentForm(student: student, enrollment: enrollment),
  );
}

class _EnrollmentForm extends ConsumerStatefulWidget {
  const _EnrollmentForm({required this.student, this.enrollment});

  final Student student;
  final Enrollment? enrollment;

  @override
  ConsumerState<_EnrollmentForm> createState() => _EnrollmentFormState();
}

class _EnrollmentFormState extends ConsumerState<_EnrollmentForm> {
  late final _plan = TextEditingController(text: widget.enrollment?.planSummary ?? '');

  late String? _specialty = widget.enrollment?.specialty;
  late int? _specialistId = widget.enrollment?.specialistId;
  late int _perWeek = widget.enrollment?.sessionsPerWeek ?? 2;
  late int _minutes = widget.enrollment?.sessionMinutes ?? 45;
  late String _status = widget.enrollment?.status ?? 'active';
  late DateTime? _startedAt =
      DateTime.tryParse(widget.enrollment?.startedAt ?? '') ?? DateTime.now();

  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  bool get _editing => widget.enrollment != null;

  @override
  void dispose() {
    _plan.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_specialty == null || _startedAt == null) {
      setState(() => _error = 'التخصص وتاريخ البداية مطلوبين.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });

    final body = <String, Object?>{
      'student_id': widget.student.id,
      'specialty': _specialty,
      'specialist_id': _specialistId,
      'sessions_per_week': _perWeek,
      'session_minutes': _minutes,
      'started_at': Fmt.isoDate(_startedAt!),
      'plan_summary': nullIfEmpty(_plan),
      if (_editing) 'status': _status,
    };

    try {
      final api = ref.read(apiProvider);
      final data = _editing
          ? await api.put('/enrollments/${widget.enrollment!.id}', body: body)
          : await api.post('/enrollments', body: body);

      if (!mounted) return;
      Navigator.of(context).pop(Enrollment.fromJson(J.map(data) ?? const {}));
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
        _fieldErrors = error.errors;
      });
    }
  }

  Future<void> _delete() async {
    final sure = await confirm(
      context,
      title: 'احذف البرنامج؟',
      // Said plainly, because the office is about to lose more than a row.
      body: 'بينحذف البرنامج وكل أهدافه وجلساته معه. إذا بس بدك توقفه، '
          'بدّل الحالة لـ«انتهى» وبيضلّ التاريخ محفوظ.',
      confirmLabel: 'احذف',
      danger: true,
    );
    if (!sure) return;

    setState(() => _busy = true);

    try {
      await ref.read(apiProvider).delete('/enrollments/${widget.enrollment!.id}');
      if (!mounted) return;
      Navigator.of(context).pop(widget.enrollment);
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
    final specialists = ref.watch(specialistsProvider);

    return FormSheet(
      title: _editing ? 'برنامج ${specialtyName(widget.enrollment!)}' : 'برنامج جديد',
      subtitle: widget.student.name,
      submitLabel: _editing ? 'احفظ' : 'افتح البرنامج',
      busy: _busy,
      error: _error,
      onSubmit: _submit,
      children: [
        ChoiceRow<String>(
          label: 'التخصص',
          required: true,
          selected: _specialty,
          options: [
            for (final entry in Labels.specialty.entries) (entry.key, entry.value),
          ],
          onSelected: (value) => setState(() => _specialty = value),
        ),

        /*
         * The specialist may be left empty on purpose: a child is enrolled the
         * day he arrives and assigned when the rota is worked out. Forcing a
         * name here produces a programme parked on whoever was first in the
         * list, which is worse than an empty one the office can see.
         */
        specialists.when(
          loading: () => const AppLoading(label: 'الأخصائيات…'),
          error: (error, _) => AppError(
            error: error,
            onRetry: () => reload(ref, specialistsProvider.future),
          ),
          data: (list) => ChoiceRow<int?>(
            label: 'الأخصائية',
            selected: _specialistId,
            options: [
              (null, 'بلا تعيين'),
              for (final account in list
                  .where((a) => _specialty == null || a.specialty == null || a.specialty == _specialty))
                (account.id, account.name),
            ],
            onSelected: (value) => setState(() => _specialistId = value),
          ),
        ),

        ChoiceRow<int>(
          label: 'جلسات بالأسبوع',
          selected: _perWeek,
          options: const [(1, '١'), (2, '٢'), (3, '٣'), (4, '٤'), (5, '٥')],
          onSelected: (value) => setState(() => _perWeek = value),
        ),
        ChoiceRow<int>(
          label: 'مدّة الجلسة',
          selected: _minutes,
          options: const [(30, '٣٠ د'), (45, '٤٥ د'), (60, 'ساعة'), (90, 'ساعة ونص')],
          onSelected: (value) => setState(() => _minutes = value),
        ),
        DateField(
          label: 'تاريخ البداية',
          value: _startedAt,
          required: true,
          error: _fieldErrors['started_at'],
          first: DateTime(2015),
          last: DateTime.now().add(const Duration(days: 365)),
          onChanged: (value) => setState(() => _startedAt = value),
        ),
        if (_editing)
          ChoiceRow<String>(
            label: 'الحالة',
            selected: _status,
            options: const [('active', 'شغّال'), ('paused', 'موقوف مؤقتاً'), ('ended', 'انتهى')],
            onSelected: (value) => setState(() => _status = value),
          ),
        AppTextField(
          controller: _plan,
          label: 'ملخّص الخطة',
          maxLines: 4,
          error: _fieldErrors['plan_summary'],
        ),
        if (_editing)
          TextButton.icon(
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded, color: AppColors.bad),
            label: const Text('احذف البرنامج', style: TextStyle(color: AppColors.bad)),
          ),
      ],
    );
  }
}
