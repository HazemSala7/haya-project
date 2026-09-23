export type Role = "admin" | "specialist" | "guardian";

export type Specialty = "speech" | "occupational" | "behavioral" | "special_ed";

/** 4 مستقل · 3 تلميح لفظي · 2 مساعدة جزئية · 1 مساعدة كاملة · 0 رفض */
export type Level = 0 | 1 | 2 | 3 | 4;

export type SessionStatus = "scheduled" | "held" | "absent" | "excused" | "cancelled";

export type ReportStatus = "draft" | "published";

export type Mood = "calm" | "happy" | "tired" | "agitated" | "crying" | "resistant";

export type Profile = {
  id: number;
  name: string;
  email: string;
  phone: string | null;
  role: Role;
  role_label: string;
  title: string | null;
  specialty: Specialty | null;
  specialty_label: string | null;
  is_staff: boolean;
  /** Guardians only — every child this login opens. */
  children?: {
    id: number;
    name: string;
    file_number: string;
    status: string;
    relation: string;
  }[];
};

export type Student = {
  id: number;
  file_number: string;
  name: string;
  birth_date: string;
  age_label: string;
  gender: "male" | "female";
  national_id: string | null;
  diagnosis: string | null;
  diagnosis_notes: string | null;
  medical_alert: string | null;
  school: string | null;
  grade: string | null;
  enrolled_at: string;
  status: "active" | "paused" | "graduated" | "withdrawn";
  left_at: string | null;
  notes: string | null;
  enrollments_count?: number;
  enrollments?: Enrollment[];
  guardians?: Guardian[];
};

export type Guardian = {
  id: number;
  name: string;
  phone: string | null;
  email: string;
  pivot?: { relation: string; is_primary: boolean };
};

export type StaffMember = {
  id: number;
  name: string;
  email: string;
  phone: string | null;
  role: Role;
  specialty: Specialty | null;
  title: string | null;
  is_active: boolean;
  last_seen_at: string | null;
  children_count?: number;
};

export type Enrollment = {
  id: number;
  student_id: number;
  specialty: Specialty;
  specialty_label: string;
  specialist_id: number | null;
  sessions_per_week: number;
  session_minutes: number;
  started_at: string;
  ended_at: string | null;
  status: "active" | "paused" | "ended";
  plan_summary: string | null;
  specialist?: { id: number; name: string; title: string | null } | null;
  student?: Pick<Student, "id" | "name" | "file_number" | "medical_alert">;
  goals_count?: number;
  sessions_count?: number;
};

export type Goal = {
  id: number;
  student_id: number;
  enrollment_id: number;
  title: string;
  description: string | null;
  criteria: string | null;
  baseline: Level;
  target: Level;
  status: "active" | "achieved" | "paused" | "dropped";
  started_at: string;
  achieved_at: string | null;
  sort_order: number;
  enrollment?: { id: number; specialty: Specialty };
  student?: Pick<Student, "id" | "name" | "file_number">;
  /** Added by the list endpoint — latest score and distance from baseline. */
  trend?: { latest: Level | null; delta: number | null; ratings: number };
};

export type GoalRating = {
  id: number;
  goal_id: number;
  level: Level;
  level_label: string;
  trials: number | null;
  successes: number | null;
  note: string | null;
  goal?: Pick<Goal, "id" | "title" | "criteria" | "baseline" | "target" | "status">;
};

export type Attachment = {
  id: number;
  original_name: string;
  mime: string;
  size: number;
  caption: string | null;
  kind: "image" | "video";
};

export type Addendum = {
  id: number;
  body: string;
  created_at: string;
  author?: { id: number; name: string } | null;
};

export type TherapySession = {
  id: number;
  number: string;
  student_id: number;
  enrollment_id: number;
  specialist_id: number | null;
  specialty: Specialty;
  scheduled_at: string;
  duration_minutes: number;
  status: SessionStatus;
  absence_reason: string | null;

  mood: Mood | null;
  activities: string | null;
  progress: string | null;
  difficulties: string | null;
  home_plan: string | null;

  /** Staff only. Absent from the payload entirely for a guardian. */
  private_notes?: string | null;
  /** Staff only, on list rows: whether a note exists, never its text. */
  has_private_note?: boolean;

  report_status: ReportStatus;
  published_at: string | null;

  /** Guardian list rows only. */
  is_read?: boolean;

  student?: Pick<Student, "id" | "name" | "file_number" | "medical_alert" | "birth_date" | "diagnosis">;
  specialist?: { id: number; name: string; title: string | null } | null;
  enrollment?: Pick<Enrollment, "id" | "specialty" | "plan_summary">;
  ratings?: GoalRating[];
  attachments?: Attachment[];
  addenda?: Addendum[];
  ratings_count?: number;
  attachments_count?: number;
  /** Staff only — who in the family has opened it. */
  read_by?: { name: string | null; read_at: string | null }[];
};

export type Message = {
  id: number;
  student_id: number;
  sender_id: number;
  therapy_session_id: number | null;
  body: string;
  read_at: string | null;
  created_at: string;
  sender?: { id: number; name: string; role: Role; title: string | null };
  session?: { id: number; number: string; scheduled_at: string } | null;
};

export type ProgressReport = {
  id: number;
  student_id: number;
  enrollment_id: number | null;
  period_start: string;
  period_end: string;
  summary: string;
  achieved: string | null;
  recommendations: string | null;
  home_program: string | null;
  status: ReportStatus;
  published_at: string | null;
  student?: Pick<Student, "id" | "name" | "file_number" | "birth_date" | "diagnosis">;
  author?: { id: number; name: string; title: string | null } | null;
  enrollment?: { id: number; specialty: Specialty; plan_summary?: string | null } | null;
};

export type Attendance = {
  window_days: number;
  held: number;
  absent: number;
  excused: number;
  expected: number;
  rate: number | null;
};

export type StudentSummary = {
  attendance: Attendance;
  goals: { active: number; achieved: number; moving: number };
  last_session: {
    id: number;
    number: string;
    scheduled_at: string;
    status: SessionStatus;
    report_status: ReportStatus;
    specialty: Specialty;
  } | null;
  next_session: string | null;
  unwritten_reports?: number;
};

export type CurvePoint = {
  date: string;
  session: string;
  level: Level;
  level_label: string;
  trials: number | null;
  successes: number | null;
  rate: number | null;
  note: string | null;
};

export type GoalCurve = {
  goal: Pick<
    Goal,
    | "id"
    | "student_id"
    | "title"
    | "criteria"
    | "baseline"
    | "target"
    | "status"
    | "started_at"
    | "achieved_at"
  >;
  baseline_point: { date: string | null; level: Level };
  points: CurvePoint[];
  summary: {
    sessions: number;
    latest: Level | null;
    best: Level | null;
    delta: number | null;
    trend: "improving" | "steady" | "declining" | null;
  };
};

export type GuardianDashboard = {
  kind: "guardian";
  children: {
    id: number;
    name: string;
    file_number: string;
    age_label: string;
    status: string;
    programmes: { id: number; specialty: Specialty; specialty_label: string; specialist: string | null }[];
    summary: StudentSummary;
    unread_reports: number;
  }[];
  unread_messages: number;
};

export type SpecialistDashboard = {
  kind: "specialist";
  today: TherapySession[];
  stats: {
    today_total: number;
    today_held: number;
    students: number;
    unwritten: number;
    oldest_unwritten: string | null;
    unread_messages: number;
  };
  queue: TherapySession[];
};

export type AdminDashboard = {
  kind: "admin";
  stats: {
    students: number;
    specialists: number;
    guardians: number;
    sessions_today: number;
    unwritten: number;
    unassigned: number;
    unanswered: number;
    attendance_rate: number | null;
    absent_week: number;
  };
  queue: TherapySession[];
  silent_families: {
    id: number;
    name: string;
    phone: string | null;
    last_seen_at: string | null;
    children: { id: number; name: string }[];
  }[];
};

export type Dashboard = GuardianDashboard | SpecialistDashboard | AdminDashboard;

export type Analytics = {
  window_weeks: number;
  weekly: {
    week: string;
    held: number;
    absent: number;
    excused: number;
    cancelled: number;
    expected: number;
    rate: number | null;
  }[];
  by_specialty: {
    specialty: Specialty;
    label: string;
    sessions: number;
    held: number;
    missed: number;
    students: number;
  }[];
  moods: { mood: Mood; count: number }[];
  turnaround: {
    buckets: {
      same_day: number;
      next_day: number;
      within_3: number;
      within_7: number;
      later: number;
    };
    published: number;
    median_days: number | null;
  };
  levels: { level: Level; label: string; count: number }[];
  level_trend: { week: string; avg: number | null; count: number }[];
  specialists: {
    id: number;
    name: string;
    title: string | null;
    is_active: boolean;
    sessions: number;
    held: number;
    students: number;
    unwritten: number;
  }[];
  engagement: { total: number; opened: number; unopened: number; rate: number | null };
};

/** One badge: how many there are, and how many are waiting for a person. */
export type NavCount = { total: number; attention: number };

/** Keyed by the nav item's `count` name — absent keys simply draw nothing. */
export type NavCounts = Partial<Record<
  "home" | "sessions" | "students" | "reports" | "messages" | "staff",
  NavCount
>>;
