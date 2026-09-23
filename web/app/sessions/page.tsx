"use client";

import Link from "next/link";
import { Suspense, useEffect, useState } from "react";
import { useSearchParams } from "next/navigation";
import { ApiError, api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { usePagedList } from "@/lib/paged";
import { PageHead } from "@/components/shell";
import {
  Badge,
  Button,
  Card,
  Confirm,
  Empty,
  ErrorNote,
  Field,
  Input,
  Loading,
  Modal,
  Pager,
  RowAction,
  Select,
  Table,
} from "@/components/ui";
import {
  REPORT_LABELS,
  REPORT_TONES,
  SESSION_LABELS,
  SESSION_TONES,
  SPECIALTY_FULL,
  SPECIALTY_LABELS,
  dayDate,
  relative,
  time,
} from "@/lib/format";
import type { Enrollment, Student, TherapySession } from "@/lib/types";

export default function SessionsPage() {
  return (
    <Suspense fallback={<Loading />}>
      <SessionsList />
    </Suspense>
  );
}

function SessionsList() {
  const { user } = useAuth();
  const params = useSearchParams();

  // The dashboard links here with ?unwritten=1. Seeding the filter from the
  // URL is what makes that link land on the list it promised rather than on
  // everything, with the user left to find the filter themselves.
  const [unwritten, setUnwritten] = useState(params.get("unwritten") === "1");
  const [mine, setMine] = useState(user?.role === "specialist");
  const [status, setStatus] = useState("");
  const [specialty, setSpecialty] = useState("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [booking, setBooking] = useState(false);
  const [removing, setRemoving] = useState<TherapySession | null>(null);

  const list = usePagedList<TherapySession, { unwritten: number | null }>("/sessions", {
    unwritten: unwritten ? 1 : undefined,
    specialist_id: mine ? user?.id : undefined,
    status: status || undefined,
    specialty: specialty || undefined,
    from: from || undefined,
    to: to || undefined,
  });

  return (
    <>
      <PageHead
        title="الجلسات"
        subtitle={
          list.meta?.unwritten
            ? `${list.meta.unwritten} جلسة تمّت وما وصل تقريرها الأهل بعد.`
            : "كل الجلسات — المجدولة، اللي تمّت، والغياب."
        }
        action={<Button onClick={() => setBooking(true)}>+ حجز جلسة</Button>}
      />

      <Card className="mb-4">
        <div className="grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-6">
          <label className="flex items-center gap-2 text-sm font-semibold text-ink">
            <input
              type="checkbox"
              checked={unwritten}
              onChange={(e) => setUnwritten(e.target.checked)}
              className="h-4 w-4 accent-[var(--color-brand)]"
            />
            بدون تقرير
          </label>

          {user?.role === "specialist" && (
            <label className="flex items-center gap-2 text-sm font-semibold text-ink">
              <input
                type="checkbox"
                checked={mine}
                onChange={(e) => setMine(e.target.checked)}
                className="h-4 w-4 accent-[var(--color-brand)]"
              />
              جلساتي فقط
            </label>
          )}

          <Select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">كل الحالات</option>
            {Object.entries(SESSION_LABELS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </Select>

          <Select value={specialty} onChange={(e) => setSpecialty(e.target.value)}>
            <option value="">كل التخصصات</option>
            {Object.entries(SPECIALTY_LABELS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </Select>

          <Input type="date" value={from} onChange={(e) => setFrom(e.target.value)} />
          <Input type="date" value={to} onChange={(e) => setTo(e.target.value)} />
        </div>
      </Card>

      <Card>
        {list.loading ? (
          <Loading />
        ) : list.rows.length === 0 ? (
          <Empty
            title="ما في جلسات بهذه الفلاتر"
            hint="جرّب توسّع الفترة أو تشيل الفلاتر."
          />
        ) : (
          <Table head={["الطفل", "الموعد", "التخصص", "الأخصائية", "الحضور", "التقرير", ""]}>
            {list.rows.map((session) => (
              <tr key={session.id}>
                <td className="px-4 py-2.5">
                  <div className="font-semibold text-ink">{session.student?.name}</div>
                  <div className="tabular text-xs text-muted">
                    {session.student?.file_number}
                  </div>
                  {session.student?.medical_alert && (
                    <div className="mt-0.5 text-xs font-semibold text-alert">⚠️ تنبيه طبي</div>
                  )}
                </td>
                <td className="px-4 py-2.5">
                  <div className="text-ink">{dayDate(session.scheduled_at)}</div>
                  <div className="tabular text-xs text-muted">{time(session.scheduled_at)}</div>
                </td>
                <td className="px-4 py-2.5 text-muted">
                  {SPECIALTY_LABELS[session.specialty]}
                </td>
                <td className="px-4 py-2.5 text-muted">
                  {session.specialist?.name ?? (
                    <span className="text-bad">غير مسندة</span>
                  )}
                </td>
                <td className="px-4 py-2.5">
                  <Badge className={SESSION_TONES[session.status]}>
                    {SESSION_LABELS[session.status]}
                  </Badge>
                </td>
                <td className="px-4 py-2.5">
                  {session.status === "held" ? (
                    <div className="flex items-center gap-1.5">
                      <Badge className={REPORT_TONES[session.report_status]}>
                        {REPORT_LABELS[session.report_status]}
                      </Badge>
                      {session.has_private_note && (
                        <span title="فيها ملاحظة خاصة" className="text-xs text-muted">
                          🔒
                        </span>
                      )}
                    </div>
                  ) : (
                    <span className="text-xs text-muted">—</span>
                  )}
                  {session.report_status === "draft" && session.status === "held" && (
                    <div className="mt-0.5 text-xs text-muted">
                      {relative(session.scheduled_at)}
                    </div>
                  )}
                </td>
                <td className="px-4 py-2.5 text-left">
                  <div className="flex flex-wrap justify-end gap-x-3 gap-y-1">
                    <Link
                      href={`/sessions/view?id=${session.id}`}
                      className="text-xs font-bold text-brand"
                    >
                      {session.report_status === "draft" && session.status === "held"
                        ? "اكتب ←"
                        : "افتح ←"}
                    </Link>
                    {/* Only a draft can go. A published report is the family's
                        copy and the API refuses to delete it. */}
                    {session.report_status === "draft" && (
                      <RowAction tone="danger" onClick={() => setRemoving(session)}>
                        حذف
                      </RowAction>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </Table>
        )}

        <Pager meta={list.meta} onPage={list.setPage} unit="جلسة" />
      </Card>

      <BookSession open={booking} onClose={() => setBooking(false)} onDone={list.reload} />

      <Confirm
        open={removing !== null}
        onClose={() => setRemoving(null)}
        onConfirm={async () => {
          await api(`/sessions/${removing!.id}`, { method: "DELETE" });
          list.reload();
        }}
        title="حذف الجلسة"
        body={
          <>
            حذف جلسة <b>{removing?.student?.name}</b> يوم {dayDate(removing?.scheduled_at ?? "")}،
            وكل قياساتها ومرفقاتها معها.
          </>
        }
      />
    </>
  );
}

/* -------------------------------------------------------------------------
 * حجز جلسة
 * ---------------------------------------------------------------------- */

/**
 * Booking a session.
 *
 * The form asks for a child and then a programme, not a specialty and a
 * specialist: the session inherits both from the enrolment, because they are
 * facts about the programme. Letting the form send them is how a speech
 * session ends up filed under occupational therapy on the one day somebody
 * covered — and the specialty is copied onto the row, so it would stay wrong.
 */
function BookSession({
  open,
  onClose,
  onDone,
}: {
  open: boolean;
  onClose: () => void;
  onDone: () => void;
}) {
  const [students, setStudents] = useState<Student[]>([]);
  const [enrollments, setEnrollments] = useState<Enrollment[]>([]);
  const [studentId, setStudentId] = useState("");
  const [enrollmentId, setEnrollmentId] = useState("");
  const [at, setAt] = useState("");
  const [minutes, setMinutes] = useState("");
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!open) return;
    setError(null);

    api<{ data: Student[] }>("/students", { query: { per_page: 200, status: "active" } })
      .then((res) => setStudents(res.data))
      .catch(() => setStudents([]));
  }, [open]);

  // The child's live programmes — one of them is what the session hangs off.
  useEffect(() => {
    if (!studentId) {
      setEnrollments([]);
      setEnrollmentId("");
      return;
    }

    let cancelled = false;

    api<{ data: Enrollment[] }>("/enrollments", {
      query: { student_id: studentId, status: "active", per_page: 50 },
    })
      .then((res) => {
        if (cancelled) return;
        setEnrollments(res.data);
        // One programme is the common case; choosing it for her saves a tap.
        setEnrollmentId(res.data.length === 1 ? String(res.data[0].id) : "");
      })
      .catch(() => !cancelled && setEnrollments([]));

    return () => {
      cancelled = true;
    };
  }, [studentId]);

  const chosen = enrollments.find((e) => String(e.id) === enrollmentId);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api("/sessions", {
        method: "POST",
        body: {
          enrollment_id: Number(enrollmentId),
          scheduled_at: at.replace("T", " ") + ":00",
          duration_minutes: minutes ? Number(minutes) : null,
        },
      });
      onDone();
      onClose();
      setStudentId("");
      setEnrollmentId("");
      setAt("");
      setMinutes("");
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="حجز جلسة">
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <Field label="الطفل *">
          <Select value={studentId} onChange={(e) => setStudentId(e.target.value)} required>
            <option value="">اختر الطفل</option>
            {students.map((s) => (
              <option key={s.id} value={s.id}>
                {s.name} — {s.file_number}
              </option>
            ))}
          </Select>
        </Field>

        <Field
          label="البرنامج *"
          hint={
            studentId && enrollments.length === 0
              ? "هذا الطفل ما عنده برامج شغّالة — افتحله برنامج من ملفه أولاً."
              : "التخصّص والأخصائية بيجوا من البرنامج نفسه."
          }
          error={error?.for("enrollment_id")}
        >
          <Select
            value={enrollmentId}
            onChange={(e) => setEnrollmentId(e.target.value)}
            required
            disabled={!studentId || enrollments.length === 0}
          >
            <option value="">اختر البرنامج</option>
            {enrollments.map((e) => (
              <option key={e.id} value={e.id}>
                {SPECIALTY_FULL[e.specialty]}
                {e.specialist ? ` — ${e.specialist.name}` : " — بلا أخصائية"}
              </option>
            ))}
          </Select>
        </Field>

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="الموعد *" error={error?.for("scheduled_at")}>
            <Input
              type="datetime-local"
              value={at}
              onChange={(e) => setAt(e.target.value)}
              required
            />
          </Field>

          <Field
            label="المدة (دقيقة)"
            hint={chosen ? `الافتراضي ${chosen.session_minutes}` : undefined}
          >
            <Input
              type="number"
              min={5}
              max={240}
              value={minutes}
              onChange={(e) => setMinutes(e.target.value)}
              placeholder={chosen ? String(chosen.session_minutes) : "45"}
            />
          </Field>
        </div>

        <div className="flex gap-2 pt-1">
          <Button type="submit" disabled={busy || !enrollmentId} className="flex-1">
            {busy ? "عم نحجز…" : "احجز"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}
