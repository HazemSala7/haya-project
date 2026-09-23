"use client";

import { useEffect, useState } from "react";
import { ApiError, api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { PageHead } from "@/components/shell";
import {
  Button,
  Card,
  ErrorNote,
  Field,
  Input,
  LevelKey,
  Loading,
  Note,
  Textarea,
} from "@/components/ui";
import { LEVEL_HINTS, LEVEL_LABELS, ROLE_LABELS, levelColor, levelInk } from "@/lib/format";

/**
 * Two things live here: the account's own password, which everybody can
 * change, and the academy's details, which only the office can.
 *
 * The prompt scale is printed at the bottom for everyone. It is the one piece
 * of shared vocabulary the whole system rests on — a specialist scoring a 2
 * and a mother reading a 2 have to mean the same thing by it — and a reference
 * nobody can find is a reference nobody uses.
 */
export default function SettingsPage() {
  const { user, can } = useAuth();

  return (
    <>
      <PageHead title="الإعدادات" subtitle={`${user?.name} · ${user ? ROLE_LABELS[user.role] : ""}`} />

      <div className="grid gap-4 lg:grid-cols-2">
        <ChangePassword />
        {can("admin") && <Academy />}
        <ScaleReference />
      </div>
    </>
  );
}

function ChangePassword() {
  const [form, setForm] = useState({
    current_password: "",
    password: "",
    password_confirmation: "",
  });
  const [error, setError] = useState<ApiError | null>(null);
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState(false);

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);
    setDone(false);

    try {
      await api("/auth/password", { method: "POST", body: form });
      setForm({ current_password: "", password: "", password_confirmation: "" });
      setDone(true);
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card title="كلمة المرور">
      <form onSubmit={submit} className="space-y-3 p-4">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}
        {done && <Note>تم تغيير كلمة المرور. باقي الأجهزة انسجّل خروجها.</Note>}

        <Field label="كلمة المرور الحالية" error={error?.for("current_password")}>
          <Input
            type="password"
            dir="ltr"
            className="text-left"
            value={form.current_password}
            onChange={(e) => set("current_password", e.target.value)}
            required
          />
        </Field>

        <Field label="كلمة المرور الجديدة" error={error?.for("password")}>
          <Input
            type="password"
            dir="ltr"
            className="text-left"
            value={form.password}
            onChange={(e) => set("password", e.target.value)}
            required
            minLength={8}
          />
        </Field>

        <Field label="تأكيد كلمة المرور">
          <Input
            type="password"
            dir="ltr"
            className="text-left"
            value={form.password_confirmation}
            onChange={(e) => set("password_confirmation", e.target.value)}
            required
          />
        </Field>

        <Button type="submit" disabled={busy}>
          {busy ? "لحظة…" : "غيّر كلمة المرور"}
        </Button>

        <p className="text-xs text-muted">
          تغيير كلمة المرور بيسجّل خروج كل الأجهزة التانية — كلمة مرور بتتغيّر والجلسات
          القديمة شغّالة ما تغيّرت شي فعلياً.
        </p>
      </form>
    </Card>
  );
}

function Academy() {
  const [form, setForm] = useState<Record<string, string>>({});
  const [loading, setLoading] = useState(true);
  const [done, setDone] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    api<{ data: Record<string, string | null> }>("/settings")
      .then((res) =>
        setForm(
          Object.fromEntries(Object.entries(res.data).map(([k, v]) => [k, v ?? ""])),
        ),
      )
      .finally(() => setLoading(false));
  }, []);

  const set = (key: string, value: string) => {
    setForm((f) => ({ ...f, [key]: value }));
    setDone(false);
  };

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api("/settings", { method: "PUT", body: form });
      setDone(true);
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(false);
    }
  }

  if (loading) {
    return (
      <Card title="بيانات الأكاديمية">
        <Loading />
      </Card>
    );
  }

  return (
    <Card title="بيانات الأكاديمية" hint="بتظهر على التقارير المطبوعة">
      <form onSubmit={submit} className="space-y-3 p-4">
        {error && <ErrorNote message={error} />}
        {done && <Note>تم الحفظ.</Note>}

        <Field label="اسم الأكاديمية">
          <Input
            value={form.academy_name ?? ""}
            onChange={(e) => set("academy_name", e.target.value)}
          />
        </Field>

        <Field label="الهاتف">
          <Input
            dir="ltr"
            className="text-left"
            value={form.phone ?? ""}
            onChange={(e) => set("phone", e.target.value)}
          />
        </Field>

        <Field label="البريد الإلكتروني">
          <Input
            type="email"
            dir="ltr"
            className="text-left"
            value={form.email ?? ""}
            onChange={(e) => set("email", e.target.value)}
          />
        </Field>

        <Field label="العنوان">
          <Input value={form.address ?? ""} onChange={(e) => set("address", e.target.value)} />
        </Field>

        <Field label="تذييل التقارير">
          <Textarea
            rows={2}
            value={form.report_footer ?? ""}
            onChange={(e) => set("report_footer", e.target.value)}
          />
        </Field>

        <Button type="submit" disabled={busy}>
          {busy ? "عم نحفظ…" : "احفظ"}
        </Button>
      </form>
    </Card>
  );
}

/**
 * The scale, spelled out.
 *
 * The gap between "partial help" and "full help" is where two specialists
 * rating the same child drift apart, and a drifting scale makes every curve
 * drawn from it fiction. So the definitions are written down once, in one
 * place, and shown to everyone — including the parents reading the numbers.
 */
function ScaleReference() {
  return (
    <Card
      title="سلّم القياس"
      hint="نفس الخمس درجات للأخصائية اللي بتقيس ولولي الأمر اللي بيقرأ"
      className="lg:col-span-2"
    >
      <ul className="divide-y divide-line-soft">
        {[4, 3, 2, 1, 0].map((level) => (
          <li key={level} className="flex items-start gap-3 px-4 py-3">
            <span
              className="tabular grid h-8 w-8 shrink-0 place-items-center rounded-lg text-sm font-extrabold"
              style={{ background: levelColor(level), color: levelInk(level) }}
            >
              {level}
            </span>
            <div>
              <p className="text-sm font-bold text-ink">{LEVEL_LABELS[level]}</p>
              <p className="mt-0.5 text-xs text-muted">{LEVEL_HINTS[level]}</p>
            </div>
          </li>
        ))}
      </ul>
      <div className="border-t border-line px-4 py-3">
        <LevelKey />
      </div>
    </Card>
  );
}
