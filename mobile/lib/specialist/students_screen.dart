import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';
import 'student_file_screen.dart';

/*
 * The children a specialist is working with.
 *
 * What stood here said «لا توجد برامج مسندة» — to a specialist who has eight
 * of them. It was a placeholder that had learned to sound authoritative, which
 * is worse than a blank screen: an empty state is a claim about the data, and
 * this one was false.
 *
 * The medical line rides on the row rather than waiting inside the file. She
 * is scrolling this list on the way into a room, and «تاريخ تشنجات» is not a
 * detail to be discovered one tap later.
 */
class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});

  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final students = ref.watch(studentsProvider);
    final needle = _search.text.trim();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: TextField(
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'ابحث بالاسم أو رقم الملف...',
              prefixIcon: Icon(Icons.search_rounded),
            ),
          ),
        ),

        Expanded(
          child: AsyncView(
            value: students,
            onRetry: () => reload(ref, studentsProvider.future),
            data: (list) {
              final shown = needle.isEmpty
                  ? list
                  : [
                      for (final s in list)
                        if (s.name.contains(needle) || s.fileNumber.contains(needle)) s,
                    ];

              if (shown.isEmpty) {
                return AppEmpty(
                  icon: Icons.person_search_rounded,
                  title: needle.isEmpty ? 'لا يوجد طلاب' : 'ما في نتيجة',
                  hint: needle.isEmpty
                      ? 'لسّا ما انسند إلك برنامج.'
                      : 'جرّبي اسم أو رقم ملف ثاني.',
                );
              }

              return RefreshIndicator(
                onRefresh: () => reload(ref, studentsProvider.future),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: shown.length,
                  itemBuilder: (context, i) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _StudentRow(
                      student: shown[i],
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => StudentFileScreen(studentId: shown[i].id),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({required this.student, required this.onTap});

  final Student student;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final alert = student.medicalAlert;
    final hasAlert = alert != null && alert.trim().isNotEmpty;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Avatar(name: student.name, seed: student.id, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(student.name, style: text.titleSmall),
                    Text(
                      '${student.ageLabel} · ملف ${student.fileNumber}',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_left_rounded, size: 20, color: AppColors.faint),
            ],
          ),

          if (student.diagnosis != null && student.diagnosis!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(student.diagnosis!, style: text.bodySmall?.copyWith(height: 1.6)),
          ],

          // The one line that can change what she does in the next minute.
          if (hasAlert) ...[
            const SizedBox(height: 9),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.badSoft,
                borderRadius: AppShape.control,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.warning_rounded, size: 15, color: AppColors.bad),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      alert.trim(),
                      style: text.labelMedium?.copyWith(color: AppColors.bad, height: 1.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
