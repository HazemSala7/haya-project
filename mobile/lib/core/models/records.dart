import 'json.dart';

/// A page of rows and the counts the API reports beside them.
class PageOf<T> {
  const PageOf({
    required this.items,
    required this.total,
    required this.currentPage,
    required this.lastPage,
    this.meta = const {},
  });

  final List<T> items;
  final int total;
  final int currentPage;
  final int lastPage;

  /// Anything else the endpoint put in `meta` — `unwritten`, `unassigned`.
  final Map<String, dynamic> meta;

  bool get hasMore => currentPage < lastPage;

  factory PageOf.fromEnvelope(Map<String, dynamic> body, T Function(Map<String, dynamic>) parse) {
    final meta = J.map(body['meta']) ?? const {};
    return PageOf(
      items: J.list(body['data'], parse),
      total: J.int0(meta['total']),
      currentPage: J.intOrNull(meta['current_page']) ?? 1,
      lastPage: J.intOrNull(meta['last_page']) ?? 1,
      meta: meta,
    );
  }
}

/// Someone named on a row — a specialist, an author, a sender.
class PersonRef {
  const PersonRef({required this.id, required this.name, this.title, this.role});

  final int id;
  final String name;
  final String? title;
  final String? role;

  static PersonRef? maybe(Object? json) {
    final map = J.map(json);
    if (map == null) return null;
    return PersonRef(
      id: J.int0(map['id']),
      name: J.s(map['name']),
      title: J.str(map['title']),
      role: J.str(map['role']),
    );
  }
}

class Guardian {
  const Guardian({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.relation,
    this.isPrimary = false,
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? relation;
  final bool isPrimary;

  factory Guardian.fromJson(Map<String, dynamic> json) {
    final pivot = J.map(json['pivot']);
    return Guardian(
      id: J.int0(json['id']),
      name: J.s(json['name']),
      email: J.s(json['email']),
      phone: J.str(json['phone']),
      relation: J.str(pivot?['relation']),
      isPrimary: J.boolean(pivot?['is_primary']),
    );
  }
}

/// A child's file.
class Student {
  const Student({
    required this.id,
    required this.fileNumber,
    required this.name,
    required this.ageLabel,
    required this.status,
    this.birthDate,
    this.gender,
    this.nationalId,
    this.diagnosis,
    this.diagnosisNotes,
    this.medicalAlert,
    this.school,
    this.grade,
    this.enrolledAt,
    this.leftAt,
    this.notes,
    this.enrollmentsCount,
    this.enrollments = const [],
    this.guardians = const [],
    this.archived = false,
  });

  final int id;
  final String fileNumber;
  final String name;
  final String ageLabel;
  final String status;
  final String? birthDate;
  final String? gender;
  final String? nationalId;
  final String? diagnosis;
  final String? diagnosisNotes;
  final String? medicalAlert;
  final String? school;
  final String? grade;
  final String? enrolledAt;
  final String? leftAt;
  final String? notes;
  final int? enrollmentsCount;
  final List<Enrollment> enrollments;
  final List<Guardian> guardians;
  final bool archived;

  factory Student.fromJson(Map<String, dynamic> json) => Student(
        id: J.int0(json['id']),
        fileNumber: J.s(json['file_number']),
        name: J.s(json['name']),
        ageLabel: J.s(json['age_label']),
        status: J.str(json['status']) ?? 'active',
        birthDate: J.str(json['birth_date']),
        gender: J.str(json['gender']),
        nationalId: J.str(json['national_id']),
        diagnosis: J.str(json['diagnosis']),
        diagnosisNotes: J.str(json['diagnosis_notes']),
        medicalAlert: J.str(json['medical_alert']),
        school: J.str(json['school']),
        grade: J.str(json['grade']),
        enrolledAt: J.str(json['enrolled_at']),
        leftAt: J.str(json['left_at']),
        notes: J.str(json['notes']),
        enrollmentsCount: J.intOrNull(json['enrollments_count']),
        enrollments: J.list(json['enrollments'], Enrollment.fromJson),
        guardians: J.list(json['guardians'], Guardian.fromJson),
        archived: json['deleted_at'] != null,
      );
}

/// A programme — one specialty, for one child, with one specialist on it.
class Enrollment {
  const Enrollment({
    required this.id,
    required this.studentId,
    required this.specialty,
    required this.specialtyLabel,
    required this.sessionsPerWeek,
    required this.sessionMinutes,
    required this.status,
    this.specialistId,
    this.startedAt,
    this.endedAt,
    this.planSummary,
    this.specialist,
    this.student,
    this.goalsCount,
    this.sessionsCount,
  });

  final int id;
  final int studentId;
  final String specialty;
  final String specialtyLabel;
  final int? specialistId;
  final int sessionsPerWeek;
  final int sessionMinutes;
  final String? startedAt;
  final String? endedAt;
  final String status;
  final String? planSummary;
  final PersonRef? specialist;
  final Student? student;
  final int? goalsCount;
  final int? sessionsCount;

  factory Enrollment.fromJson(Map<String, dynamic> json) => Enrollment(
        id: J.int0(json['id']),
        studentId: J.int0(json['student_id']),
        specialty: J.s(json['specialty']),
        specialtyLabel: J.s(json['specialty_label']),
        specialistId: J.intOrNull(json['specialist_id']),
        sessionsPerWeek: J.intOrNull(json['sessions_per_week']) ?? 2,
        sessionMinutes: J.intOrNull(json['session_minutes']) ?? 45,
        startedAt: J.str(json['started_at']),
        endedAt: J.str(json['ended_at']),
        status: J.str(json['status']) ?? 'active',
        planSummary: J.str(json['plan_summary']),
        specialist: PersonRef.maybe(json['specialist']),
        student: J.map(json['student']) == null ? null : Student.fromJson(J.map(json['student'])!),
        goalsCount: J.intOrNull(json['goals_count']),
        sessionsCount: J.intOrNull(json['sessions_count']),
      );
}

/// Where a goal stands, as the list endpoint computes it.
class GoalTrend {
  const GoalTrend({this.latest, this.delta, this.ratings = 0});

  final int? latest;
  final int? delta;
  final int ratings;

  static GoalTrend? maybe(Object? json) {
    final map = J.map(json);
    if (map == null) return null;
    return GoalTrend(
      latest: J.intOrNull(map['latest']),
      delta: J.intOrNull(map['delta']),
      ratings: J.int0(map['ratings']),
    );
  }
}

class Goal {
  const Goal({
    required this.id,
    required this.studentId,
    required this.enrollmentId,
    required this.title,
    required this.baseline,
    required this.status,
    this.description,
    this.criteria,
    this.target,
    this.startedAt,
    this.achievedAt,
    this.specialty,
    this.trend,
  });

  final int id;
  final int studentId;
  final int enrollmentId;
  final String title;
  final String? description;
  final String? criteria;
  final int baseline;
  final int? target;
  final String status;
  final String? startedAt;
  final String? achievedAt;

  /// From the eager-loaded enrolment, when the list carried it.
  final String? specialty;
  final GoalTrend? trend;

  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
        id: J.int0(json['id']),
        studentId: J.int0(json['student_id']),
        enrollmentId: J.int0(json['enrollment_id']),
        title: J.s(json['title']),
        description: J.str(json['description']),
        criteria: J.str(json['criteria']),
        baseline: J.int0(json['baseline']),
        target: J.intOrNull(json['target']),
        status: J.str(json['status']) ?? 'active',
        startedAt: J.str(json['started_at']),
        achievedAt: J.str(json['achieved_at']),
        specialty: J.str(J.map(json['enrollment'])?['specialty']),
        trend: GoalTrend.maybe(json['trend']),
      );
}

class GoalRating {
  const GoalRating({
    required this.id,
    required this.goalId,
    required this.level,
    required this.levelLabel,
    this.trials,
    this.successes,
    this.note,
    this.goalTitle,
    this.goalCriteria,
    this.goalBaseline,
  });

  final int id;
  final int goalId;
  final int level;
  final String levelLabel;
  final int? trials;
  final int? successes;
  final String? note;
  final String? goalTitle;
  final String? goalCriteria;
  final int? goalBaseline;

  factory GoalRating.fromJson(Map<String, dynamic> json) {
    final goal = J.map(json['goal']);
    return GoalRating(
      id: J.int0(json['id']),
      goalId: J.int0(json['goal_id']),
      level: J.int0(json['level']),
      levelLabel: J.s(json['level_label']),
      trials: J.intOrNull(json['trials']),
      successes: J.intOrNull(json['successes']),
      note: J.str(json['note']),
      goalTitle: J.str(goal?['title']),
      goalCriteria: J.str(goal?['criteria']),
      goalBaseline: J.intOrNull(goal?['baseline']),
    );
  }
}

class Attachment {
  const Attachment({
    required this.id,
    required this.name,
    required this.mime,
    required this.size,
    required this.kind,
    this.caption,
  });

  final int id;
  final String name;
  final String mime;
  final int size;
  final String kind;
  final String? caption;

  bool get isVideo => kind == 'video';

  factory Attachment.fromJson(Map<String, dynamic> json) => Attachment(
        id: J.int0(json['id']),
        name: J.s(json['original_name']),
        mime: J.s(json['mime']),
        size: J.int0(json['size']),
        kind: J.str(json['kind']) ?? 'image',
        caption: J.str(json['caption']),
      );
}

class Addendum {
  const Addendum({required this.id, required this.body, this.createdAt, this.author});

  final int id;
  final String body;
  final String? createdAt;
  final PersonRef? author;

  factory Addendum.fromJson(Map<String, dynamic> json) => Addendum(
        id: J.int0(json['id']),
        body: J.s(json['body']),
        createdAt: J.str(json['created_at']),
        author: PersonRef.maybe(json['author']),
      );
}

class ReadReceipt {
  const ReadReceipt({this.name, this.readAt});

  final String? name;
  final String? readAt;

  factory ReadReceipt.fromJson(Map<String, dynamic> json) =>
      ReadReceipt(name: J.str(json['name']), readAt: J.str(json['read_at']));
}

/// الجلسة — the appointment, and the report that came out of it.
class TherapySession {
  const TherapySession({
    required this.id,
    required this.number,
    required this.studentId,
    required this.enrollmentId,
    required this.specialty,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.status,
    required this.reportStatus,
    this.specialistId,
    this.absenceReason,
    this.mood,
    this.activities,
    this.progress,
    this.difficulties,
    this.homePlan,
    this.privateNotes,
    this.hasPrivateNote = false,
    this.publishedAt,
    this.isRead,
    this.student,
    this.specialist,
    this.planSummary,
    this.ratings = const [],
    this.attachments = const [],
    this.addenda = const [],
    this.readBy = const [],
    this.ratingsCount,
    this.attachmentsCount,
  });

  final int id;
  final String number;
  final int studentId;
  final int enrollmentId;
  final int? specialistId;
  final String specialty;
  final String scheduledAt;
  final int durationMinutes;
  final String status;
  final String? absenceReason;

  final String? mood;
  final String? activities;
  final String? progress;
  final String? difficulties;
  final String? homePlan;

  /// Staff only — absent from the payload entirely for a guardian.
  final String? privateNotes;

  /// Staff list rows: whether a note exists, never its text.
  final bool hasPrivateNote;

  final String reportStatus;
  final String? publishedAt;

  /// Guardian list rows only.
  final bool? isRead;

  final Student? student;
  final PersonRef? specialist;
  final String? planSummary;
  final List<GoalRating> ratings;
  final List<Attachment> attachments;
  final List<Addendum> addenda;
  final List<ReadReceipt> readBy;
  final int? ratingsCount;
  final int? attachmentsCount;

  bool get isPublished => reportStatus == 'published';
  bool get isHeld => status == 'held';
  bool get isMissed => status == 'absent' || status == 'excused' || status == 'cancelled';

  /// Held, and still nothing sent — the queue a specialist empties.
  bool get awaitingReport => isHeld && !isPublished;

  factory TherapySession.fromJson(Map<String, dynamic> json) {
    final enrollment = J.map(json['enrollment']);
    return TherapySession(
      id: J.int0(json['id']),
      number: J.s(json['number']),
      studentId: J.int0(json['student_id']),
      enrollmentId: J.int0(json['enrollment_id']),
      specialistId: J.intOrNull(json['specialist_id']),
      specialty: J.s(json['specialty']),
      scheduledAt: J.s(json['scheduled_at']),
      durationMinutes: J.intOrNull(json['duration_minutes']) ?? 45,
      status: J.str(json['status']) ?? 'scheduled',
      absenceReason: J.str(json['absence_reason']),
      mood: J.str(json['mood']),
      activities: J.str(json['activities']),
      progress: J.str(json['progress']),
      difficulties: J.str(json['difficulties']),
      homePlan: J.str(json['home_plan']),
      privateNotes: J.str(json['private_notes']),
      hasPrivateNote: J.boolean(json['has_private_note']),
      reportStatus: J.str(json['report_status']) ?? 'draft',
      publishedAt: J.str(json['published_at']),
      isRead: json.containsKey('is_read') ? J.boolean(json['is_read']) : null,
      student: J.map(json['student']) == null ? null : Student.fromJson(J.map(json['student'])!),
      specialist: PersonRef.maybe(json['specialist']),
      planSummary: J.str(enrollment?['plan_summary']),
      ratings: J.list(json['ratings'], GoalRating.fromJson),
      attachments: J.list(json['attachments'], Attachment.fromJson),
      addenda: J.list(json['addenda'], Addendum.fromJson),
      readBy: J.list(json['read_by'], ReadReceipt.fromJson),
      ratingsCount: J.intOrNull(json['ratings_count']),
      attachmentsCount: J.intOrNull(json['attachments_count']),
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.studentId,
    required this.senderId,
    required this.body,
    this.createdAt,
    this.readAt,
    this.sender,
    this.sessionId,
    this.sessionNumber,
    this.sessionAt,
  });

  final int id;
  final int studentId;
  final int senderId;
  final String body;
  final String? createdAt;
  final String? readAt;
  final PersonRef? sender;
  final int? sessionId;
  final String? sessionNumber;
  final String? sessionAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final session = J.map(json['session']);
    return ChatMessage(
      id: J.int0(json['id']),
      studentId: J.int0(json['student_id']),
      senderId: J.int0(json['sender_id']),
      body: J.s(json['body']),
      createdAt: J.str(json['created_at']),
      readAt: J.str(json['read_at']),
      sender: PersonRef.maybe(json['sender']),
      sessionId: J.intOrNull(session?['id']),
      sessionNumber: J.str(session?['number']),
      sessionAt: J.str(session?['scheduled_at']),
    );
  }
}

/// A thread with something unread in it — `GET /messages/unread`.
class UnreadThread {
  const UnreadThread({required this.studentId, required this.studentName, required this.unread, this.lastAt});

  final int studentId;
  final String studentName;
  final int unread;
  final String? lastAt;

  factory UnreadThread.fromJson(Map<String, dynamic> json) => UnreadThread(
        studentId: J.int0(json['student_id']),
        studentName: J.s(json['student_name']),
        unread: J.int0(json['unread']),
        lastAt: J.str(json['last_at']),
      );
}

/// التقرير الدوري — the quarter, not the day.
class ProgressReport {
  const ProgressReport({
    required this.id,
    required this.studentId,
    required this.periodStart,
    required this.periodEnd,
    required this.summary,
    required this.status,
    this.enrollmentId,
    this.achieved,
    this.recommendations,
    this.homeProgram,
    this.publishedAt,
    this.student,
    this.author,
    this.specialty,
  });

  final int id;
  final int studentId;
  final int? enrollmentId;
  final String periodStart;
  final String periodEnd;
  final String summary;
  final String? achieved;
  final String? recommendations;
  final String? homeProgram;
  final String status;
  final String? publishedAt;
  final Student? student;
  final PersonRef? author;
  final String? specialty;

  bool get isPublished => status == 'published';

  factory ProgressReport.fromJson(Map<String, dynamic> json) => ProgressReport(
        id: J.int0(json['id']),
        studentId: J.int0(json['student_id']),
        enrollmentId: J.intOrNull(json['enrollment_id']),
        periodStart: J.s(json['period_start']),
        periodEnd: J.s(json['period_end']),
        summary: J.s(json['summary']),
        achieved: J.str(json['achieved']),
        recommendations: J.str(json['recommendations']),
        homeProgram: J.str(json['home_program']),
        status: J.str(json['status']) ?? 'draft',
        publishedAt: J.str(json['published_at']),
        student: J.map(json['student']) == null ? null : Student.fromJson(J.map(json['student'])!),
        author: PersonRef.maybe(json['author']),
        specialty: J.str(J.map(json['enrollment'])?['specialty']),
      );
}

class Attendance {
  const Attendance({
    required this.windowDays,
    required this.held,
    required this.absent,
    required this.excused,
    required this.expected,
    this.rate,
  });

  final int windowDays;
  final int held;
  final int absent;
  final int excused;
  final int expected;
  final int? rate;

  factory Attendance.fromJson(Map<String, dynamic> json) => Attendance(
        windowDays: J.intOrNull(json['window_days']) ?? 90,
        held: J.int0(json['held']),
        absent: J.int0(json['absent']),
        excused: J.int0(json['excused']),
        expected: J.int0(json['expected']),
        rate: J.intOrNull(json['rate']),
      );
}

class LastSession {
  const LastSession({
    required this.id,
    required this.scheduledAt,
    required this.status,
    required this.reportStatus,
    this.specialty,
  });

  final int id;
  final String scheduledAt;
  final String status;
  final String reportStatus;
  final String? specialty;

  static LastSession? maybe(Object? json) {
    final map = J.map(json);
    if (map == null) return null;
    return LastSession(
      id: J.int0(map['id']),
      scheduledAt: J.s(map['scheduled_at']),
      status: J.s(map['status']),
      reportStatus: J.s(map['report_status']),
      specialty: J.str(map['specialty']),
    );
  }
}

/// The child's file, summarised — `Progress::studentSummary` on the server.
class StudentSummary {
  const StudentSummary({
    required this.attendance,
    required this.goalsActive,
    required this.goalsAchieved,
    required this.goalsMoving,
    this.lastSession,
    this.nextSession,
    this.unwrittenReports,
  });

  final Attendance attendance;
  final int goalsActive;
  final int goalsAchieved;
  final int goalsMoving;
  final LastSession? lastSession;
  final String? nextSession;
  final int? unwrittenReports;

  factory StudentSummary.fromJson(Map<String, dynamic> json) {
    final goals = J.map(json['goals']) ?? const {};
    return StudentSummary(
      attendance: Attendance.fromJson(J.map(json['attendance']) ?? const {}),
      goalsActive: J.int0(goals['active']),
      goalsAchieved: J.int0(goals['achieved']),
      goalsMoving: J.int0(goals['moving']),
      lastSession: LastSession.maybe(json['last_session']),
      nextSession: J.str(json['next_session']),
      unwrittenReports: J.intOrNull(json['unwritten_reports']),
    );
  }
}

class CurvePoint {
  const CurvePoint({
    required this.date,
    required this.session,
    required this.level,
    required this.levelLabel,
    this.trials,
    this.successes,
    this.rate,
    this.note,
  });

  final String date;
  final String session;
  final int level;
  final String levelLabel;
  final int? trials;
  final int? successes;
  final int? rate;
  final String? note;

  factory CurvePoint.fromJson(Map<String, dynamic> json) => CurvePoint(
        date: J.s(json['date']),
        session: J.s(json['session']),
        level: J.int0(json['level']),
        levelLabel: J.s(json['level_label']),
        trials: J.intOrNull(json['trials']),
        successes: J.intOrNull(json['successes']),
        rate: J.intOrNull(json['rate']),
        note: J.str(json['note']),
      );
}

/// One goal's whole history — `GET /goals/{id}`.
class GoalCurve {
  const GoalCurve({
    required this.goal,
    required this.baselineDate,
    required this.points,
    required this.sessions,
    this.latest,
    this.best,
    this.delta,
    this.trend,
  });

  final Goal goal;
  final String? baselineDate;
  final List<CurvePoint> points;
  final int sessions;
  final int? latest;
  final int? best;
  final int? delta;
  final String? trend;

  factory GoalCurve.fromJson(Map<String, dynamic> json) {
    final summary = J.map(json['summary']) ?? const {};
    return GoalCurve(
      goal: Goal.fromJson(J.map(json['goal']) ?? const {}),
      baselineDate: J.str(J.map(json['baseline_point'])?['date']),
      points: J.list(json['points'], CurvePoint.fromJson),
      sessions: J.int0(summary['sessions']),
      latest: J.intOrNull(summary['latest']),
      best: J.intOrNull(summary['best']),
      delta: J.intOrNull(summary['delta']),
      trend: J.str(summary['trend']),
    );
  }
}

/// An account, as the office's list shows it.
class Account {
  const Account({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.isActive,
    this.phone,
    this.specialty,
    this.title,
    this.lastSeenAt,
    this.childrenCount,
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final String role;
  final String? specialty;
  final String? title;
  final bool isActive;
  final String? lastSeenAt;
  final int? childrenCount;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: J.int0(json['id']),
        name: J.s(json['name']),
        email: J.s(json['email']),
        phone: J.str(json['phone']),
        role: J.s(json['role']),
        specialty: J.str(json['specialty']),
        title: J.str(json['title']),
        isActive: json.containsKey('is_active') ? J.boolean(json['is_active']) : true,
        lastSeenAt: J.str(json['last_seen_at']),
        childrenCount: J.intOrNull(json['children_count']),
      );
}
