"use client";

import Link from "next/link";
import { useState } from "react";
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
  useDebounced,
} from "@/components/ui";
import { SPECIALTY_LABELS, STUDENT_LABELS, date } from "@/lib/format";
import type { Student } from "@/lib/types";

export default function StudentsPage() {
  const { user, can } = useAuth();

  const [q, setQ] = useState("");
  const [status, setStatus] = useState("active");
  const [specialty, setSpecialty] = useState("");
  const [mine, setMine] = useState(false);
  const [archived, setArchived] = useState(false);
  const [adding, setAdding] = useState(false);
  const [acting, setActing] = useState<{ row: Student; kind: "archive" | "restore" } | null>(null);

  const search = useDebounced(q);

  const list = usePagedList<Student, Record<string, never>>("/students", {
    q: search || undefined,
    status: status || undefined,
    specialty: specialty || undefined,
    specialist_id: mine ? user?.id : undefined,
    archived: archived ? 1 : undefined,
  });

  return (
    <>
      <PageHead
        title="الأطفال"
        subtitle="ملفات الأطفال المسجّلين في الأكاديمية."
        action={
          can("admin") && <Button onClick={() => setAdding(true)}>+ تسجيل طفل</Button>
        }
      />

      <Card className="mb-4">
        <div className="grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-4">
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="ابحث بالاسم أو رقم الملف أو التشخيص…"
          />

          <Select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">كل الحالات</option>
            {Object.entries(STUDENT_LABELS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </Select>

          <Select value={specialty} onChange={(e) => setSpecialty(e.target.value)}>
            <option value="">كل البرامج</option>
            {Object.entries(SPECIALTY_LABELS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </Select>

          {user?.role === "specialist" && (
            <label className="flex items-center gap-2 text-sm font-semibold text-ink">
              <input
                type="checkbox"
                checked={mine}
                onChange={(e) => setMine(e.target.checked)}
                className="h-4 w-4 accent-[var(--color-brand)]"
              />
              أطفالي فقط
            </label>
          )}

          {/* Archived files are reachable, not gone — a child who left in June
              is often back in September. */}
          {can("admin") && (
            <label className="flex items-center gap-2 text-sm font-semibold text-ink">
              <input
                type="checkbox"
                checked={archived}
                onChange={(e) => setArchived(e.target.checked)}
                className="h-4 w-4 accent-[var(--color-brand)]"
              />
              الملفات المؤرشفة
            </label>
          )}
        </div>
      </Card>

      <Card>
        {list.loading ? (
          <Loading />
        ) : list.rows.length === 0 ? (
          <Empty title="ما في أطفال بهذه الفلاتر" hint="جرّب تشيل الفلاتر." />
        ) : (
          <Table head={["الطفل", "العمر", "التشخيص", "البرامج", "الحالة", ""]}>
            {list.rows.map((student) => (
              <tr key={student.id}>
                <td className="px-4 py-2.5">
                  <Link
                    href={`/students/view?id=${student.id}`}
                    className="font-semibold text-ink hover:text-brand"
                  >
                    {student.name}
                  </Link>
                  <div className="tabular text-xs text-muted">ملف {student.file_number}</div>
                  {student.medical_alert && (
                    <div className="mt-0.5 text-xs font-semibold text-alert">⚠️ تنبيه طبي</div>
                  )}
                </td>
                <td className="px-4 py-2.5 text-muted">{student.age_label}</td>
                <td className="px-4 py-2.5 text-muted">{student.diagnosis ?? "—"}</td>
                <td className="tabular px-4 py-2.5 text-muted">
                  {student.enrollments_count ?? 0}
                </td>
                <td className="px-4 py-2.5">
                  <Badge
                    className={
                      student.status === "active"
                        ? "bg-good-soft text-good"
                        : "bg-line/60 text-muted"
                    }
                  >
                    {STUDENT_LABELS[student.status]}
                  </Badge>
                </td>
                <td className="px-4 py-2.5 text-left">
                  <div className="flex flex-wrap justify-end gap-x-3 gap-y-1">
                    {!archived && (
                      <Link
                        href={`/students/view?id=${student.id}`}
                        className="text-xs font-bold text-brand"
                      >
                        الملف ←
                      </Link>
                    )}
                    {can("admin") &&
                      (archived ? (
                        <RowAction
                          tone="brand"
                          onClick={() => setActing({ row: student, kind: "restore" })}
                        >
                          استرجاع
                        </RowAction>
                      ) : (
                        <RowAction
                          tone="danger"
                          onClick={() => setActing({ row: student, kind: "archive" })}
                        >
                          أرشفة
                        </RowAction>
                      ))}
                  </div>
                </td>
              </tr>
            ))}
          </Table>
        )}

        <Pager meta={list.meta} onPage={list.setPage} unit="طفل" />
      </Card>

      <AddStudent open={adding} onClose={() => setAdding(false)} onDone={list.reload} />

      <Confirm
        open={acting !== null}
        onClose={() => setActing(null)}
        confirmLabel={acting?.kind === "restore" ? "استرجع" : "أرشف"}
        tone={acting?.kind === "restore" ? "primary" : "danger"}
        title={acting?.kind === "restore" ? "استرجاع الملف" : "أرشفة الملف"}
        onConfirm={async () => {
          if (acting?.kind === "restore") {
            await api(`/students/${acting.row.id}/restore`, { method: "POST" });
          } else {
            await api(`/students/${acting!.row.id}`, { method: "DELETE" });
          }
          list.reload();
        }}
        body={
          acting?.kind === "restore" ? (
            <>
              رجوع ملف <b>{acting?.row.name}</b> للقوائم بكل جلساته وأهدافه زي ما كانت.
            </>
          ) : (
            <>
              ملف <b>{acting?.row.name}</b> بينشال من القوائم — بس ما بينحذف. كل جلساته
              وأهدافه وتقاريره بتضلّ محفوظة، وبتقدر ترجّعه من فلتر «الملفات المؤرشفة».
            </>
          )
        }
      />
    </>
  );
}

function AddStudent({
  open,
  onClose,
  onDone,
}: {
  open: boolean;
  onClose: () => void;
  onDone: () => void;
}) {
  const empty = {
    name: "",
    birth_date: "",
    gender: "male",
    diagnosis: "",
    medical_alert: "",
    school: "",
    grade: "",
    enrolled_at: new Date().toISOString().slice(0, 10),
    notes: "",
  };

  const [form, setForm] = useState(empty);
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api("/students", { method: "POST", body: form });
      setForm(empty);
      onDone();
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="تسجيل طفل جديد" wide>
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="اسم الطفل *" error={error?.for("name")}>
            <Input value={form.name} onChange={(e) => set("name", e.target.value)} required />
          </Field>

          <Field label="تاريخ الميلاد *" error={error?.for("birth_date")}>
            <Input
              type="date"
              value={form.birth_date}
              onChange={(e) => set("birth_date", e.target.value)}
              required
            />
          </Field>

          <Field label="الجنس *">
            <Select value={form.gender} onChange={(e) => set("gender", e.target.value)}>
              <option value="male">ذكر</option>
              <option value="female">أنثى</option>
            </Select>
          </Field>

          <Field label="تاريخ الالتحاق *" error={error?.for("enrolled_at")}>
            <Input
              type="date"
              value={form.enrolled_at}
              onChange={(e) => set("enrolled_at", e.target.value)}
              required
            />
          </Field>

          <Field label="التشخيص" error={error?.for("diagnosis")}>
            <Input
              value={form.diagnosis}
              onChange={(e) => set("diagnosis", e.target.value)}
              placeholder="اضطراب طيف التوحد — درجة متوسطة"
            />
          </Field>

          <Field label="المدرسة">
            <Input value={form.school} onChange={(e) => set("school", e.target.value)} />
          </Field>
        </div>

        <Field
          label="تنبيه طبي"
          hint="حساسية، أدوية، تشنّجات — بيطلع كشريط أحمر فوق كل شاشة فيها هذا الطفل."
          error={error?.for("medical_alert")}
        >
          <Textarea
            rows={2}
            value={form.medical_alert}
            onChange={(e) => set("medical_alert", e.target.value)}
            placeholder="حساسية من الفول السوداني. لا يُعطى أي طعام دون الرجوع للأم."
          />
        </Field>

        <Field label="ملاحظات">
          <Textarea rows={2} value={form.notes} onChange={(e) => set("notes", e.target.value)} />
        </Field>

        <div className="flex gap-2 pt-1">
          <Button type="submit" disabled={busy} className="flex-1">
            {busy ? "عم نسجّل…" : "سجّل الطفل"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}
