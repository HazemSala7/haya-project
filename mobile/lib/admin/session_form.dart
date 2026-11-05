import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'office_data.dart';

/// Putting a session in the diary.
///
/// It hangs off a programme, not off a child: the programme is what carries
/// the specialty, the specialist and the default length, and the server copies
/// all three from it. Asking for them again here would be asking the office to
/// re-answer a question the file already answered — and to get it wrong.
Future<TherapySession?> openSessionForm(
  BuildContext context,
  WidgetRef ref, {
  Student? student,
  Enrollment? enrollment,
}) {
  return showFormSheet<TherapySession>(
    context,
    builder: (_) => _SessionForm(student: student, enrollment: enrollment),
  );
}

class _SessionForm extends ConsumerStatefulWidget {
  const _SessionForm({this.student, this.enrollment});

  final Student? student;
  final Enrollment? enrollment;

  @override
  ConsumerState<_SessionForm> createState() => _SessionFormState();
}

class _SessionFormState extends ConsumerState<_SessionForm> {
  late int? _enrollmentId = widget.enrollment?.id;
  late int? _specialistId = widget.enrollment?.specialistId;
  late int _minutes = widget.enrollment?.sessionMinutes ?? 45;

  DateTime _day = DateTime.now();
  TimeOfDay _time = const TimeOfDay(hour: 9, minute: 0);

  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (_enrollmentId == null) {
      setState(() => _error = 'اختر البرنامج.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final at = DateTime(_day.year, _day.month, _day.day, _time.hour, _time.minute);

    try {
      final data = await ref.read(apiProvider).post('/sessions', body: {
        'enrollment_id': _enrollmentId,
        // Local wall-clock converted the way the rest of the app does it —
        // the server runs in UTC and a raw local string lands three hours out.
        'scheduled_at': Fmt.toServerDateTime(at),
        'duration_minutes': _minutes,
        'specialist_id': _specialistId,
      });

      if (!mounted) return;
      Navigator.of(context).pop(TherapySession.fromJson(J.map(data) ?? const {}));
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
    // When a child was given, only his programmes; otherwise the live ones.
    final enrollments = ref.watch(
      enrollmentsProvider((studentId: widget.student?.id, status: 'active')),
    );
    final specialists = ref.watch(specialistsProvider);
    final text = Theme.of(context).textTheme;

    return FormSheet(
      title: 'جلسة جديدة',
      subtitle: widget.student?.name,
      submitLabel: 'اجدول',
      busy: _busy,
      error: _error,
      onSubmit: _submit,
      children: [
        if (widget.enrollment == null)
          enrollments.when(
            loading: () => const AppLoading(label: 'البرامج…'),
            error: (error, _) => AppError(
              error: error,
              onRetry: () => reload(
                ref,
                enrollmentsProvider((studentId: widget.student?.id, status: 'active')).future,
              ),
            ),
            data: (list) => list.isEmpty
                ? const NoteBox(
                    'ما في برامج شغّالة — افتح برنامج للطفل أولاً من ملفّه.',
                    tone: 'bad',
                    icon: Icons.error_outline_rounded,
                  )
                : ChoiceRow<int>(
                    label: 'البرنامج',
                    required: true,
                    selected: _enrollmentId,
                    options: [
                      for (final enrollment in list)
                        (
                          enrollment.id,
                          '${enrollment.student?.name ?? ''} — ${specialtyName(enrollment)}',
                        ),
                    ],
                    onSelected: (value) => setState(() {
                      _enrollmentId = value;
                      final picked = list.firstWhere((e) => e.id == value);
                      _specialistId = picked.specialistId;
                      _minutes = picked.sessionMinutes;
                    }),
                  ),
          )
        else
          AppCard(
            child: Row(
              children: [
                SpecialtyTag(widget.enrollment!.specialty),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.enrollment!.specialist?.name ?? 'بلا أخصائية',
                    style: text.bodySmall,
                  ),
                ),
              ],
            ),
          ),

        DateField(
          label: 'اليوم',
          value: _day,
          required: true,
          first: DateTime.now().subtract(const Duration(days: 30)),
          last: DateTime.now().add(const Duration(days: 365)),
          onChanged: (value) => setState(() => _day = value ?? _day),
        ),

        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const IconTile(Icons.schedule_rounded),
          title: const Text('الساعة'),
          subtitle: Text(_time.format(context)),
          trailing: const Icon(Icons.edit_outlined, size: 18),
          onTap: () async {
            final picked = await showTimePicker(context: context, initialTime: _time);
            if (picked != null) setState(() => _time = picked);
          },
        ),

        ChoiceRow<int>(
          label: 'المدّة',
          selected: _minutes,
          options: const [(30, '٣٠ د'), (45, '٤٥ د'), (60, 'ساعة'), (90, 'ساعة ونص')],
          onSelected: (value) => setState(() => _minutes = value),
        ),

        /*
         * Overriding the specialist is for the real case the office deals with
         * weekly: somebody is away and a colleague takes the session. The
         * programme keeps its own specialist; only this one session moves.
         */
        specialists.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (list) => ChoiceRow<int?>(
            label: 'الأخصائية لهذه الجلسة',
            selected: _specialistId,
            options: [
              (null, 'حسب البرنامج'),
              for (final account in list) (account.id, account.name),
            ],
            onSelected: (value) => setState(() => _specialistId = value),
          ),
        ),
      ],
    );
  }
}
