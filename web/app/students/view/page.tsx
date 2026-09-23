"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ApiError, api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { PageHead } from "@/components/shell";
import { AttendanceBar, AttendanceTable, Figure } from "@/components/charts";
import {
  Badge,
  Button,
  Card,
  Confirm,
  Empty,
  ErrorNote,
  Field,
  Input,
  LevelChip,
  Loading,
  MedicalAlert,
  Modal,
  RowAction,
  Select,
  Stat,
  Table,
  Textarea,
  WithId,
} from "@/components/ui";
import {
  GOAL_LABELS,
  GOAL_TONES,
  LEVEL_LABELS,
  RELATION_LABELS,
  REPORT_LABELS,
  REPORT_TONES,
  SESSION_LABELS,
  SESSION_TONES,
  SPECIALTY_FULL,
  SPECIALTY_LABELS,
  STUDENT_LABELS,
  date,
  dayDate,
  number,
  percent,
  relative,
} from "@/lib/format";
import type { Enrollment, Goal, StaffMember, Student, StudentSummary, TherapySession } from "@/lib/types";

export default function StudentPage() {
  return <WithId>{(id) => <StudentFile id={id} />}</WithId>;
}

function StudentFile({ id }: { id: number }) {
  const { isStaff, can } = useAuth();
  const router = useRouter();

  const [student, setStudent] = useState<Student | null>(null);
  const [summary, setSummary] = useState<StudentSummary | null>(null);
  const [goals, setGoals] = useState<Goal[]>([]);
  const [sessions, setSessions] = useState<TherapySession[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);
  const [addingGoal, setAddingGoal] = useState(false);
  const [editingGoal, setEditingGoal] = useState<Goal | null>(null);
  const [removingGoal, setRemovingGoal] = useState<Goal | null>(null);
  const [programme, setProgramme] = useState<Enrollment | "new" | null>(null);
  const [removingProgramme, setRemovingProgramme] = useState<Enrollment | null>(null);
  const [editingStudent, setEditingStudent] = useState(false);
  const [archiving, setArchiving] = useState(false);
  const [detaching, setDetaching] = useState<{ id: number; name: string } | null>(null);
  const [linkingGuardian, setLinkingGuardian] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await api<{ data: Student; meta: StudentSummary }>(`/students/${id}`);
      setStudent(res.data);
      setSummary(res.meta);

      const [g, s] = await Promise.all([
        api<{ data: Goal[] }>("/goals", { query: { student_id: id, per_page: 50 } }),
        api<{ data: TherapySession[] }>("/sessions", {
          query: { student_id: id, per_page: 12 },
        }),
      ]);

      setGoals(g.data);
      setSessions(s.data);
    } catch (e) {
      if ((e as ApiError).status === 404) setNotFound(true);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) return <Loading boxed rows={5} />;
  if (notFound || !student || !summary) {
    return <Empty boxed title="الملف غير متاح" hint="يمكن يكون مش من ملفاتك." />;
  }

  const { attendance } = summary;

  return (
    <>
      <PageHead
        back={isStaff ? { href: "/students", label: "كل الأطفال" } : undefined}
        title={student.name}
        subtitle={`${student.age_label} · ملف ${student.file_number}${
          student.diagnosis ? ` · ${student.diagnosis}` : ""
        }`}
        action={
          <div className="flex items-center gap-2">
            <Badge
              className={
                student.status === "active" ? "bg-good-soft text-good" : "bg-line/60 text-muted"
              }
            >
              {STUDENT_LABELS[student.status]}
            </Badge>
            <Link
              href={`/messages?student=${student.id}`}
              className="rounded-lg border border-line px-3 py-2 text-sm font-semibold text-muted transition hover:text-brand"
            >
              الرسائل
            </Link>
            {can("admin") && (
              <>
                <Button variant="ghost" onClick={() => setEditingStudent(true)}>
                  تعديل الملف
                </Button>
                <Button variant="danger" onClick={() => setArchiving(true)}>
                  أرشفة
                </Button>
              </>
            )}
          </div>
        }
      />

      <MedicalAlert text={student.medical_alert} />

      <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="نسبة الحضور"
          value={percent(attendance.rate)}
          hint={`آخر ${attendance.window_days} يوم`}
          tone={attendance.rate !== null && attendance.rate < 70 ? "warn" : "plain"}
        />
        <Stat label="أهداف شغّالة" value={number(summary.goals.active)} tone="brand" />
        <Stat
          label="أهداف تحقّقت"
          value={number(summary.goals.achieved)}
          tone={summary.goals.achieved > 0 ? "good" : "plain"}
        />
        {isStaff && summary.unwritten_reports !== undefined ? (
          <Stat
            label="تقارير ما انكتبت"
            value={number(summary.unwritten_reports)}
            tone={summary.unwritten_reports > 0 ? "warn" : "good"}
          />
        ) : (
          <Stat
            label="الجلسة الجاية"
            value={summary.next_session ? dayDate(summary.next_session) : "—"}
          />
        )}
      </div>

      <div className="grid gap-4 lg:grid-cols-[1fr_20rem]">
        <div className="space-y-4">
          {/* ---- programmes ---- */}
          <Card
            title="البرامج"
            hint="الطفل ممكن يكون في أكثر من برنامج، لكل واحد أخصائيته وأهدافه"
            action={
              can("admin") && (
                <Button variant="ghost" onClick={() => setProgramme("new")}>
                  + برنامج
                </Button>
              )
            }
          >
            {(student.enrollments?.length ?? 0) === 0 ? (
              <Empty title="ما في برامج شغّالة" hint="الإدارة بتقدر تسجّله ببرنامج." />
            ) : (
              <ul className="divide-y divide-line-soft">
                {student.enrollments!.map((enrollment) => (
                  <li key={enrollment.id} className="px-4 py-3">
                    <div className="flex flex-wrap items-start justify-between gap-2">
                      <div>
                        <p className="text-sm font-bold text-ink">
                          {SPECIALTY_FULL[enrollment.specialty]}
                        </p>
                        <p className="mt-0.5 text-xs text-muted">
                          {enrollment.specialist ? (
                            <>
                              {enrollment.specialist.name}
                              {enrollment.specialist.title &&
                                ` · ${enrollment.specialist.title}`}
                            </>
                          ) : (
                            <span className="font-semibold text-bad">
                              ما في أخصائية مسندة لهذا البرنامج
                            </span>
                          )}
                        </p>
                      </div>
                      <div className="flex items-center gap-3">
                        <Badge className="bg-brand-soft text-brand">
                          {enrollment.sessions_per_week} جلسة/أسبوع ·{" "}
                          {enrollment.session_minutes} دقيقة
                        </Badge>
                        {isStaff && (
                          <RowAction tone="brand" onClick={() => setProgramme(enrollment)}>
                            تعديل
                          </RowAction>
                        )}
                        {can("admin") && (
                          <RowAction
                            tone="danger"
                            onClick={() => setRemovingProgramme(enrollment)}
                          >
                            حذف
                          </RowAction>
                        )}
                      </div>
                    </div>
                    {enrollment.plan_summary && (
                      <p className="mt-2 text-xs leading-relaxed text-muted">
                        {enrollment.plan_summary}
                      </p>
                    )}
                  </li>
                ))}
              </ul>
            )}
          </Card>

          {/* ---- goals ---- */}
          <Card
            title="الأهداف العلاجية"
            hint="كل هدف بينقاس كل جلسة على سلّم من ٠ إلى ٤ — الخط بيقول وين وصل"
            action={
              isStaff && (
                <Button variant="ghost" onClick={() => setAddingGoal(true)}>
                  + هدف
                </Button>
              )
            }
          >
            {goals.length === 0 ? (
              <Empty
                title="ما في أهداف مكتوبة"
                hint="الهدف الضيّق المقاس هو اللي بيخلّي التقدّم شي بينقال."
              />
            ) : (
              <ul className="divide-y divide-line-soft">
                {goals.map((goal) => (
                  <li key={goal.id}>
                    {/*
                      The row is a link to the curve, and the two buttons sit
                      inside it. Nesting a button in an anchor means a click on
                      "delete" also navigates, so the wrapper stops the event
                      before the anchor ever sees it.
                    */}
                    <Link
                      href={`/goals/view?id=${goal.id}`}
                      className="flex items-center gap-4 px-4 py-3 transition hover:bg-brand-soft/45"
                      onClick={(event) => {
                        if ((event.target as HTMLElement).closest("button")) {
                          event.preventDefault();
                        }
                      }}
                    >
                      <div className="min-w-0 flex-1">
                        <p className="text-sm font-semibold text-ink">{goal.title}</p>
                        <p className="mt-0.5 text-xs text-muted">
                          {goal.enrollment && SPECIALTY_LABELS[goal.enrollment.specialty]}
                          {goal.criteria && ` · ${goal.criteria}`}
                        </p>
                      </div>

                      {/*
                        Where he started and where he is — not a sparkline.
                        The list endpoint carries only the latest rating, so a
                        line drawn here would have two points and would read as
                        a trajectory that was never measured.
                      */}
                      <div className="hidden items-center gap-1.5 sm:flex">
                        <LevelChip level={goal.baseline} size="sm" />
                        <span aria-hidden className="text-xs text-muted">
                          ←
                        </span>
                        {goal.trend?.latest !== null && goal.trend?.latest !== undefined ? (
                          <LevelChip level={goal.trend.latest} size="sm" />
                        ) : (
                          <span className="text-xs text-muted">لسه ما انقاس</span>
                        )}
                      </div>

                      <div className="flex flex-col items-end gap-1">
                        {isStaff && (
                          <span className="flex gap-2">
                            <RowAction
                              tone="brand"
                              onClick={(() => setEditingGoal(goal)) as () => void}
                            >
                              تعديل
                            </RowAction>
                            <RowAction
                              tone="danger"
                              onClick={(() => setRemovingGoal(goal)) as () => void}
                            >
                              حذف
                            </RowAction>
                          </span>
                        )}
                        {goal.trend?.delta !== null && goal.trend?.delta !== undefined && (
                          <span
                            className={`tabular text-xs font-bold ${
                              goal.trend.delta > 0
                                ? "text-good"
                                : goal.trend.delta < 0
                                  ? "text-bad"
                                  : "text-muted"
                            }`}
                          >
                            {goal.trend.delta > 0 ? "+" : ""}
                            {goal.trend.delta}
                          </span>
                        )}
                        <Badge className={GOAL_TONES[goal.status]}>
                          {GOAL_LABELS[goal.status]}
                        </Badge>
                      </div>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          {/* ---- the timeline ---- */}
          <Card
            title="آخر الجلسات"
            action={
              isStaff && (
                <Link
                  href={`/sessions?student=${student.id}`}
                  className="text-xs font-semibold text-brand"
                >
                  الكل ←
                </Link>
              )
            }
          >
            {sessions.length === 0 ? (
              <Empty title="ما في جلسات بعد" />
            ) : (
              <ul className="divide-y divide-line-soft">
                {sessions.map((session) => (
                  <li key={session.id}>
                    <Link
                      href={`/sessions/view?id=${session.id}`}
                      className="flex items-start gap-3 px-4 py-3 transition hover:bg-brand-soft/45"
                    >
                      <div className="min-w-0 flex-1">
                        <div className="flex flex-wrap items-center gap-2">
                          <span className="text-sm font-semibold text-ink">
                            {dayDate(session.scheduled_at)}
                          </span>
                          <Badge className={SESSION_TONES[session.status]}>
                            {SESSION_LABELS[session.status]}
                          </Badge>
                          {session.status === "held" && isStaff && (
                            <Badge className={REPORT_TONES[session.report_status]}>
                              {REPORT_LABELS[session.report_status]}
                            </Badge>
                          )}
                          {session.is_read === false && (
                            <Badge className="bg-brand text-white">جديد</Badge>
                          )}
                        </div>
                        <p className="mt-0.5 text-xs text-muted">
                          {SPECIALTY_LABELS[session.specialty]}
                          {session.specialist && ` · ${session.specialist.name}`}
                        </p>
                        {session.absence_reason && (
                          <p className="mt-1 text-xs text-muted">{session.absence_reason}</p>
                        )}
                      </div>
                      <span className="whitespace-nowrap text-xs text-muted">
                        {relative(session.scheduled_at)}
                      </span>
                    </Link>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        </div>

        {/* ---- rail ---- */}
        <aside className="space-y-4">
          <Figure
            title="الحضور"
            hint={`آخر ${attendance.window_days} يوم — الجلسات الملغية من طرف الأكاديمية مش محسوبة`}
            table={
              <AttendanceTable
                held={attendance.held}
                absent={attendance.absent}
                excused={attendance.excused}
                rate={attendance.rate}
              />
            }
          >
            <AttendanceBar
              held={attendance.held}
              absent={attendance.absent}
              excused={attendance.excused}
            />
          </Figure>

          <Card
            title="الأهل"
            action={
              can("admin") && (
                <Button variant="ghost" onClick={() => setLinkingGuardian(true)}>
                  + ربط
                </Button>
              )
            }
          >
            {(student.guardians?.length ?? 0) === 0 ? (
              <Empty title="ما في أولياء أمور مربوطين" hint="الإدارة بتقدر تربطهم." />
            ) : (
              <ul className="divide-y divide-line-soft">
                {student.guardians!.map((guardian) => (
                  <li key={guardian.id} className="px-4 py-2.5">
                    <div className="flex items-center justify-between gap-2">
                      <p className="text-sm font-semibold text-ink">{guardian.name}</p>
                      <span className="flex items-center gap-2">
                        {guardian.pivot?.is_primary && (
                          <Badge className="bg-brand-soft text-brand">الأساسي</Badge>
                        )}
                        {can("admin") && (
                          <RowAction
                            tone="danger"
                            onClick={() =>
                              setDetaching({ id: guardian.id, name: guardian.name })
                            }
                          >
                            فكّ الربط
                          </RowAction>
                        )}
                      </span>
                    </div>
                    <p className="text-xs text-muted">
                      {RELATION_LABELS[guardian.pivot?.relation ?? "guardian"]}
                      {guardian.phone && (
                        <>
                          {" · "}
                          <span dir="ltr" className="tabular">
                            {guardian.phone}
                          </span>
                        </>
                      )}
                    </p>
                  </li>
                ))}
              </ul>
            )}
          </Card>

          {isStaff && (
            <Card title="بيانات الملف">
              <dl className="divide-y divide-line text-sm">
                <Row label="تاريخ الميلاد" value={date(student.birth_date)} />
                <Row label="الالتحاق" value={date(student.enrolled_at)} />
                <Row label="المدرسة" value={student.school ?? "—"} />
                <Row label="الصف" value={student.grade ?? "—"} />
              </dl>
              {student.diagnosis_notes && (
                <div className="border-t border-line px-4 py-3">
                  <p className="text-xs font-semibold text-muted">تفاصيل التشخيص</p>
                  <p className="mt-1 text-sm leading-relaxed text-ink">
                    {student.diagnosis_notes}
                  </p>
                </div>
              )}
              {student.notes && (
                <div className="border-t border-line px-4 py-3">
                  <p className="text-xs font-semibold text-muted">ملاحظات</p>
                  <p className="mt-1 text-sm leading-relaxed text-ink">{student.notes}</p>
                </div>
              )}
            </Card>
          )}
        </aside>
      </div>

      <AddGoal
        open={addingGoal}
        onClose={() => setAddingGoal(false)}
        enrollments={student.enrollments ?? []}
        onDone={load}
      />

      <EditGoal goal={editingGoal} onClose={() => setEditingGoal(null)} onDone={load} />

      <ProgrammeForm
        studentId={student.id}
        enrollment={programme}
        onClose={() => setProgramme(null)}
        onDone={load}
      />

      <EditStudent
        student={editingStudent ? student : null}
        onClose={() => setEditingStudent(false)}
        onDone={load}
      />

      <LinkGuardian
        studentId={linkingGuardian ? student.id : null}
        onClose={() => setLinkingGuardian(false)}
        onDone={load}
      />

      <Confirm
        open={removingGoal !== null}
        onClose={() => setRemovingGoal(null)}
        onConfirm={async () => {
          await api(`/goals/${removingGoal!.id}`, { method: "DELETE" });
          await load();
        }}
        title="حذف الهدف"
        body={
          <>
            حذف <b>{removingGoal?.title}</b>. لو كان عليه قياسات، النظام رح يرفض ويطلب
            توقيفه أو تعليمه محقّقاً — عشان المنحنى ما ينمسح من تحت أهل قرأوه.
          </>
        }
      />

      <Confirm
        open={removingProgramme !== null}
        onClose={() => setRemovingProgramme(null)}
        onConfirm={async () => {
          await api(`/enrollments/${removingProgramme!.id}`, { method: "DELETE" });
          await load();
        }}
        title="حذف البرنامج"
        body={
          <>
            حذف برنامج <b>{removingProgramme && SPECIALTY_FULL[removingProgramme.specialty]}</b>.
            لو عليه جلسات مسجّلة، النظام رح يرفض ويطلب إنهاءه بدل حذفه حتى يضلّ تاريخه محفوظ.
          </>
        }
      />

      <Confirm
        open={detaching !== null}
        onClose={() => setDetaching(null)}
        onConfirm={async () => {
          await api(`/students/${student.id}/guardians/${detaching!.id}`, { method: "DELETE" });
          await load();
        }}
        confirmLabel="فكّ الربط"
        title="فكّ ربط ولي الأمر"
        body={
          <>
            <b>{detaching?.name}</b> ما رح يقدر يشوف ملف {student.name} ولا تقاريره بعد هلق.
            الحساب نفسه بيضلّ موجود.
          </>
        }
      />

      <Confirm
        open={archiving}
        onClose={() => setArchiving(false)}
        onConfirm={async () => {
          await api(`/students/${student.id}`, { method: "DELETE" });
          router.replace("/students");
        }}
        confirmLabel="أرشف الملف"
        title="أرشفة ملف الطالب"
        body={
          <>
            ملف <b>{student.name}</b> بينشال من القوائم — بس ما بينحذف. كل جلساته وأهدافه
            وتقاريره بتضلّ محفوظة، وبتقدر ترجّعه من فلتر «المؤرشفة» بأي وقت.
          </>
        }
      />
    </>
  );
}

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-center justify-between gap-3 px-4 py-2">
      <dt className="text-xs text-muted">{label}</dt>
      <dd className="text-sm font-semibold text-ink">{value}</dd>
    </div>
  );
}

/**
 * A new goal.
 *
 * The baseline is asked for at the start and never editable afterwards — it is
 * the number every curve is measured against, and revising it later would let
 * a goal that went nowhere be made to look like progress.
 */
function AddGoal({
  open,
  onClose,
  enrollments,
  onDone,
}: {
  open: boolean;
  onClose: () => void;
  enrollments: { id: number; specialty: string }[];
  onDone: () => Promise<void>;
}) {
  const [form, setForm] = useState({
    enrollment_id: "",
    title: "",
    criteria: "",
    baseline: "0",
    target: "4",
    description: "",
  });
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api("/goals", {
        method: "POST",
        body: {
          ...form,
          enrollment_id: Number(form.enrollment_id),
          baseline: Number(form.baseline),
          target: Number(form.target),
        },
      });
      setForm({ ...form, title: "", criteria: "", description: "" });
      await onDone();
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="هدف علاجي جديد">
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <Field label="البرنامج *" error={error?.for("enrollment_id")}>
          <Select
            value={form.enrollment_id}
            onChange={(e) => set("enrollment_id", e.target.value)}
            required
          >
            <option value="">اختر البرنامج</option>
            {enrollments.map((e) => (
              <option key={e.id} value={e.id}>
                {SPECIALTY_FULL[e.specialty]}
              </option>
            ))}
          </Select>
        </Field>

        <Field
          label="الهدف *"
          hint="ضيّق ومحدّد: «ينطق /س/ في بداية الكلمة»، مش «تحسين النطق»."
          error={error?.for("title")}
        >
          <Input value={form.title} onChange={(e) => set("title", e.target.value)} required />
        </Field>

        <Field
          label="معيار الإتقان"
          hint="بينكتب قبل ما نعرف النتيجة — عشان «تحقّق» تكون خط انعبر مش رأي."
        >
          <Input
            value={form.criteria}
            onChange={(e) => set("criteria", e.target.value)}
            placeholder="٨ من ١٠ محاولات في ٣ جلسات متتالية"
          />
        </Field>

        <div className="grid gap-3 sm:grid-cols-2">
          <Field
            label="خط البداية *"
            hint="وين هو اليوم. ما بينعدّل بعدين."
          >
            <Select value={form.baseline} onChange={(e) => set("baseline", e.target.value)}>
              {[0, 1, 2, 3, 4].map((l) => (
                <option key={l} value={l}>
                  {l} — {LEVEL_LABELS[l]}
                </option>
              ))}
            </Select>
          </Field>

          <Field label="الهدف المطلوب">
            <Select value={form.target} onChange={(e) => set("target", e.target.value)}>
              {[0, 1, 2, 3, 4].map((l) => (
                <option key={l} value={l}>
                  {l} — {LEVEL_LABELS[l]}
                </option>
              ))}
            </Select>
          </Field>
        </div>

        <Field label="تفاصيل">
          <Textarea
            rows={2}
            value={form.description}
            onChange={(e) => set("description", e.target.value)}
          />
        </Field>

        <div className="flex gap-2 pt-1">
          <Button type="submit" disabled={busy} className="flex-1">
            {busy ? "عم نضيف…" : "أضف الهدف"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/* -------------------------------------------------------------------------
 * البرنامج — create and edit
 * ---------------------------------------------------------------------- */

/**
 * A programme: which specialty, whose caseload, how often.
 *
 * One form for both creating and editing, because the fields are the same and
 * two near-identical dialogs drift apart. `enrollment` is `"new"` to open it
 * empty, a record to edit, or null to keep it shut.
 *
 * The specialist dropdown is filtered to the chosen specialty. The API refuses
 * a mismatch outright — a speech therapist on a sensory-integration case signs
 * reports a mother will read as expert in something she is not — so the list
 * never offers one rather than offering it and being rejected.
 */
function ProgrammeForm({
  studentId,
  enrollment,
  onClose,
  onDone,
}: {
  studentId: number;
  enrollment: Enrollment | "new" | null;
  onClose: () => void;
  onDone: () => Promise<void>;
}) {
  const editing = enrollment !== null && enrollment !== "new";

  const blank = {
    specialty: "",
    specialist_id: "",
    sessions_per_week: "2",
    session_minutes: "45",
    started_at: new Date().toISOString().slice(0, 10),
    status: "active",
    plan_summary: "",
  };

  const [form, setForm] = useState(blank);
  const [specialists, setSpecialists] = useState<StaffMember[]>([]);
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!enrollment) return;
    setError(null);

    if (enrollment === "new") {
      setForm({ ...blank, started_at: new Date().toISOString().slice(0, 10) });
      return;
    }

    setForm({
      specialty: enrollment.specialty,
      specialist_id: enrollment.specialist_id?.toString() ?? "",
      sessions_per_week: String(enrollment.sessions_per_week ?? 2),
      session_minutes: String(enrollment.session_minutes ?? 45),
      started_at: enrollment.started_at?.slice(0, 10) ?? "",
      status: enrollment.status ?? "active",
      plan_summary: enrollment.plan_summary ?? "",
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [enrollment]);

  // Only the people qualified for the chosen programme.
  useEffect(() => {
    if (!enrollment || !form.specialty) {
      setSpecialists([]);
      return;
    }

    let cancelled = false;

    api<{ data: StaffMember[] }>("/staff", {
      query: { role: "specialist", specialty: form.specialty, active: true, per_page: 100 },
    })
      .then((res) => !cancelled && setSpecialists(res.data))
      .catch(() => !cancelled && setSpecialists([]));

    return () => {
      cancelled = true;
    };
  }, [enrollment, form.specialty]);

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  if (!enrollment) return null;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    const body = {
      ...form,
      specialist_id: form.specialist_id ? Number(form.specialist_id) : null,
      sessions_per_week: Number(form.sessions_per_week),
      session_minutes: Number(form.session_minutes),
    };

    try {
      if (editing) {
        await api(`/enrollments/${(enrollment as Enrollment).id}`, { method: "PUT", body });
      } else {
        await api("/enrollments", { method: "POST", body: { ...body, student_id: studentId } });
      }
      await onDone();
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title={editing ? "تعديل البرنامج" : "برنامج جديد"}>
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <Field label="التخصّص *" error={error?.for("specialty")}>
          <Select
            value={form.specialty}
            onChange={(e) => {
              set("specialty", e.target.value);
              set("specialist_id", "");
            }}
            required
            disabled={editing}
          >
            <option value="">اختر التخصّص</option>
            {Object.entries(SPECIALTY_FULL).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </Select>
        </Field>

        <Field
          label="الأخصائية"
          hint="اتركها فاضية لو لسه ما تحدّدت — بتظهر في «برامج بلا أخصائية» على شاشة الإدارة."
          error={error?.for("specialist_id")}
        >
          <Select
            value={form.specialist_id}
            onChange={(e) => set("specialist_id", e.target.value)}
            disabled={!form.specialty}
          >
            <option value="">بلا أخصائية</option>
            {specialists.map((person) => (
              <option key={person.id} value={person.id}>
                {person.name}
                {person.title ? ` — ${person.title}` : ""}
              </option>
            ))}
          </Select>
        </Field>

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="جلسات بالأسبوع">
            <Input
              type="number"
              min={1}
              max={14}
              value={form.sessions_per_week}
              onChange={(e) => set("sessions_per_week", e.target.value)}
            />
          </Field>
          <Field label="مدة الجلسة (دقيقة)">
            <Input
              type="number"
              min={15}
              max={180}
              value={form.session_minutes}
              onChange={(e) => set("session_minutes", e.target.value)}
            />
          </Field>
        </div>

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="تاريخ البدء *">
            <Input
              type="date"
              value={form.started_at}
              onChange={(e) => set("started_at", e.target.value)}
              required
              disabled={editing}
            />
          </Field>

          {editing && (
            <Field label="الحالة">
              <Select value={form.status} onChange={(e) => set("status", e.target.value)}>
                <option value="active">شغّال</option>
                <option value="paused">موقوف مؤقتاً</option>
                <option value="ended">منتهٍ</option>
              </Select>
            </Field>
          )}
        </div>

        <Field label="ملخّص الخطة العلاجية">
          <Textarea
            rows={3}
            value={form.plan_summary}
            onChange={(e) => set("plan_summary", e.target.value)}
            placeholder="وين رايح هذا البرنامج — والأهداف تحته بتقول كيف رح نعرف إنه وصل."
          />
        </Field>

        <div className="flex gap-2 pt-1">
          <Button type="submit" disabled={busy} className="flex-1">
            {busy ? "عم نحفظ…" : editing ? "احفظ" : "أضف البرنامج"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/* -------------------------------------------------------------------------
 * الهدف — edit
 * ---------------------------------------------------------------------- */

/**
 * Editing a goal.
 *
 * `baseline` is shown but never editable. It is the number every curve is
 * measured against, and letting it be revised after the fact would let a goal
 * that went nowhere be made to look like progress by lowering where it
 * started — which is precisely what a parent is trusting this not to do.
 */
function EditGoal({
  goal,
  onClose,
  onDone,
}: {
  goal: Goal | null;
  onClose: () => void;
  onDone: () => Promise<void>;
}) {
  const [form, setForm] = useState({
    title: "",
    criteria: "",
    description: "",
    target: "4",
    status: "active",
  });
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!goal) return;
    setError(null);
    setForm({
      title: goal.title ?? "",
      criteria: goal.criteria ?? "",
      description: goal.description ?? "",
      target: String(goal.target ?? 4),
      status: goal.status ?? "active",
    });
  }, [goal]);

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  if (!goal) return null;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api(`/goals/${goal!.id}`, {
        method: "PUT",
        body: { ...form, target: Number(form.target) },
      });
      await onDone();
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title="تعديل الهدف">
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <Field label="الهدف *" error={error?.for("title")}>
          <Input value={form.title} onChange={(e) => set("title", e.target.value)} required />
        </Field>

        <Field label="معيار الإتقان">
          <Input value={form.criteria} onChange={(e) => set("criteria", e.target.value)} />
        </Field>

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="خط البداية" hint="ما بينعدّل — كل المنحنى مقاس عليه.">
            <Input value={`${goal.baseline} — ${LEVEL_LABELS[goal.baseline]}`} disabled readOnly />
          </Field>

          <Field label="الهدف المطلوب">
            <Select value={form.target} onChange={(e) => set("target", e.target.value)}>
              {[0, 1, 2, 3, 4].map((l) => (
                <option key={l} value={l}>
                  {l} — {LEVEL_LABELS[l]}
                </option>
              ))}
            </Select>
          </Field>
        </div>

        <Field label="الحالة">
          <Select value={form.status} onChange={(e) => set("status", e.target.value)}>
            <option value="active">شغّال</option>
            <option value="achieved">تحقّق</option>
            <option value="paused">موقوف</option>
            <option value="dropped">أُلغي</option>
          </Select>
        </Field>

        <Field label="تفاصيل">
          <Textarea
            rows={2}
            value={form.description}
            onChange={(e) => set("description", e.target.value)}
          />
        </Field>

        <div className="flex gap-2 pt-1">
          <Button type="submit" disabled={busy} className="flex-1">
            {busy ? "عم نحفظ…" : "احفظ"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/* -------------------------------------------------------------------------
 * ملف الطالب — edit
 * ---------------------------------------------------------------------- */

function EditStudent({
  student,
  onClose,
  onDone,
}: {
  student: Student | null;
  onClose: () => void;
  onDone: () => Promise<void>;
}) {
  const [form, setForm] = useState<Record<string, string>>({});
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!student) return;
    setError(null);
    setForm({
      name: student.name ?? "",
      birth_date: student.birth_date?.slice(0, 10) ?? "",
      gender: student.gender ?? "male",
      national_id: student.national_id ?? "",
      diagnosis: student.diagnosis ?? "",
      diagnosis_notes: student.diagnosis_notes ?? "",
      medical_alert: student.medical_alert ?? "",
      school: student.school ?? "",
      grade: student.grade ?? "",
      enrolled_at: student.enrolled_at?.slice(0, 10) ?? "",
      status: student.status ?? "active",
      left_at: student.left_at?.slice(0, 10) ?? "",
      notes: student.notes ?? "",
    });
  }, [student]);

  const set = (key: string, value: string) => setForm((f) => ({ ...f, [key]: value }));

  if (!student) return null;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api(`/students/${student!.id}`, {
        method: "PUT",
        body: { ...form, left_at: form.left_at || null },
      });
      await onDone();
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title={`تعديل ملف ${student.name}`} wide>
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="اسم الطفل *" error={error?.for("name")}>
            <Input value={form.name ?? ""} onChange={(e) => set("name", e.target.value)} required />
          </Field>

          <Field label="تاريخ الميلاد *" error={error?.for("birth_date")}>
            <Input
              type="date"
              value={form.birth_date ?? ""}
              onChange={(e) => set("birth_date", e.target.value)}
              required
            />
          </Field>

          <Field label="الجنس *">
            <Select value={form.gender ?? "male"} onChange={(e) => set("gender", e.target.value)}>
              <option value="male">ذكر</option>
              <option value="female">أنثى</option>
            </Select>
          </Field>

          <Field label="الحالة">
            <Select value={form.status ?? "active"} onChange={(e) => set("status", e.target.value)}>
              {Object.entries(STUDENT_LABELS).map(([key, label]) => (
                <option key={key} value={key}>
                  {label}
                </option>
              ))}
            </Select>
          </Field>

          <Field label="تاريخ الالتحاق *" error={error?.for("enrolled_at")}>
            <Input
              type="date"
              value={form.enrolled_at ?? ""}
              onChange={(e) => set("enrolled_at", e.target.value)}
              required
            />
          </Field>

          <Field label="تاريخ المغادرة" error={error?.for("left_at")}>
            <Input
              type="date"
              value={form.left_at ?? ""}
              onChange={(e) => set("left_at", e.target.value)}
            />
          </Field>

          <Field label="التشخيص">
            <Input value={form.diagnosis ?? ""} onChange={(e) => set("diagnosis", e.target.value)} />
          </Field>

          <Field label="رقم الهوية">
            <Input
              dir="ltr"
              className="text-left"
              value={form.national_id ?? ""}
              onChange={(e) => set("national_id", e.target.value)}
            />
          </Field>

          <Field label="المدرسة">
            <Input value={form.school ?? ""} onChange={(e) => set("school", e.target.value)} />
          </Field>

          <Field label="الصف">
            <Input value={form.grade ?? ""} onChange={(e) => set("grade", e.target.value)} />
          </Field>
        </div>

        <Field
          label="تنبيه طبي"
          hint="بيطلع كشريط أحمر فوق كل شاشة فيها هذا الطفل — حساسية، أدوية، تشنّجات."
          error={error?.for("medical_alert")}
        >
          <Textarea
            rows={2}
            value={form.medical_alert ?? ""}
            onChange={(e) => set("medical_alert", e.target.value)}
          />
        </Field>

        <Field label="تفاصيل التشخيص">
          <Textarea
            rows={2}
            value={form.diagnosis_notes ?? ""}
            onChange={(e) => set("diagnosis_notes", e.target.value)}
          />
        </Field>

        <Field label="ملاحظات">
          <Textarea
            rows={2}
            value={form.notes ?? ""}
            onChange={(e) => set("notes", e.target.value)}
          />
        </Field>

        <div className="flex gap-2 pt-1">
          <Button type="submit" disabled={busy} className="flex-1">
            {busy ? "عم نحفظ…" : "احفظ"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/* -------------------------------------------------------------------------
 * ربط ولي أمر
 * ---------------------------------------------------------------------- */

/**
 * Attaching an existing guardian account, never creating one here.
 *
 * A mother with two children in the academy must end up with one login that
 * opens both. A "create parent" button on a child's screen is exactly how she
 * ends up with two, each showing her half of her own family.
 */
function LinkGuardian({
  studentId,
  onClose,
  onDone,
}: {
  studentId: number | null;
  onClose: () => void;
  onDone: () => Promise<void>;
}) {
  const [guardians, setGuardians] = useState<StaffMember[]>([]);
  const [userId, setUserId] = useState("");
  const [relation, setRelation] = useState("mother");
  const [primary, setPrimary] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!studentId) return;
    setError(null);

    let cancelled = false;

    api<{ data: StaffMember[] }>("/staff", { query: { role: "guardian", per_page: 200 } })
      .then((res) => !cancelled && setGuardians(res.data))
      .catch(() => !cancelled && setGuardians([]));

    return () => {
      cancelled = true;
    };
  }, [studentId]);

  if (!studentId) return null;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api(`/students/${studentId}/guardians`, {
        method: "POST",
        body: { user_id: Number(userId), relation, is_primary: primary },
      });
      await onDone();
      onClose();
      setUserId("");
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title="ربط ولي أمر بالطفل">
      <form onSubmit={submit} className="space-y-3">
        {error && <ErrorNote message={error} />}

        <Field
          label="حساب ولي الأمر *"
          hint="لو الحساب مش موجود، أنشئه أول من صفحة «الحسابات»."
        >
          <Select value={userId} onChange={(e) => setUserId(e.target.value)} required>
            <option value="">اختر الحساب</option>
            {guardians.map((g) => (
              <option key={g.id} value={g.id}>
                {g.name} — {g.email}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="صلة القرابة *">
          <Select value={relation} onChange={(e) => setRelation(e.target.value)}>
            <option value="mother">الأم</option>
            <option value="father">الأب</option>
            <option value="grandparent">جد/جدة</option>
            <option value="sibling">أخ/أخت</option>
            <option value="guardian">وصي</option>
          </Select>
        </Field>

        <label className="flex items-center gap-2 text-sm font-semibold text-ink">
          <input
            type="checkbox"
            checked={primary}
            onChange={(e) => setPrimary(e.target.checked)}
            className="h-4 w-4 accent-[var(--color-brand)]"
          />
          جهة الاتصال الأولى لهذا الطفل
        </label>

        <div className="flex gap-2 pt-1">
          <Button type="submit" disabled={busy || !userId} className="flex-1">
            {busy ? "عم نربط…" : "اربط"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}
