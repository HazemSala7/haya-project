"use client";

import { useEffect, useState } from "react";
import { ApiError, api } from "@/lib/api";
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
  Note,
  Pager,
  RowAction,
  Select,
  Table,
  useDebounced,
} from "@/components/ui";
import { useAuth } from "@/lib/auth";
import { ROLE_LABELS, SPECIALTY_FULL, SPECIALTY_LABELS, relative } from "@/lib/format";
import type { StaffMember, Student } from "@/lib/types";

/**
 * Accounts.
 *
 * Guardian accounts are created here by the office, not by families signing
 * themselves up — a parent who can register unaided can register against any
 * child, and the only thing between a stranger and a disabled child's file
 * would be a form field.
 */
export default function StaffPage() {
  const { user: me } = useAuth();
  const [q, setQ] = useState("");
  const [role, setRole] = useState("");
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<StaffMember | null>(null);
  const [linking, setLinking] = useState<StaffMember | null>(null);
  const [removing, setRemoving] = useState<StaffMember | null>(null);
  const [resetting, setResetting] = useState<StaffMember | null>(null);
  const [password, setPassword] = useState<{ name: string; value: string } | null>(null);

  const search = useDebounced(q);

  const list = usePagedList<StaffMember, Record<string, never>>("/staff", {
    q: search || undefined,
    role: role || undefined,
  });

  async function toggle(user: StaffMember) {
    await api(`/staff/${user.id}`, {
      method: "PUT",
      body: { is_active: !user.is_active },
    });
    list.reload();
  }

  async function reset(user: StaffMember) {
    const res = await api<{ meta: { generated_password: string } }>(
      `/staff/${user.id}/password`,
      { method: "POST", body: {} },
    );
    setPassword({ name: user.name, value: res.meta.generated_password });
  }

  async function remove(user: StaffMember) {
    await api(`/staff/${user.id}`, { method: "DELETE" });
    list.reload();
  }

  return (
    <>
      <PageHead
        title="الحسابات"
        subtitle="الإدارة، الأخصائيات، وأولياء الأمور."
        action={<Button onClick={() => setAdding(true)}>+ حساب جديد</Button>}
      />

      <Card className="mb-4">
        <div className="grid gap-3 p-4 sm:grid-cols-3">
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="ابحث بالاسم أو البريد أو الهاتف…"
          />
          <Select value={role} onChange={(e) => setRole(e.target.value)}>
            <option value="">كل الأدوار</option>
            {Object.entries(ROLE_LABELS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </Select>
        </div>
      </Card>

      <Card>
        {list.loading ? (
          <Loading />
        ) : list.rows.length === 0 ? (
          <Empty title="ما في حسابات بهذه الفلاتر" />
        ) : (
          <Table head={["الاسم", "الدور", "التواصل", "آخر دخول", "الحالة", ""]}>
            {list.rows.map((user) => (
              <tr key={user.id}>
                <td className="px-4 py-2.5">
                  <div className="font-semibold text-ink">{user.name}</div>
                  {user.title && <div className="text-xs text-muted">{user.title}</div>}
                </td>
                <td className="px-4 py-2.5">
                  <Badge
                    className={
                      user.role === "admin"
                        ? "bg-brand-soft text-brand"
                        : user.role === "specialist"
                          ? "bg-good-soft text-good"
                          : "bg-line/60 text-muted"
                    }
                  >
                    {ROLE_LABELS[user.role]}
                  </Badge>
                  {user.specialty && (
                    <div className="mt-0.5 text-xs text-muted">
                      {SPECIALTY_LABELS[user.specialty]}
                    </div>
                  )}
                  {user.role === "guardian" && (
                    <div className="tabular mt-0.5 text-xs text-muted">
                      {user.children_count ?? 0} طفل
                    </div>
                  )}
                </td>
                <td className="px-4 py-2.5">
                  <div dir="ltr" className="text-right text-xs text-muted">
                    {user.email}
                  </div>
                  {user.phone && (
                    <div dir="ltr" className="tabular text-right text-xs text-muted">
                      {user.phone}
                    </div>
                  )}
                </td>
                <td className="px-4 py-2.5 text-xs text-muted">
                  {user.last_seen_at ? relative(user.last_seen_at) : "ولا مرة"}
                </td>
                <td className="px-4 py-2.5">
                  <Badge
                    className={user.is_active ? "bg-good-soft text-good" : "bg-bad-soft text-bad"}
                  >
                    {user.is_active ? "شغّال" : "موقوف"}
                  </Badge>
                </td>
                <td className="px-4 py-2.5 text-left">
                  <div className="flex flex-wrap justify-end gap-x-3 gap-y-1">
                    <RowAction tone="brand" onClick={() => setEditing(user)}>
                      تعديل
                    </RowAction>
                    {user.role === "guardian" && (
                      <RowAction tone="brand" onClick={() => setLinking(user)}>
                        اربط طفل
                      </RowAction>
                    )}
                    <RowAction onClick={() => setResetting(user)}>كلمة مرور</RowAction>
                    <RowAction
                      tone={user.is_active ? "danger" : "brand"}
                      onClick={() => toggle(user)}
                    >
                      {user.is_active ? "أوقف" : "فعّل"}
                    </RowAction>
                    {/* Deleting yourself is the one thing the API will not do,
                        so the button is not offered either. */}
                    {user.id !== me?.id && (
                      <RowAction tone="danger" onClick={() => setRemoving(user)}>
                        حذف
                      </RowAction>
                    )}
                  </div>
                </td>
              </tr>
            ))}
          </Table>
        )}

        <Pager meta={list.meta} onPage={list.setPage} unit="حساب" />
      </Card>

      <AddAccount
        open={adding}
        onClose={() => setAdding(false)}
        onDone={(name, value) => {
          list.reload();
          if (value) setPassword({ name, value });
        }}
      />

      <EditAccount
        user={editing}
        onClose={() => setEditing(null)}
        onDone={list.reload}
      />

      <LinkChild
        guardian={linking}
        onClose={() => setLinking(null)}
        onDone={list.reload}
      />

      <Confirm
        open={resetting !== null}
        onClose={() => setResetting(null)}
        onConfirm={() => reset(resetting!)}
        confirmLabel="عيّن كلمة مرور جديدة"
        tone="primary"
        title="كلمة مرور جديدة"
        body={
          <>
            رح نولّد كلمة مرور جديدة لـ <b>{resetting?.name}</b> وبتظهر لك مرة وحدة.
            كل الأجهزة اللي داخلة بهذا الحساب رح تنسجّل خروج فوراً.
          </>
        }
      />

      <Confirm
        open={removing !== null}
        onClose={() => setRemoving(null)}
        onConfirm={() => remove(removing!)}
        title="حذف الحساب"
        body={
          <>
            حذف حساب <b>{removing?.name}</b> نهائياً.
            {removing?.role === "guardian" ? (
              <> بينفكّ ربطه عن أطفاله، بس ملفاتهم بتضلّ زي ما هي.</>
            ) : (
              <> لو كان اسمه موقّع على جلسات أو برامج، النظام رح يرفض ويطلب توقيفه بدل حذفه.</>
            )}
          </>
        }
      />

      {/* Shown once and never retrievable — the office writes it down or
          reads it out, and a reset is one click away if they lose it. */}
      <Modal
        open={password !== null}
        onClose={() => setPassword(null)}
        title="كلمة المرور"
      >
        {password && (
          <div className="space-y-3">
            <Note>
              كلمة مرور {password.name} — بتظهر مرة وحدة بس. اكتبها أو احكيها إلهم الآن.
            </Note>
            <div
              dir="ltr"
              className="tabular rounded-xl border border-line bg-surface px-4 py-4 text-center text-xl font-bold text-ink"
            >
              {password.value}
            </div>
            <Button className="w-full" onClick={() => setPassword(null)}>
              أخذتها
            </Button>
          </div>
        )}
      </Modal>
    </>
  );
}

function AddAccount({
  open,
  onClose,
  onDone,
}: {
  open: boolean;
  onClose: () => void;
  onDone: (name: string, password: string | null) => void;
}) {
  const empty = {
    name: "",
    email: "",
    role: "guardian",
    phone: "",
    specialty: "",
    title: "",
    password: "",
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
      const res = await api<{ meta: { generated_password: string | null } }>("/staff", {
        method: "POST",
        body: {
          ...form,
          specialty: form.role === "specialist" ? form.specialty : null,
          password: form.password || null,
        },
      });

      onDone(form.name, res.meta.generated_password);
      setForm(empty);
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="حساب جديد">
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <Field label="الدور *">
          <Select value={form.role} onChange={(e) => set("role", e.target.value)}>
            {Object.entries(ROLE_LABELS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </Select>
        </Field>

        <Field label="الاسم *" error={error?.for("name")}>
          <Input value={form.name} onChange={(e) => set("name", e.target.value)} required />
        </Field>

        <Field label="البريد الإلكتروني *" error={error?.for("email")}>
          <Input
            type="email"
            dir="ltr"
            className="text-left"
            value={form.email}
            onChange={(e) => set("email", e.target.value)}
            required
          />
        </Field>

        <Field label="الهاتف">
          <Input
            dir="ltr"
            className="text-left"
            value={form.phone}
            onChange={(e) => set("phone", e.target.value)}
          />
        </Field>

        {form.role === "specialist" && (
          <>
            <Field label="التخصّص *" error={error?.for("specialty")}>
              <Select
                value={form.specialty}
                onChange={(e) => set("specialty", e.target.value)}
                required
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
              label="المسمّى"
              hint="بينطبع تحت اسمها في كل تقرير بيقرأه ولي الأمر."
            >
              <Input
                value={form.title}
                onChange={(e) => set("title", e.target.value)}
                placeholder="أخصائية نطق ولغة"
              />
            </Field>
          </>
        )}

        <Field
          label="كلمة المرور"
          hint="اتركها فاضية ونولّد وحدة قوية — بتظهر مرة وحدة بعد الحفظ."
        >
          <Input
            dir="ltr"
            className="text-left"
            value={form.password}
            onChange={(e) => set("password", e.target.value)}
          />
        </Field>

        <div className="flex gap-2 pt-1">
          <Button type="submit" disabled={busy} className="flex-1">
            {busy ? "عم ننشئ…" : "أنشئ الحساب"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/**
 * Editing an account.
 *
 * The role is not on this form. Flipping a guardian into a specialist would
 * hand that family every child's file in the building while leaving their
 * existing links in place; flipping a specialist into a guardian orphans
 * everything she signed. The API refuses both — the safe path is a new
 * account — so the field is not offered rather than offered and rejected.
 */
function EditAccount({
  user,
  onClose,
  onDone,
}: {
  user: StaffMember | null;
  onClose: () => void;
  onDone: () => void;
}) {
  const [form, setForm] = useState({
    name: "",
    email: "",
    phone: "",
    specialty: "",
    title: "",
  });
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  // Reload the form whenever a different row is opened.
  useEffect(() => {
    if (!user) return;
    setError(null);
    setForm({
      name: user.name ?? "",
      email: user.email ?? "",
      phone: user.phone ?? "",
      specialty: user.specialty ?? "",
      title: user.title ?? "",
    });
  }, [user]);

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  if (!user) return null;

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api(`/staff/${user!.id}`, {
        method: "PUT",
        body: {
          ...form,
          specialty: user!.role === "specialist" ? form.specialty : null,
        },
      });
      onDone();
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title={`تعديل حساب ${user.name}`}>
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <div className="rounded-lg bg-surface px-3 py-2 text-xs text-muted">
          الدور: <b className="text-ink">{ROLE_LABELS[user.role]}</b> — الدور ما بينعدّل، لأن
          تحويل ولي أمر لأخصائية بيفتحله كل ملفات الأطفال، وتحويل أخصائية لولي أمر بيتيّه
          توقيعها عن تقاريرها. لو الدور غلط، أنشئ حساباً جديداً.
        </div>

        <Field label="الاسم *" error={error?.for("name")}>
          <Input value={form.name} onChange={(e) => set("name", e.target.value)} required />
        </Field>

        <Field label="البريد الإلكتروني *" error={error?.for("email")}>
          <Input
            type="email"
            dir="ltr"
            className="text-left"
            value={form.email}
            onChange={(e) => set("email", e.target.value)}
            required
          />
        </Field>

        <Field label="الهاتف" error={error?.for("phone")}>
          <Input
            dir="ltr"
            className="text-left"
            value={form.phone}
            onChange={(e) => set("phone", e.target.value)}
          />
        </Field>

        {user.role === "specialist" && (
          <>
            <Field label="التخصّص *" error={error?.for("specialty")}>
              <Select
                value={form.specialty}
                onChange={(e) => set("specialty", e.target.value)}
                required
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
              label="المسمّى"
              hint="بينطبع تحت اسمها في كل تقرير بيقرأه ولي الأمر."
            >
              <Input value={form.title} onChange={(e) => set("title", e.target.value)} />
            </Field>
          </>
        )}

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

/**
 * Attaching an existing guardian account to a child.
 *
 * Attaching, never creating — a mother with two children here must end up with
 * one login that opens both, and a "create parent" button on a child's screen
 * is how she ends up with two, each showing her half of her family.
 */
function LinkChild({
  guardian,
  onClose,
  onDone,
}: {
  guardian: StaffMember | null;
  onClose: () => void;
  onDone: () => void;
}) {
  const [students, setStudents] = useState<Student[]>([]);
  const [studentId, setStudentId] = useState("");
  const [relation, setRelation] = useState("mother");
  const [primary, setPrimary] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // In an effect, not during render: fetching from the render body sets state
  // mid-render, which React re-enters, and the list is requested on a loop.
  useEffect(() => {
    if (!guardian) return;

    let cancelled = false;

    api<{ data: Student[] }>("/students", { query: { per_page: 100, status: "active" } })
      .then((res) => !cancelled && setStudents(res.data))
      .catch(() => !cancelled && setStudents([]));

    return () => {
      cancelled = true;
    };
  }, [guardian]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api(`/students/${studentId}/guardians`, {
        method: "POST",
        body: { user_id: guardian!.id, relation, is_primary: primary },
      });
      onDone();
      onClose();
      setStudentId("");
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(false);
    }
  }

  if (!guardian) return null;

  return (
    <Modal open onClose={onClose} title={`اربط طفلاً بحساب ${guardian.name}`}>
      <form onSubmit={submit} className="space-y-3">
        {error && <ErrorNote message={error} />}

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
          <Button type="submit" disabled={busy || !studentId} className="flex-1">
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
