import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'student_billing_sheet.dart';
import 'student_form.dart';
import 'student_office_screen.dart';

/// Every child in the building — the office's list, and the way in to a file.
///
/// This screen used to show three children written into the source: «محمد
/// أحمد / الملف ٠٠١» and two more, with `onTap: () {}`. It looked finished
/// and it was a drawing. The dashboard beside it read eight, which is the
/// kind of disagreement nobody notices until a parent asks why her child is
/// not listed.
///
/// So: the real list, searched on the server, filtered by status, and every
/// row opens the file. The archive is here too — a withdrawn child's file is
/// never destroyed, and a family that comes back after a year is found by
/// switching one chip rather than by phoning whoever remembers.
class AdminStudentsListScreen extends ConsumerStatefulWidget {
  const AdminStudentsListScreen({super.key});

  @override
  ConsumerState<AdminStudentsListScreen> createState() => _AdminStudentsListScreenState();
}

class _AdminStudentsListScreenState extends ConsumerState<AdminStudentsListScreen> {
  final _search = TextEditingController();
  final _list = GlobalKey<PagedListState<Student>>();

  String _status = 'active';
  String _query = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Typing "محمد" is four keystrokes and must not be four requests.
  void _onTyped(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  Future<void> _create() async {
    final student = await openStudentForm(context, ref);
    if (student == null || !mounted) return;

    showToast(context, 'انفتح ملف ${student.name}.');
    _list.currentState?.reload();
    await _open(student.id);
  }

  /// Everything the office may do to one child, from the row itself.
  ///
  /// The same list the file's own ⋮ carries, because a person who has
  /// learnt it there should not have to learn it again here — and because
  /// opening a file to change a fee is three taps that teach nothing.
  Future<void> _actions(Student student) async {
    final api = ref.read(apiProvider);

    Future<void> archive() async {
      final sure = await confirm(
        context,
        title: 'أرشفة ملف ${student.name}؟',
        // The honest description of what the server does: a soft delete.
        // Calling it «حذف» would make the office think the history is gone
        // and stop them doing it when they should.
        body: 'الملف بيروح للأرشيف ولا بينحذف. جلساته وتقاريره بيضلّوا، '
            'وبترجّعه بضغطة من فلتر «الأرشيف».',
        confirmLabel: 'أرشِف',
        danger: true,
      );
      if (!sure || !mounted) return;

      try {
        await api.delete('/students/${student.id}');
        if (!mounted) return;
        showToast(context, 'انأرشف ملف ${student.name}.');
        _list.currentState?.reload();
      } on ApiException catch (error) {
        if (mounted) showFailure(context, error);
      }
    }

    Future<void> restore() async {
      try {
        await api.post('/students/${student.id}/restore');
        if (!mounted) return;
        showToast(context, 'رجع ملف ${student.name}.');
        _list.currentState?.reload();
      } on ApiException catch (error) {
        if (mounted) showFailure(context, error);
      }
    }

    await showActions(
      context,
      title: student.name,
      subtitle: 'الملف #${student.fileNumber}',
      actions: [
        SheetAction(
          label: 'افتح الملف',
          icon: Icons.folder_open_rounded,
          onTap: () => _open(student.id),
        ),
        SheetAction(
          label: 'عدّل الملف',
          icon: Icons.edit_outlined,
          hint: 'الاسم، الميلاد، التشخيص، التنبيه الطبي',
          onTap: () async {
            final saved = await openStudentForm(context, ref, student: student);
            if (saved == null || !mounted) return;
            showToast(context, 'انحفظ الملف.');
            _list.currentState?.reload();
          },
        ),
        SheetAction(
          label: 'الرسوم الشهرية',
          icon: Icons.payments_outlined,
          tone: 'good',
          onTap: () => openFeeSheet(context, ref, student),
        ),
        if (student.archived)
          SheetAction(
            label: 'رجّعه من الأرشيف',
            icon: Icons.restore_rounded,
            onTap: restore,
          )
        else
          SheetAction(
            label: 'أرشِف الملف',
            icon: Icons.inventory_2_outlined,
            tone: 'bad',
            hint: 'بيختفي من القوائم وتاريخه بيضلّ',
            onTap: archive,
          ),
      ],
    );
  }

  Future<void> _open(int id) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => StudentOfficeScreen(studentId: id)),
    );
    // A file edited, a programme ended, a child archived — the list behind
    // it must not still be showing what was true when it was opened.
    _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الطلاب'), centerTitle: false),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('طالب جديد'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _search,
                  onChanged: _onTyped,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'ابحث بالاسم أو رقم الملف…',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _search.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              _search.clear();
                              _onTyped('');
                            },
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final (value, label) in const [
                        ('active', 'نشط'),
                        ('paused', 'موقوف'),
                        ('graduated', 'تخرّج'),
                        ('withdrawn', 'انسحب'),
                        ('archived', 'الأرشيف'),
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
              ],
            ),
          ),
          Expanded(
            child: PagedList<Student>(
              key: _list,
              // Changing this starts the list over, which is how a chip
              // resets it without this screen tracking pages itself.
              filterKey: '$_status|$_query',
              fetch: (page) async => PageOf.fromEnvelope(
                await ref.read(apiProvider).getEnvelope('/students', query: {
                  'page': page,
                  'per_page': 30,
                  if (_status == 'archived')
                    'archived': 1
                  else if (_status.isNotEmpty)
                    'status': _status,
                  if (_query.isNotEmpty) 'q': _query,
                }),
                Student.fromJson,
              ),
              empty: _query.isEmpty
                  ? const AppEmpty(
                      icon: Icons.people_outline,
                      title: 'ما في طلاب بهذه الحالة',
                      hint: 'بدّل الفلتر، أو افتح ملفاً جديداً.',
                    )
                  : AppEmpty(
                      icon: Icons.search_off_rounded,
                      title: 'ما لقينا «$_query»',
                      hint: 'جرّب جزءاً من الاسم أو رقم الملف.',
                    ),
              itemBuilder: (context, student) => StudentRow(
                student: student,
                onTap: () => _open(student.id),
                onMore: () => _actions(student),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One child in the list.
class StudentRow extends StatelessWidget {
  const StudentRow({super.key, required this.student, required this.onTap, this.onMore});

  final Student student;
  final VoidCallback onTap;

  /// The ⋮ — and the long press, for the thumb that already knows the list.
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      onTap: onTap,
      onLongPress: onMore,
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Avatar(name: student.name, seed: student.id, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.name, style: text.titleSmall),
                Text(
                  [
                    'الملف #${student.fileNumber}',
                    if (student.ageLabel.isNotEmpty) student.ageLabel,
                    // The fee on the row itself: the office's commonest
                    // question about a child it is not opening.
                    if (student.monthlyFee != null) '${Fmt.number(student.monthlyFee)} ₪ بالشهر',
                  ].join(' · '),
                  style: text.bodySmall?.copyWith(color: AppColors.muted),
                ),
                if (student.enrollments.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final enrollment in student.enrollments.take(3))
                        SpecialtyTag(enrollment.specialty),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (student.archived)
                const ToneChip('مؤرشف', tone: 'muted', icon: Icons.inventory_2_outlined)
              else
                ToneChip(
                  Labels.studentStatus[student.status] ?? student.status,
                  tone: Labels.studentTone[student.status] ?? 'muted',
                ),
              // A child with no programme is a child nobody is scheduled to
              // see — the office's most actionable row.
              if (!student.archived && (student.enrollmentsCount ?? 0) == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: ToneChip('بلا برنامج', tone: 'bad', icon: Icons.error_outline_rounded),
                ),
              // And one with no fee is a child who will be left out of the
              // month's invoices — the same failure, in money.
              if (!student.archived && student.monthlyFee == null)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: ToneChip('بلا رسوم', tone: 'warn', icon: Icons.payments_outlined),
                ),
            ],
          ),
          if (onMore != null) RowMenu(onTap: onMore!),
        ],
      ),
    );
  }
}
