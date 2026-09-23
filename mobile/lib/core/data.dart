import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth/session.dart';
import 'models/json.dart';
import 'models/profile.dart';
import 'models/records.dart';

/// The reads more than one screen shares.
///
/// Every provider here is `autoDispose`: a child's file or a report read on
/// Monday must not be what the same screen shows on Tuesday because the app
/// was never closed. The price is one request per visit, which is the right
/// price for data a family is being asked to trust.

/// `GET /dashboard` — three different shapes behind one path; each home
/// screen reads the keys that belong to it.
final dashboardProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = await ref.watch(apiProvider).get('/dashboard');
  return J.map(data) ?? const {};
});

/// One nav badge: how many there are, and how many wait for a person.
class NavCount {
  const NavCount(this.total, this.attention);
  final int total;
  final int attention;
}

/// `GET /nav-counts` — the numbers beside the tabs. Re-read on every tab
/// change, so a count never contradicts the screen just acted on.
final navCountsProvider = FutureProvider.autoDispose<Map<String, NavCount>>((ref) async {
  final data = J.map(await ref.watch(apiProvider).get('/nav-counts')) ?? const {};
  return {
    for (final entry in data.entries)
      entry.key: NavCount(
        J.int0(J.map(entry.value)?['total']),
        J.int0(J.map(entry.value)?['attention']),
      ),
  };
});

/// A child's file and its summary — one request, as the server shapes it.
class StudentFile {
  const StudentFile(this.student, this.summary);
  final Student student;
  final StudentSummary summary;
}

final studentProvider = FutureProvider.autoDispose.family<StudentFile, int>((ref, id) async {
  final body = await ref.watch(apiProvider).getEnvelope('/students/$id');
  return StudentFile(
    Student.fromJson(J.map(body['data']) ?? const {}),
    StudentSummary.fromJson(J.map(body['meta']) ?? const {}),
  );
});

/// The children this account may read.
///
/// The API scopes it: a specialist gets the ones she has an active programme
/// with, the office gets everybody. So no filter is sent — asking for "mine"
/// would be the client deciding a thing the server already decided, and the
/// two would disagree the first time an enrolment moved.
final studentsProvider = FutureProvider.autoDispose<List<Student>>((ref) async {
  final body = await ref
      .watch(apiProvider)
      .getEnvelope('/students', query: {'per_page': 100, 'status': 'active'});
  return J.list(body['data'], Student.fromJson);
});

/// Sessions, newest first.
///
/// Scoped to the signed-in specialist's own sessions, and not merely to the
/// children she can reach: those children also see other specialists, and the
/// API refuses a write on somebody else's session. Listing them under a badge
/// reading «بدّه تقرير» would be offering her work she is not allowed to do.
/// The office has no such limit, so it gets everything.
final sessionsProvider = FutureProvider.autoDispose<List<TherapySession>>((ref) async {
  final me = ref.watch(meProvider);

  final body = await ref.watch(apiProvider).getEnvelope('/sessions', query: {
        'per_page': 40,
        if (me?.role == AppRole.specialist) 'specialist_id': me!.id,
      });

  return J.list(body['data'], TherapySession.fromJson);
});

/// One child's thread with the academy, newest first as the API sends it.
final threadProvider =
    FutureProvider.autoDispose.family<List<ChatMessage>, int>((ref, studentId) async {
  final body = await ref
      .watch(apiProvider)
      .getEnvelope('/students/$studentId/messages', query: {'per_page': 60});
  return J.list(body['data'], ChatMessage.fromJson);
});

/// Every goal on a child's file — active ones and the history.
final studentGoalsProvider = FutureProvider.autoDispose.family<List<Goal>, int>((ref, id) async {
  final body = await ref
      .watch(apiProvider)
      .getEnvelope('/goals', query: {'student_id': id, 'per_page': 100});
  return J.list(body['data'], Goal.fromJson);
});

/// The latest sessions on a child's file. The full history is paged on the
/// sessions screen — a child two years in has three hundred of them.
final studentSessionsProvider =
    FutureProvider.autoDispose.family<List<TherapySession>, int>((ref, id) async {
  final body = await ref
      .watch(apiProvider)
      .getEnvelope('/sessions', query: {'student_id': id, 'per_page': 12});
  return J.list(body['data'], TherapySession.fromJson);
});

final sessionProvider = FutureProvider.autoDispose.family<TherapySession, int>((ref, id) async {
  final data = await ref.watch(apiProvider).get('/sessions/$id');
  return TherapySession.fromJson(J.map(data) ?? const {});
});

/// The goals a report can be scored against: the programme's active ones.
final enrollmentGoalsProvider =
    FutureProvider.autoDispose.family<List<Goal>, int>((ref, enrollmentId) async {
  final body = await ref.watch(apiProvider).getEnvelope(
    '/goals',
    query: {'enrollment_id': enrollmentId, 'status': 'active', 'per_page': 50},
  );
  return J.list(body['data'], Goal.fromJson);
});

final goalCurveProvider = FutureProvider.autoDispose.family<GoalCurve, int>((ref, id) async {
  final data = await ref.watch(apiProvider).get('/goals/$id');
  return GoalCurve.fromJson(J.map(data) ?? const {});
});

/// Threads with something unread in them.
final unreadThreadsProvider = FutureProvider.autoDispose<List<UnreadThread>>((ref) async {
  final body = await ref.watch(apiProvider).getEnvelope('/messages/unread');
  return J.list(body['data'], UnreadThread.fromJson);
});

final progressReportProvider =
    FutureProvider.autoDispose.family<ProgressReport, int>((ref, id) async {
  final data = await ref.watch(apiProvider).get('/progress-reports/$id');
  return ProgressReport.fromJson(J.map(data) ?? const {});
});

/// A child's periodic reports — for the file, and for a parent's list.
final studentReportsProvider =
    FutureProvider.autoDispose.family<List<ProgressReport>, int>((ref, id) async {
  final body = await ref
      .watch(apiProvider)
      .getEnvelope('/progress-reports', query: {'student_id': id, 'per_page': 20});
  return J.list(body['data'], ProgressReport.fromJson);
});

final analyticsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, int>((ref, weeks) async {
  final data = await ref.watch(apiProvider).get('/analytics', query: {'weeks': weeks});
  return J.map(data) ?? const {};
});

/// Active specialists, for assigning a programme. Admin only on the server.
final specialistsProvider = FutureProvider.autoDispose<List<Account>>((ref) async {
  final body = await ref.watch(apiProvider).getEnvelope(
    '/staff',
    query: {'role': 'specialist', 'active': 1, 'per_page': 100},
  );
  return J.list(body['data'], Account.fromJson);
});
