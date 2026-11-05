import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/// Opening a child's file, and editing it afterwards.
///
/// Every field `StudentController` accepts is here. A form that offers eight
/// of fourteen columns is a form the office works around — the missing six
/// get written into `notes`, and then nothing can be searched or reported on.
///
/// Resolves to the saved child, or null when the sheet was dismissed.
Future<Student?> openStudentForm(BuildContext context, WidgetRef ref, {Student? student}) {
  return showFormSheet<Student>(
    context,
    builder: (_) => _StudentForm(student: student),
  );
}

class _StudentForm extends ConsumerStatefulWidget {
  const _StudentForm({this.student});

  final Student? student;

  @override
  ConsumerState<_StudentForm> createState() => _StudentFormState();
}

class _StudentFormState extends ConsumerState<_StudentForm> {
  late final _name = TextEditingController(text: widget.student?.name ?? '');
  late final _fileNumber = TextEditingController(text: widget.student?.fileNumber ?? '');
  late final _nationalId = TextEditingController(text: widget.student?.nationalId ?? '');
  late final _diagnosis = TextEditingController(text: widget.student?.diagnosis ?? '');
  late final _diagnosisNotes = TextEditingController(text: widget.student?.diagnosisNotes ?? '');
  late final _medicalAlert = TextEditingController(text: widget.student?.medicalAlert ?? '');
  late final _school = TextEditingController(text: widget.student?.school ?? '');
  late final _grade = TextEditingController(text: widget.student?.grade ?? '');
  late final _notes = TextEditingController(text: widget.student?.notes ?? '');

  late String? _gender = widget.student?.gender;
  late String _status = widget.student?.status ?? 'active';
  late DateTime? _birthDate = _parse(widget.student?.birthDate);
  late DateTime? _enrolledAt = _parse(widget.student?.enrolledAt) ?? DateTime.now();
  late DateTime? _leftAt = _parse(widget.student?.leftAt);

  bool _busy = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};

  static DateTime? _parse(String? value) =>
      value == null ? null : DateTime.tryParse(value);

  bool get _editing => widget.student != null;

  @override
  void dispose() {
    for (final controller in [
      _name, _fileNumber, _nationalId, _diagnosis, _diagnosisNotes,
      _medicalAlert, _school, _grade, _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();

    // Checked here so the person is not made to wait for a round trip to be
    // told a thing the form already knew.
    if (name.isEmpty || _birthDate == null || _gender == null || _enrolledAt == null) {
      setState(() => _error = 'الاسم وتاريخ الميلاد والجنس وتاريخ الالتحاق مطلوبة.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });

    final body = <String, Object?>{
      'name': name,
      'birth_date': Fmt.isoDate(_birthDate!),
      'gender': _gender,
      'enrolled_at': Fmt.isoDate(_enrolledAt!),
      'status': _status,
      'national_id': nullIfEmpty(_nationalId),
      'diagnosis': nullIfEmpty(_diagnosis),
      'diagnosis_notes': nullIfEmpty(_diagnosisNotes),
      'medical_alert': nullIfEmpty(_medicalAlert),
      'school': nullIfEmpty(_school),
      'grade': nullIfEmpty(_grade),
      'notes': nullIfEmpty(_notes),
      'left_at': _leftAt == null ? null : Fmt.isoDate(_leftAt!),
      // Server-generated on create; editable afterwards because the office
      // sometimes has to match a number already written on a paper file.
      if (_editing || _fileNumber.text.trim().isNotEmpty) 'file_number': nullIfEmpty(_fileNumber),
    };

    try {
      final api = ref.read(apiProvider);
      final data = _editing
          ? await api.put('/students/${widget.student!.id}', body: body)
          : await api.post('/students', body: body);

      final saved = Student.fromJson(J.map(data) ?? const {});

      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.message;
        _fieldErrors = error.errors;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return FormSheet(
      title: _editing ? 'تعديل ملف ${widget.student!.name}' : 'طالب جديد',
      subtitle: _editing ? 'الملف #${widget.student!.fileNumber}' : 'افتح ملفاً جديداً',
      submitLabel: _editing ? 'احفظ' : 'افتح الملف',
      busy: _busy,
      error: _error,
      onSubmit: _submit,
      children: [
        AppTextField(
          controller: _name,
          label: 'الاسم',
          required: true,
          error: _fieldErrors['name'],
          textInputAction: TextInputAction.next,
        ),
        DateField(
          label: 'تاريخ الميلاد',
          value: _birthDate,
          required: true,
          error: _fieldErrors['birth_date'],
          first: DateTime(1990),
          last: DateTime.now(),
          onChanged: (value) => setState(() => _birthDate = value),
        ),
        ChoiceRow<String>(
          label: 'الجنس',
          required: true,
          selected: _gender,
          options: const [('male', 'ذكر'), ('female', 'أنثى')],
          onSelected: (value) => setState(() => _gender = value),
        ),
        DateField(
          label: 'تاريخ الالتحاق',
          value: _enrolledAt,
          required: true,
          error: _fieldErrors['enrolled_at'],
          first: DateTime(2015),
          last: DateTime.now().add(const Duration(days: 365)),
          onChanged: (value) => setState(() => _enrolledAt = value),
        ),
        ChoiceRow<String>(
          label: 'الحالة',
          selected: _status,
          options: const [
            ('active', 'نشط'),
            ('paused', 'موقوف مؤقتاً'),
            ('graduated', 'تخرّج'),
            ('withdrawn', 'انسحب'),
          ],
          onSelected: (value) => setState(() => _status = value),
        ),
        if (_status == 'graduated' || _status == 'withdrawn')
          DateField(
            label: 'تاريخ المغادرة',
            value: _leftAt,
            clearable: true,
            first: DateTime(2015),
            last: DateTime.now(),
            onChanged: (value) => setState(() => _leftAt = value),
          ),

        /*
         * The red band. Separate from `notes` on purpose — mixing "بحب
         * القطارات" into the same box as "عنده صرع" means the second gets
         * skimmed at the speed of the first, and the day it matters is a day
         * nobody was expecting.
         */
        AppTextField(
          controller: _medicalAlert,
          label: 'تنبيه طبي',
          help: 'حساسية، دواء، تاريخ تشنّجات — بيظهر فوق كل شاشة عن الطفل.',
          maxLines: 3,
          error: _fieldErrors['medical_alert'],
        ),

        AppTextField(
          controller: _diagnosis,
          label: 'التشخيص',
          error: _fieldErrors['diagnosis'],
        ),
        AppTextField(
          controller: _diagnosisNotes,
          label: 'تفاصيل التشخيص',
          maxLines: 4,
          error: _fieldErrors['diagnosis_notes'],
        ),
        AppTextField(
          controller: _school,
          label: 'المدرسة',
          error: _fieldErrors['school'],
        ),
        AppTextField(
          controller: _grade,
          label: 'الصف',
          error: _fieldErrors['grade'],
        ),
        AppTextField(
          controller: _nationalId,
          label: 'رقم الهوية',
          ltr: true,
          keyboardType: TextInputType.number,
          error: _fieldErrors['national_id'],
        ),
        if (_editing)
          AppTextField(
            controller: _fileNumber,
            label: 'رقم الملف',
            help: 'بيتولّد لحاله. عدّله بس إذا لازم يطابق ملفاً ورقياً.',
            ltr: true,
            error: _fieldErrors['file_number'],
          ),
        AppTextField(
          controller: _notes,
          label: 'ملاحظات',
          maxLines: 4,
          error: _fieldErrors['notes'],
        ),
      ],
    );
  }
}
