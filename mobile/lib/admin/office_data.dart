import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/core.dart';

/// The reads only the office has.
///
/// Kept apart from `core/data.dart` because every one of these answers 403 to
/// a specialist and to a family. A provider that is only ever valid for one
/// role sitting in the shared file is a provider somebody wires into a shared
/// screen, and then the screen works for three people and fails for two.

/// Everyone who works here — not only the specialists.
///
/// `core/data.dart` has `specialistsProvider`, which filters `role=specialist`
/// because it exists to fill the "assign a programme to" picker. The office
/// needs the other side of that list too: the second admin, the receptionist,
/// the specialist who was switched off last month. Filtering them out of the
/// staff screen is how an account nobody can see stays able to sign in.
final staffProvider = FutureProvider.autoDispose
    .family<List<Account>, ({String role, String search, bool? active})>((ref, filter) async {
  final body = await ref.watch(apiProvider).getEnvelope('/staff', query: {
        'per_page': 100,
        if (filter.role.isNotEmpty) 'role': filter.role,
        if (filter.search.isNotEmpty) 'q': filter.search,
        if (filter.active != null) 'active': filter.active! ? 1 : 0,
      });

  return J.list(body['data'], Account.fromJson);
});

/// The children one staff account is responsible for — what a delete would
/// orphan, and what an «خامل» would leave uncovered.
final staffChildrenProvider =
    FutureProvider.autoDispose.family<List<Student>, int>((ref, userId) async {
  final body = await ref.watch(apiProvider).getEnvelope('/staff/$userId/children');
  return J.list(body['data'], Student.fromJson);
});

/// Programmes, optionally for one child. The office creates and ends them;
/// a specialist may only edit the one she runs.
final enrollmentsProvider = FutureProvider.autoDispose
    .family<List<Enrollment>, ({int? studentId, String status})>((ref, filter) async {
  final body = await ref.watch(apiProvider).getEnvelope('/enrollments', query: {
        'per_page': 100,
        if (filter.studentId != null) 'student_id': filter.studentId,
        if (filter.status.isNotEmpty) 'status': filter.status,
      });

  return J.list(body['data'], Enrollment.fromJson);
});

/// What the academy is owed and what came in — the whole module is behind the
/// office wall, because a specialist who knows which family has not paid is a
/// specialist with a reason to treat two children differently.
final billingSummaryProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = await ref.watch(apiProvider).get('/billing/summary');
  return J.map(data) ?? const {};
});

final invoicesProvider = FutureProvider.autoDispose
    .family<List<Invoice>, ({String status, String period})>((ref, filter) async {
  final body = await ref.watch(apiProvider).getEnvelope('/billing/invoices', query: {
        'per_page': 60,
        if (filter.status.isNotEmpty) 'status': filter.status,
        if (filter.period.isNotEmpty) 'period': filter.period,
      });

  return J.list(body['data'], Invoice.fromJson);
});

final invoiceProvider = FutureProvider.autoDispose.family<Invoice, int>((ref, id) async {
  final data = await ref.watch(apiProvider).get('/billing/invoices/$id');
  return Invoice.fromJson(J.map(data) ?? const {});
});

/// One child's account — the parent sees this too, for her own child only.
///
/// Lives here rather than in `core/data.dart` only by history; the server
/// lets a guardian read her own child's account and refuses a specialist.
final studentBillingProvider =
    FutureProvider.autoDispose.family<StudentAccount, int>((ref, studentId) async {
  final data = await ref.watch(apiProvider).get('/billing/students/$studentId');
  return StudentAccount.fromJson(J.map(data) ?? const {});
});

/// The academy's own details — name, phone, what prints under a report.
final settingsProvider = FutureProvider.autoDispose<Map<String, String>>((ref) async {
  final data = J.map(await ref.watch(apiProvider).get('/settings')) ?? const {};
  return {for (final entry in data.entries) entry.key: J.s(entry.value)};
});

/// Reports across the whole academy, newest first. A specialist's own list is
/// scoped by the server; the office gets everybody's.
final allReportsProvider = FutureProvider.autoDispose
    .family<List<ProgressReport>, String>((ref, status) async {
  final body = await ref.watch(apiProvider).getEnvelope('/progress-reports', query: {
        'per_page': 40,
        if (status.isNotEmpty) 'status': status,
      });

  return J.list(body['data'], ProgressReport.fromJson);
});

/// The state of the one-way sync from the old system. See
/// `api/app/Http/Controllers/Api/SyncController.php`.
final syncStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = await ref.watch(apiProvider).get('/sync/status');
  return J.map(data) ?? const {};
});


/// اسم التخصص كما يُعرض: ما أرسله الخادم، وإلّا ترجمة الرمز الخام.
///
/// `specialty_label` مُلحقٌ على موديل البرنامج وحده. البرامج المتداخلة داخل
/// ملف الطالب تصل بلا هذا الحقل، فكان الوسم يُرسَم «—» على شاشة فيها
/// برنامجان شغّالان. الرمز الخام موجود دائماً، وترجمته في `Labels`.
String specialtyName(Enrollment enrollment) => enrollment.specialtyLabel.isNotEmpty
    ? enrollment.specialtyLabel
    : Labels.specialty[enrollment.specialty] ?? enrollment.specialty;
