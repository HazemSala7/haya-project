import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

class StudentFileScreen extends ConsumerWidget {
  const StudentFileScreen({super.key, required this.studentId});

  final int studentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentFile = ref.watch(studentProvider(studentId));

    return studentFile.when(
      data: (file) {
        final student = file.student;

        return Scaffold(
          appBar: AppBar(
            title: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.name, style: Theme.of(context).textTheme.titleMedium),
                Text('الملف #${student.fileNumber}', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            centerTitle: false,
          ),
          body: RefreshList(
            onRefresh: () => ref.refresh(studentProvider(studentId).future),
            children: [
              if (student.medicalAlert != null && student.medicalAlert!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: MedicalAlert(student.medicalAlert!),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: SectionCard(
                  title: 'المعلومات',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      InfoRow(label: 'الحالة', value: student.status),
                      if (student.gender != null) InfoRow(label: 'النوع', value: student.gender),
                      if (student.ageLabel.isNotEmpty) InfoRow(label: 'العمر', value: student.ageLabel),
                      if (student.diagnosis != null) InfoRow(label: 'التشخيص', value: student.diagnosis),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SectionTitle('البرامج النشطة', count: student.enrollments.length),
              ),
              for (final enrollment in student.enrollments)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: EnrollmentCard(enrollment: enrollment),
                ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
      loading: () => const Scaffold(body: AppLoading()),
      error: (error, _) => Scaffold(
        body: AppError(
          error: error,
          onRetry: () => ref.refresh(studentProvider(studentId).future),
        ),
      ),
    );
  }
}

class EnrollmentCard extends StatelessWidget {
  const EnrollmentCard({super.key, required this.enrollment});

  final Enrollment enrollment;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SpecialtyTag(enrollment.specialty),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(enrollment.specialtyLabel, style: text.titleSmall),
                    if (enrollment.specialist != null)
                      Text(enrollment.specialist!.name, style: text.bodySmall?.copyWith(color: AppColors.muted)),
                  ],
                ),
              ),
              ToneChip(enrollment.status, tone: 'info'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${enrollment.sessionsPerWeek}/أسبوع', style: text.labelSmall),
                    Text('${enrollment.sessionMinutes} دقيقة', style: text.bodySmall),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الأهداف', style: text.labelSmall),
                    Text('${enrollment.goalsCount ?? 0}', style: text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
