import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import '../specialist/session_report_screen.dart';
import 'enrollment_form.dart';
import 'guardian_picker.dart';
import 'student_billing_sheet.dart';
import 'student_thread_screen.dart';
import 'student_form.dart';

/// One child, and everything the office may do about him.
///
/// The screen exists because the admin's control was spread across nothing:
/// the list did not open, and the actions the API has had no button at all.
/// Rather than scatter them — a delete here, a fee there — they are gathered
/// on the file itself, which is where somebody looking for them will be.
///
/// What is **not** here: writing the therapy. The office may open a session
/// and read it, and the report screen it opens is the specialist's own — the
/// same screen, the same rules, `mayWriteOn` enforced on the server. There is
/// no separate admin way to write on a child's file, because two ways to
/// write the same report is how two versions of it come to exist.
class StudentOfficeScreen extends ConsumerWidget {
  const StudentOfficeScreen({super.key, required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final file = ref.watch(studentProvider(studentId));

    return Scaffold(
      appBar: AppBar(
        title: Text(file.valueOrNull?.student.name ?? 'الملف'),
        actions: [
          if (file.hasValue)
            _FileMenu(file: file.value!, onDone: () => reload(ref, studentProvider(studentId).future)),
        ],
      ),
      body: AsyncView<StudentFile>(
        value: file,
        onRetry: () => reload(ref, studentProvider(studentId).future),
        data: (data) => _Body(file: data, studentId: studentId),
      ),
    );
  }
}

/// The destructive and the administrative, behind one button.
///
/// Not spread across the screen as buttons: «احذف الملف» sitting beside
/// «عدّل» is a delete that gets pressed on the way to an edit.
class _FileMenu extends ConsumerWidget {
  const _FileMenu({required this.file, required this.onDone});

  final StudentFile file;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = file.student;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (choice) async {
        final api = ref.read(apiProvider);

        try {
          switch (choice) {
            case 'edit':
              final saved = await openStudentForm(context, ref, student: student);
              if (saved != null && context.mounted) showToast(context, 'انحفظ الملف.');

            case 'fee':
              await openFeeSheet(context, ref, student);

            case 'archive':
              final sure = await confirm(
                context,
                title: 'أرشفة ملف ${student.name}؟',
                // The honest description of what the server does: a soft
                // delete. Calling it «حذف» would make the office think the
                // history is gone and stop them doing it when they should.
                body: 'الملف بيروح للأرشيف ولا بينحذف. جلساته وتقاريره بيضلّوا، '
                    'وبترجّعه بضغطة من فلتر «الأرشيف».',
                confirmLabel: 'أرشِف',
                danger: true,
              );
              if (!sure) return;
              await api.delete('/students/${student.id}');
              if (context.mounted) {
                showToast(context, 'انأرشف الملف.');
                Navigator.of(context).pop();
              }

            case 'restore':
              await api.post('/students/${student.id}/restore');
              if (context.mounted) showToast(context, 'رجع الملف.');
          }
        } on ApiException catch (error) {
          if (context.mounted) showFailure(context, error);
        }

        onDone();
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'edit',
          child: ListTile(
            leading: Icon(Icons.edit_outlined),
            title: Text('عدّل الملف'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuItem(
          value: 'fee',
          child: ListTile(
            leading: Icon(Icons.payments_outlined),
            title: Text('الرسوم الشهرية'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        const PopupMenuDivider(),
        if (student.archived)
          const PopupMenuItem(
            value: 'restore',
            child: ListTile(
              leading: Icon(Icons.restore_rounded),
              title: Text('رجّع من الأرشيف'),
              contentPadding: EdgeInsets.zero,
            ),
          )
        else
          const PopupMenuItem(
            value: 'archive',
            child: ListTile(
              leading: Icon(Icons.inventory_2_outlined, color: AppColors.bad),
              title: Text('أرشِف الملف', style: TextStyle(color: AppColors.bad)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.file, required this.studentId});

  final StudentFile file;
  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = file.student;
    final text = Theme.of(context).textTheme;

    Future<void> refreshFile() => reload(ref, studentProvider(studentId).future);

    return RefreshList(
      onRefresh: refreshFile,
      children: [
        if (student.medicalAlert != null && student.medicalAlert!.isNotEmpty)
          MedicalAlert(student.medicalAlert!),

        if (student.archived)
          const NoteBox(
            'هذا الملف مؤرشف. بيضلّ يتقرا، وما بينكتب عليه إشي جديد لحتى يترجّع.',
            tone: 'warn',
            icon: Icons.inventory_2_outlined,
          ),

        /* ---- who he is ------------------------------------------------ */

        SectionCard(
          title: 'الملف',
          child: Column(
            children: [
              InfoRow(label: 'رقم الملف', value: '#${student.fileNumber}'),
              InfoRow(label: 'العمر', value: student.ageLabel),
              InfoRow(label: 'تاريخ الميلاد', value: Fmt.date(student.birthDate)),
              InfoRow(label: 'الجنس', value: student.gender == 'female' ? 'أنثى' : 'ذكر'),
              InfoRow(
                label: 'الحالة',
                value: Labels.studentStatus[student.status] ?? student.status,
              ),
              InfoRow(label: 'تاريخ الالتحاق', value: Fmt.date(student.enrolledAt)),
              InfoRow(
                label: 'الرسوم الشهرية',
                value: student.monthlyFee == null ? 'ما انحطّت' : '${Fmt.number(student.monthlyFee)} ₪',
              ),
              if (student.leftAt != null) InfoRow(label: 'غادر في', value: Fmt.date(student.leftAt)),
              if (student.diagnosis != null) InfoRow(label: 'التشخيص', value: student.diagnosis!),
              if (student.school != null) InfoRow(label: 'المدرسة', value: student.school!),
              if (student.grade != null) InfoRow(label: 'الصف', value: student.grade!),
              if (student.nationalId != null) InfoRow(label: 'رقم الهوية', value: student.nationalId!),
            ],
          ),
        ),

        if (student.diagnosisNotes != null && student.diagnosisNotes!.isNotEmpty)
          SectionCard(
            title: 'تفاصيل التشخيص',
            child: Text(student.diagnosisNotes!, style: text.bodyMedium),
          ),

        if (student.notes != null && student.notes!.isNotEmpty)
          SectionCard(title: 'ملاحظات', child: Text(student.notes!, style: text.bodyMedium)),

        /* ---- the family ----------------------------------------------- */

        _Guardians(student: student, onChanged: refreshFile),

        /* ---- the programmes -------------------------------------------- */

        _Enrollments(student: student, onChanged: refreshFile),

        /* ---- what the office opens from here ---------------------------- */

        SectionCard(
          title: 'الملف الكامل',
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const IconTile(Icons.receipt_long_rounded, tone: 'good'),
                title: const Text('الحساب والفواتير'),
                subtitle: const Text('الرسوم، الفواتير، والمدفوع'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => openStudentBilling(context, ref, student),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const IconTile(Icons.forum_rounded),
                title: const Text('المراسلات مع الأهل'),
                subtitle: const Text('اقرأ واكتب في ملفّ هذا الطفل'),
                trailing: const Icon(Icons.chevron_left_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => StudentThreadScreen(student: student),
                )),
              ),
            ],
          ),
        ),

        /* ---- the goals --------------------------------------------------- */

        _Goals(studentId: studentId),

        /* ---- the sessions ------------------------------------------------ */

        _Sessions(studentId: studentId),
      ],
    );
  }
}

/// Who holds a login to this child's file.
class _Guardians extends ConsumerWidget {
  const _Guardians({required this.student, required this.onChanged});

  final Student student;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return SectionCard(
      title: 'الأهل',
      action: TextButton.icon(
        onPressed: () async {
          final added = await openGuardianPicker(context, ref, student);
          if (added == true) onChanged();
        },
        icon: const Icon(Icons.person_add_alt_rounded, size: 18),
        label: const Text('اربط ولي أمر'),
      ),
      child: student.guardians.isEmpty
          // The office's most common real gap: a child on file whose family
          // has no way in. Worth saying rather than showing a blank space
          // that reads like "nothing to do here".
          ? const NoteBox(
              'ما في ولي أمر مربوط بهذا الملف — يعني ما في حدا من العيلة بيقدر يشوف تقاريره.',
              tone: 'warn',
              icon: Icons.link_off_rounded,
            )
          : Column(
              children: [
                for (final guardian in student.guardians)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Avatar(name: guardian.name, seed: guardian.id, size: 40),
                    title: Row(
                      children: [
                        Flexible(child: Text(guardian.name, style: text.titleSmall)),
                        if (guardian.isPrimary) ...[
                          const SizedBox(width: 6),
                          const ToneChip('الأساسي', tone: 'brand'),
                        ],
                      ],
                    ),
                    subtitle: Text(
                      [
                        Labels.relation[guardian.relation] ?? guardian.relation,
                        if (guardian.phone != null) guardian.phone!,
                      ].join(' · '),
                      style: text.bodySmall,
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.link_off_rounded, color: AppColors.bad),
                      tooltip: 'فكّ الربط',
                      onPressed: () async {
                        final sure = await confirm(
                          context,
                          title: 'فكّ ربط ${guardian.name}؟',
                          body: 'حسابه بيضلّ، بس ما بيعود يشوف ملف ${student.name}.',
                          confirmLabel: 'فكّ الربط',
                          danger: true,
                        );
                        if (!sure) return;

                        try {
                          await ref
                              .read(apiProvider)
                              .delete('/students/${student.id}/guardians/${guardian.id}');
                          if (context.mounted) showToast(context, 'انفكّ الربط.');
                          onChanged();
                        } on ApiException catch (error) {
                          if (context.mounted) showFailure(context, error);
                        }
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The programmes he is on — the thing that decides who sees him and how often.
class _Enrollments extends ConsumerWidget {
  const _Enrollments({required this.student, required this.onChanged});

  final Student student;
  final VoidCallback onChanged;

  Future<void> _edit(BuildContext context, WidgetRef ref, Enrollment enrollment) async {
    final saved = await openEnrollmentForm(context, ref, student: student, enrollment: enrollment);
    if (saved != null) onChanged();
  }

  /// Editing a programme and deleting it are not the same act, and the
  /// second one takes the child's sessions with it — so it asks, and it says
  /// what it is about to take.
  Future<void> _menu(BuildContext context, WidgetRef ref, Enrollment enrollment) {
    return showActions(
      context,
      title: Labels.specialty[enrollment.specialty] ?? 'البرنامج',
      subtitle: enrollment.specialist?.name ?? 'بلا أخصائية',
      actions: [
        SheetAction(
          label: 'عدّل البرنامج',
          icon: Icons.edit_outlined,
          hint: 'الأخصائية، عدد الجلسات، المدّة، الحالة',
          onTap: () => _edit(context, ref, enrollment),
        ),
        SheetAction(
          label: 'احذف البرنامج',
          icon: Icons.delete_outline_rounded,
          tone: 'bad',
          hint: 'للبرنامج الي انفتح بالغلط. وقف الشغل عليه؟ خلّيه «منتهي» بدل ما تحذفه.',
          onTap: () async {
            final sure = await confirm(
              context,
              title: 'احذف برنامج ${Labels.specialty[enrollment.specialty] ?? ''}؟',
              body: 'بينشال من ملفّ ${student.name}. إذا إله جلسات مسجّلة '
                  'الخادم بيرفض الحذف — وقتها خلّي حالته «منتهي».',
              confirmLabel: 'احذف',
              danger: true,
            );
            if (!sure || !context.mounted) return;

            try {
              await ref.read(apiProvider).delete('/enrollments/${enrollment.id}');
              onChanged();
              if (context.mounted) showToast(context, 'انحذف البرنامج.');
            } on ApiException catch (error) {
              if (context.mounted) showFailure(context, error);
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;

    return SectionCard(
      title: 'البرامج',
      action: TextButton.icon(
        onPressed: () async {
          final saved = await openEnrollmentForm(context, ref, student: student);
          if (saved != null) onChanged();
        },
        icon: const Icon(Icons.add_rounded, size: 18),
        label: const Text('برنامج جديد'),
      ),
      child: student.enrollments.isEmpty
          ? const NoteBox(
              'ما في برنامج — يعني ما في أخصائية مسؤولة عنه ولا جلسات بتنجدول إله.',
              tone: 'bad',
              icon: Icons.error_outline_rounded,
            )
          : Column(
              children: [
                for (final enrollment in student.enrollments)
                  AppCard(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    onTap: () => _edit(context, ref, enrollment),
                    onLongPress: () => _menu(context, ref, enrollment),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SpecialtyTag(enrollment.specialty),
                              const SizedBox(height: 4),
                              Text(
                                enrollment.specialist?.name ?? 'بلا أخصائية',
                                style: text.titleSmall?.copyWith(
                                  color: enrollment.specialist == null ? AppColors.bad : null,
                                ),
                              ),
                              Text(
                                '${enrollment.sessionsPerWeek} جلسات بالأسبوع · '
                                '${enrollment.sessionMinutes} دقيقة',
                                style: text.bodySmall?.copyWith(color: AppColors.muted),
                              ),
                            ],
                          ),
                        ),
                        ToneChip(
                          Labels.enrollmentStatus[enrollment.status] ?? enrollment.status,
                          tone: switch (enrollment.status) {
                            'active' => 'good',
                            'paused' => 'warn',
                            _ => 'muted',
                          },
                        ),
                        RowMenu(onTap: () => _menu(context, ref, enrollment)),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

/// The goals on the file, and how far along each one is.
///
/// Read-only here on purpose: a goal is written by the specialist who will
/// score it every session, and the prompt level it is scored on is a clinical
/// judgement. The office needs to *see* them — a child with no active goal is
/// a child whose sessions are not measuring anything — and that is what this
/// section is for.
class _Goals extends ConsumerWidget {
  const _Goals({required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals = ref.watch(studentGoalsProvider(studentId));
    final text = Theme.of(context).textTheme;

    return SectionCard(
      title: 'الأهداف',
      child: goals.when(
        loading: () => const AppLoading(),
        error: (error, _) => AppError(
          error: error,
          onRetry: () => reload(ref, studentGoalsProvider(studentId).future),
        ),
        data: (list) {
          final active = list.where((goal) => goal.status == 'active').toList();

          if (list.isEmpty) {
            return const NoteBox(
              'ما في أهداف — يعني جلساته ما بتقيس إشي. الأخصائية بتكتبهم من ملفّها.',
              tone: 'warn',
              icon: Icons.flag_outlined,
            );
          }

          return Column(
            children: [
              for (final goal in [...active, ...list.where((g) => g.status != 'active')].take(8))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(goal.title, style: text.bodyMedium),
                            Text(
                              Labels.specialty[goal.specialty] ?? '',
                              style: text.labelSmall?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          ToneChip(
                            Labels.goalStatus[goal.status] ?? goal.status,
                            tone: switch (goal.status) {
                              'active' => 'brand',
                              'achieved' => 'good',
                              'paused' => 'warn',
                              _ => 'muted',
                            },
                          ),
                          // Where he started and where he is — the one number
                          // this whole system exists to move.
                          if (goal.trend != null)
                            Text(
                              '${Labels.level(goal.baseline)} ← ${Labels.level(goal.trend!.latest)}',
                              style: text.labelSmall?.copyWith(color: AppColors.muted),
                            ),
                        ],
                      ),
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

/// The last sessions on the file, as a way in rather than as a list.
class _Sessions extends ConsumerWidget {
  const _Sessions({required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessions = ref.watch(studentSessionsProvider(studentId));
    final text = Theme.of(context).textTheme;

    return SectionCard(
      title: 'آخر الجلسات',
      child: sessions.when(
        loading: () => const AppLoading(),
        error: (error, _) => AppError(
          error: error,
          onRetry: () => reload(ref, studentSessionsProvider(studentId).future),
        ),
        data: (list) => list.isEmpty
            ? const NoteBox(
                'ما في جلسات مسجّلة بعد.',
                tone: 'muted',
                icon: Icons.event_busy_rounded,
              )
            : Column(
                children: [
                  for (final session in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(Fmt.dateTime(session.scheduledAt), style: text.titleSmall),
                      subtitle: Text(
                        [
                          Labels.specialty[session.specialty] ?? session.specialty,
                          if (session.specialist != null) session.specialist!.name,
                        ].join(' · '),
                        style: text.bodySmall,
                      ),
                      trailing: ToneChip(
                        Labels.sessionStatus[session.status] ?? session.status,
                        tone: Labels.sessionTone[session.status] ?? 'muted',
                      ),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => SessionReportScreen(
                          sessionId: session.id,
                          studentName: session.student?.name ?? '',
                        ),
                      )),
                    ),
                ],
              ),
      ),
    );
  }
}
