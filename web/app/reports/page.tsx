"use client";

import { useEffect, useState } from "react";
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
  Textarea,
} from "@/components/ui";
import {
  REPORT_LABELS,
  REPORT_TONES,
  SPECIALTY_FULL,
  date,
  percent,
} from "@/lib/format";
import type { ProgressReport, Student } from "@/lib/types";

/**
 * التقرير الدوري — the arc, where the daily reports are the frames.
 *
 * A parent who has read twenty-four session reports knows what happened on
 * twenty-four days and still cannot answer "is this working?". That question
 * gets asked at the school and at the doctor, and it needs a document.
 */
export default function ReportsPage() {
  const { isStaff } = useAuth();
  const [status, setStatus] = useState("");
  const [writing, setWriting] = useState(false);
  const [open, setOpen] = useState<ProgressReport | null>(null);
  const [editing, setEditing] = useState<ProgressReport | null>(null);
  const [removing, setRemoving] = useState<ProgressReport | null>(null);

  const list = usePagedList<ProgressReport, Record<string, never>>("/progress-reports", {
    status: status || undefined,
  });

  return (
    <>
      <PageHead
        title="التقارير الدورية"
        subtitle={
          isStaff
            ? "ملخّص فترة كاملة لكل طفل — هذا اللي بياخده الأهل للمدرسة وللطبيب."
            : "ملخّص كل فترة: وين كان طفلك، وين صار، وشو الخطوة الجاية."
        }
        action={isStaff && <Button onClick={() => setWriting(true)}>+ تقرير دوري</Button>}
      />

      {isStaff && (
        <Card className="mb-4">
          <div className="grid gap-3 p-4 sm:grid-cols-3">
            <Select value={status} onChange={(e) => setStatus(e.target.value)}>
              <option value="">الكل</option>
              <option value="draft">مسوّدة</option>
              <option value="published">وصل الأهل</option>
            </Select>
          </div>
        </Card>
      )}

      <Card>
        {list.loading ? (
          <Loading />
        ) : list.rows.length === 0 ? (
          <Empty
            title="ما في تقارير دورية"
            hint={isStaff ? "اكتب أول تقرير لطفل." : "رح توصلك أول ما تكتبها الأخصائية."}
          />
        ) : (
          <Table head={["الطفل", "الفترة", "البرنامج", "كتبته", "الحالة", ""]}>
            {list.rows.map((report) => (
              <tr key={report.id}>
                <td className="px-4 py-2.5">
                  <div className="font-semibold text-ink">{report.student?.name}</div>
                  <div className="tabular text-xs text-muted">
                    {report.student?.file_number}
                  </div>
                </td>
                <td className="px-4 py-2.5 text-xs text-muted">
                  {date(report.period_start)} — {date(report.period_end)}
                </td>
                <td className="px-4 py-2.5 text-muted">
                  {report.enrollment
                    ? SPECIALTY_FULL[report.enrollment.specialty]
                    : "كل البرامج"}
                </td>
                <td className="px-4 py-2.5 text-muted">{report.author?.name ?? "—"}</td>
                <td className="px-4 py-2.5">
                  <Badge className={REPORT_TONES[report.status]}>
                    {REPORT_LABELS[report.status]}
                  </Badge>
                </td>
                <td className="px-4 py-2.5 text-left">
                  <div className="flex flex-wrap justify-end gap-x-3 gap-y-1">
                    <RowAction tone="brand" onClick={() => setOpen(report)}>
                      افتح ←
                    </RowAction>
                    {/* A draft is still the academy's own; a published one is
                        the family's copy and the API refuses both edits. */}
                    {isStaff && report.status === "draft" && (
                      <>
                        <RowAction tone="brand" onClick={() => setEditing(report)}>
                          تعديل
                        </RowAction>
                        <RowAction tone="danger" onClick={() => setRemoving(report)}>
                          حذف
                        </RowAction>
                      </>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </Table>
        )}

        <Pager meta={list.meta} onPage={list.setPage} unit="تقرير" />
      </Card>

      <WriteReport open={writing} onClose={() => setWriting(false)} onDone={list.reload} />

      <EditPeriodic report={editing} onClose={() => setEditing(null)} onDone={list.reload} />

      <Confirm
        open={removing !== null}
        onClose={() => setRemoving(null)}
        onConfirm={async () => {
          await api(`/progress-reports/${removing!.id}`, { method: "DELETE" });
          list.reload();
        }}
        title="حذف التقرير الدوري"
        body={
          <>
            حذف تقرير <b>{removing?.student?.name}</b> للفترة {date(removing?.period_start)} —{" "}
            {date(removing?.period_end)}. بينفع طالما هو مسوّدة.
          </>
        }
      />

      <ReadReport
        report={open}
        onClose={() => setOpen(null)}
        onChanged={list.reload}
        mayPublish={isStaff}
      />
    </>
  );
}

/* ---------------------------------------------------------------------- */

function ReadReport({
  report,
  onClose,
  onChanged,
  mayPublish,
}: {
  report: ProgressReport | null;
  onClose: () => void;
  onChanged: () => void;
  mayPublish: boolean;
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  if (!report) return null;

  async function publish() {
    setBusy(true);
    setError(null);

    try {
      await api(`/progress-reports/${report!.id}/publish`, { method: "POST" });
      onChanged();
      onClose();
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(false);
    }
  }

  const sections = [
    { label: "أين هو الآن", value: report.summary },
    { label: "ما أُنجز في الفترة", value: report.achieved },
    { label: "التوصيات", value: report.recommendations },
    { label: "البرنامج المنزلي", value: report.home_program },
  ].filter((s) => s.value);

  return (
    <Modal open onClose={onClose} title="التقرير الدوري" wide>
      <div className="space-y-4">
        <header className="rounded-xl bg-surface px-4 py-3">
          <p className="text-base font-extrabold text-ink">{report.student?.name}</p>
          <p className="mt-0.5 text-xs text-muted">
            {date(report.period_start)} — {date(report.period_end)}
            {report.enrollment && ` · ${SPECIALTY_FULL[report.enrollment.specialty]}`}
          </p>
        </header>

        {sections.map((section) => (
          <section key={section.label}>
            <h3 className="mb-1 text-sm font-extrabold text-ink">{section.label}</h3>
            <p className="report-prose text-ink">{section.value}</p>
          </section>
        ))}

        <footer className="border-t border-line pt-3 text-xs text-muted">
          كتبته <span className="font-bold text-ink">{report.author?.name ?? "—"}</span>
          {report.author?.title && ` · ${report.author.title}`}
        </footer>

        {error && <ErrorNote message={error} />}

        <div className="no-print flex gap-2">
          {mayPublish && report.status === "draft" && (
            <Button className="flex-1" disabled={busy} onClick={publish}>
              {busy ? "عم نبعت…" : "أرسل لولي الأمر"}
            </Button>
          )}
          <Button variant="ghost" onClick={() => window.print()}>
            طباعة
          </Button>
          <Button variant="ghost" onClick={onClose}>
            إغلاق
          </Button>
        </div>
      </div>
    </Modal>
  );
}

/* ---------------------------------------------------------------------- */

/**
 * Writing one.
 *
 * The attendance and goal figures for the child are fetched and shown beside
 * the empty boxes, so the prose is written against the same arithmetic the
 * parent will read underneath it. A report whose words and whose numbers were
 * assembled separately is one that eventually contradicts itself in front of a
 * family.
 */
function WriteReport({
  open,
  onClose,
  onDone,
}: {
  open: boolean;
  onClose: () => void;
  onDone: () => void;
}) {
  const today = new Date().toISOString().slice(0, 10);
  const quarterAgo = new Date(Date.now() - 90 * 864e5).toISOString().slice(0, 10);

  const [students, setStudents] = useState<Student[]>([]);
  const [form, setForm] = useState({
    student_id: "",
    enrollment_id: "",
    period_start: quarterAgo,
    period_end: today,
    summary: "",
    achieved: "",
    recommendations: "",
    home_program: "",
  });
  const [figures, setFigures] = useState<{
    summary: { attendance: { rate: number | null; held: number; absent: number } };
    goals: { id: number; title: string; latest: number | null; delta: number | null }[];
  } | null>(null);
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  useEffect(() => {
    if (!open) return;
    api<{ data: Student[] }>("/students", { query: { per_page: 100, status: "active" } }).then(
      (res) => setStudents(res.data),
    );
  }, [open]);

  useEffect(() => {
    if (!form.student_id) {
      setFigures(null);
      return;
    }

    api<{ data: typeof figures }>("/progress-reports/figures", {
      query: { student_id: form.student_id },
    })
      .then((res) => setFigures(res.data))
      .catch(() => setFigures(null));
  }, [form.student_id]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api("/progress-reports", {
        method: "POST",
        body: {
          ...form,
          student_id: Number(form.student_id),
          enrollment_id: form.enrollment_id ? Number(form.enrollment_id) : null,
        },
      });
      onDone();
      onClose();
      setForm({ ...form, summary: "", achieved: "", recommendations: "", home_program: "" });
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="تقرير دوري جديد" wide>
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <div className="grid gap-3 sm:grid-cols-3">
          <Field label="الطفل *" error={error?.for("student_id")}>
            <Select
              value={form.student_id}
              onChange={(e) => set("student_id", e.target.value)}
              required
            >
              <option value="">اختر الطفل</option>
              {students.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </Select>
          </Field>

          <Field label="من *">
            <Input
              type="date"
              value={form.period_start}
              onChange={(e) => set("period_start", e.target.value)}
              required
            />
          </Field>

          <Field label="إلى *" error={error?.for("period_end")}>
            <Input
              type="date"
              value={form.period_end}
              onChange={(e) => set("period_end", e.target.value)}
              required
            />
          </Field>
        </div>

        {figures && (
          <div className="rounded-xl border border-line bg-surface p-3">
            <p className="text-xs font-semibold text-muted">
              أرقام الفترة — اكتب النصّ وهي قدّامك
            </p>
            <p className="mt-1 text-sm text-ink">
              الحضور {percent(figures.summary.attendance.rate)} ·{" "}
              <span className="tabular">{figures.summary.attendance.held}</span> جلسة تمّت ·{" "}
              <span className="tabular">{figures.summary.attendance.absent}</span> غياب
            </p>
            <ul className="mt-2 space-y-0.5">
              {figures.goals.slice(0, 6).map((goal) => (
                <li key={goal.id} className="text-xs text-muted">
                  {goal.title} —{" "}
                  {goal.latest === null ? (
                    "لسه ما انقاس"
                  ) : (
                    <span className="tabular font-semibold text-ink">
                      {goal.latest}
                      {goal.delta !== null && goal.delta !== 0 && (
                        <span className={goal.delta > 0 ? "text-good" : "text-bad"}>
                          {" "}
                          ({goal.delta > 0 ? "+" : ""}
                          {goal.delta})
                        </span>
                      )}
                    </span>
                  )}
                </li>
              ))}
            </ul>
          </div>
        )}

        <Field label="أين هو الآن *" error={error?.for("summary")}>
          <Textarea
            rows={4}
            value={form.summary}
            onChange={(e) => set("summary", e.target.value)}
            required
          />
        </Field>

        <Field label="ما أُنجز في الفترة">
          <Textarea
            rows={3}
            value={form.achieved}
            onChange={(e) => set("achieved", e.target.value)}
          />
        </Field>

        <Field label="التوصيات">
          <Textarea
            rows={3}
            value={form.recommendations}
            onChange={(e) => set("recommendations", e.target.value)}
          />
        </Field>

        <Field label="البرنامج المنزلي">
          <Textarea
            rows={3}
            value={form.home_program}
            onChange={(e) => set("home_program", e.target.value)}
          />
        </Field>

        <div className="flex gap-2 pt-1">
          <Button type="submit" disabled={busy} className="flex-1">
            {busy ? "عم نحفظ…" : "احفظ كمسوّدة"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            إلغاء
          </Button>
        </div>

        <p className="text-xs text-muted">
          بينحفظ كمسوّدة. بيوصل الأهل لما تفتحه وتضغط «أرسل».
        </p>
      </form>
    </Modal>
  );
}

/* -------------------------------------------------------------------------
 * تعديل تقرير دوري
 * ---------------------------------------------------------------------- */

/**
 * Editing a periodic report — drafts only.
 *
 * The API refuses to touch a published one, and the button that opens this is
 * only drawn for drafts, so the two agree. A report a family has already taken
 * to a school or a doctor cannot change under them.
 */
function EditPeriodic({
  report,
  onClose,
  onDone,
}: {
  report: ProgressReport | null;
  onClose: () => void;
  onDone: () => void;
}) {
  const [form, setForm] = useState<Record<string, string>>({});
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!report) return;
    setError(null);
    setForm({
      period_start: report.period_start?.slice(0, 10) ?? "",
      period_end: report.period_end?.slice(0, 10) ?? "",
      summary: report.summary ?? "",
      achieved: report.achieved ?? "",
      recommendations: report.recommendations ?? "",
      home_program: report.home_program ?? "",
    });
  }, [report]);

  const set = (key: string, value: string) => setForm((f) => ({ ...f, [key]: value }));

  if (!report) return null;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api(`/progress-reports/${report!.id}`, { method: "PUT", body: form });
      onDone();
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title={`تعديل تقرير ${report.student?.name ?? ""}`} wide>
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="من *">
            <Input
              type="date"
              value={form.period_start ?? ""}
              onChange={(e) => set("period_start", e.target.value)}
              required
            />
          </Field>
          <Field label="إلى *" error={error?.for("period_end")}>
            <Input
              type="date"
              value={form.period_end ?? ""}
              onChange={(e) => set("period_end", e.target.value)}
              required
            />
          </Field>
        </div>

        <Field label="أين هو الآن *" error={error?.for("summary")}>
          <Textarea
            rows={4}
            value={form.summary ?? ""}
            onChange={(e) => set("summary", e.target.value)}
            required
          />
        </Field>

        <Field label="ما أُنجز في الفترة">
          <Textarea
            rows={3}
            value={form.achieved ?? ""}
            onChange={(e) => set("achieved", e.target.value)}
          />
        </Field>

        <Field label="التوصيات">
          <Textarea
            rows={3}
            value={form.recommendations ?? ""}
            onChange={(e) => set("recommendations", e.target.value)}
          />
        </Field>

        <Field label="البرنامج المنزلي">
          <Textarea
            rows={3}
            value={form.home_program ?? ""}
            onChange={(e) => set("home_program", e.target.value)}
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
