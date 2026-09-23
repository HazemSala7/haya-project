"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { ApiError, api, upload } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { PageHead } from "@/components/shell";
import {
  AttachmentTile,
  Badge,
  Button,
  Card,
  Confirm,
  Empty,
  ErrorNote,
  Field,
  Input,
  LevelChip,
  LevelKey,
  Loading,
  MedicalAlert,
  Modal,
  Note,
  Select,
  Textarea,
  WithId,
} from "@/components/ui";
import {
  LEVEL_HINTS,
  LEVEL_LABELS,
  MOOD_FACES,
  MOOD_LABELS,
  REPORT_LABELS,
  REPORT_TONES,
  SESSION_LABELS,
  SESSION_TONES,
  SPECIALTY_FULL,
  date,
  dateTime,
  dayDate,
  levelColor,
  levelInk,
  relative,
  time,
} from "@/lib/format";
import type { Goal, TherapySession } from "@/lib/types";

export default function SessionPage() {
  return <WithId>{(id) => <SessionScreen id={id} />}</WithId>;
}

/* -------------------------------------------------------------------------
 * The five questions
 *
 * Named, ordered, and the same five every day. A single free textarea produces
 * "تمت الجلسة بنجاح" for a year; five questions get five answers, and the
 * mother reading them learns something she did not know.
 * ---------------------------------------------------------------------- */

const BOXES = [
  {
    key: "activities" as const,
    label: "شو عملنا اليوم",
    placeholder: "الأنشطة اللي اشتغلتوا عليها، بالترتيب…",
    required: true,
  },
  {
    key: "progress" as const,
    label: "شو تطوّر",
    placeholder: "أي شي عمله اليوم وما كان بيعمله قبل…",
    required: false,
  },
  {
    key: "difficulties" as const,
    label: "شو الصعوبات اللي واجهناها",
    placeholder: "شو وقف بوجهه، وكيف تعاملتوا معها…",
    required: false,
  },
  {
    key: "home_plan" as const,
    label: "شو بدنا منكم بالبيت",
    placeholder: "تمرين واحد واضح، بوقت محدّد، يقدروا يعملوه…",
    required: true,
  },
];

const MOODS = ["happy", "calm", "tired", "agitated", "crying", "resistant"] as const;

function SessionScreen({ id }: { id: number }) {
  const { user, isStaff } = useAuth();

  const [session, setSession] = useState<TherapySession | null>(null);
  const [goals, setGoals] = useState<Goal[]>([]);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await api<{ data: TherapySession }>(`/sessions/${id}`);
      setSession(res.data);

      if (res.data.report_status === "draft") {
        const g = await api<{ data: Goal[] }>("/goals", {
          query: { enrollment_id: res.data.enrollment_id, status: "active", per_page: 50 },
        });
        setGoals(g.data);
      }
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
  if (notFound || !session) {
    return (
      <Empty
        boxed
        title="التقرير غير متاح"
        hint="يمكن يكون لسه ما انبعت، أو مش من ملفاتك."
        action={
          <Link
            href="/"
            className="rounded-lg bg-brand px-3.5 py-2 text-sm font-semibold text-white shadow-soft transition hover:shadow-glow"
          >
            رجوع للرئيسية
          </Link>
        }
      />
    );
  }

  // The API already refuses a write she is not allowed to make; this is what
  // stops the form being drawn at all, so she is never offered a button that
  // will 403 when she presses it.
  const mayWrite =
    isStaff &&
    (user?.role === "admin" ||
      session.specialist_id === null ||
      session.specialist_id === user?.id);

  return (
    <>
      <PageHead
        back={{ href: isStaff ? "/sessions" : `/students/view?id=${session.student_id}`, label: "رجوع" }}
        title={session.student?.name ?? "الجلسة"}
        subtitle={`${dayDate(session.scheduled_at)} · ${time(session.scheduled_at)} · ${SPECIALTY_FULL[session.specialty]}`}
        action={
          <div className="flex flex-wrap items-center gap-2">
            <Badge className={SESSION_TONES[session.status]}>
              {SESSION_LABELS[session.status]}
            </Badge>
            {session.status === "held" && (
              <Badge className={REPORT_TONES[session.report_status]}>
                {REPORT_LABELS[session.report_status]}
              </Badge>
            )}
          </div>
        }
      />

      <MedicalAlert text={session.student?.medical_alert} />

      {mayWrite && session.report_status === "draft" ? (
        <WriteReport session={session} goals={goals} onSaved={load} />
      ) : (
        <ReadReport session={session} mayWrite={mayWrite} onChanged={load} />
      )}
    </>
  );
}

/* -------------------------------------------------------------------------
 * Writing
 * ---------------------------------------------------------------------- */

function WriteReport({
  session,
  goals,
  onSaved,
}: {
  session: TherapySession;
  goals: Goal[];
  onSaved: () => Promise<void>;
}) {
  const [form, setForm] = useState({
    mood: session.mood ?? "",
    activities: session.activities ?? "",
    progress: session.progress ?? "",
    difficulties: session.difficulties ?? "",
    home_plan: session.home_plan ?? "",
    private_notes: session.private_notes ?? "",
  });

  const [ratings, setRatings] = useState<
    Record<number, { level: number; trials: string; successes: string; note: string }>
  >(() =>
    Object.fromEntries(
      (session.ratings ?? []).map((r) => [
        r.goal_id,
        {
          level: r.level,
          trials: r.trials?.toString() ?? "",
          successes: r.successes?.toString() ?? "",
          note: r.note ?? "",
        },
      ]),
    ),
  );

  const [status, setStatus] = useState(session.status);
  const [absenceReason, setAbsenceReason] = useState(session.absence_reason ?? "");
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);
  const [busy, setBusy] = useState<null | "save" | "publish" | "attend">(null);
  const [removing, setRemoving] = useState(false);
  const router = useRouter();

  const set = (key: keyof typeof form, value: string) => {
    setForm((f) => ({ ...f, [key]: value }));
    setSaved(false);
  };

  async function saveDraft() {
    setBusy("save");
    setError(null);

    try {
      await api(`/sessions/${session.id}`, {
        method: "PUT",
        body: { ...form, mood: form.mood || null },
      });

      await api(`/sessions/${session.id}/ratings`, {
        method: "POST",
        body: {
          ratings: Object.entries(ratings).map(([goalId, r]) => ({
            goal_id: Number(goalId),
            level: r.level,
            trials: r.trials === "" ? null : Number(r.trials),
            successes: r.successes === "" ? null : Number(r.successes),
            note: r.note || null,
          })),
        },
      });

      setSaved(true);
      await onSaved();
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(null);
    }
  }

  async function setAttendance(next: string) {
    setBusy("attend");
    setError(null);

    try {
      await api(`/sessions/${session.id}/attendance`, {
        method: "POST",
        body: { status: next, absence_reason: next === "held" ? null : absenceReason || null },
      });
      setStatus(next as typeof status);
      await onSaved();
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(null);
    }
  }

  async function publish() {
    setBusy("publish");
    setError(null);

    try {
      // Saved first, always. Publishing what is on screen rather than what was
      // last saved is the only behaviour that cannot surprise her.
      await saveDraftQuietly();
      await api(`/sessions/${session.id}/publish`, { method: "POST" });
      await onSaved();
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(null);
    }
  }

  async function saveDraftQuietly() {
    await api(`/sessions/${session.id}`, {
      method: "PUT",
      body: { ...form, mood: form.mood || null },
    });
    await api(`/sessions/${session.id}/ratings`, {
      method: "POST",
      body: {
        ratings: Object.entries(ratings).map(([goalId, r]) => ({
          goal_id: Number(goalId),
          level: r.level,
          trials: r.trials === "" ? null : Number(r.trials),
          successes: r.successes === "" ? null : Number(r.successes),
          note: r.note || null,
        })),
      },
    });
  }

  const missing = [
    !form.activities.trim() && "شو عملنا اليوم",
    !form.home_plan.trim() && "شو بدنا منكم بالبيت",
  ].filter(Boolean) as string[];

  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_20rem]">
      <div className="space-y-4">
        {/* ---- attendance ---- */}
        <Card title="الحضور" hint="علّم شو صار قبل ما تكتب التقرير">
          <div className="flex flex-wrap gap-2 p-4">
            {(["held", "absent", "excused", "cancelled"] as const).map((option) => (
              <button
                key={option}
                type="button"
                disabled={busy === "attend"}
                onClick={() => setAttendance(option)}
                className={`rounded-lg border px-3 py-2 text-sm font-semibold transition disabled:opacity-50 ${
                  status === option
                    ? "border-brand bg-brand text-white"
                    : "border-line bg-panel text-muted hover:text-ink"
                }`}
              >
                {SESSION_LABELS[option]}
              </button>
            ))}
          </div>

          {status !== "held" && status !== "scheduled" && (
            <div className="border-t border-line p-4">
              <Field label="السبب — بيوصل ولي الأمر">
                <Input
                  value={absenceReason}
                  onChange={(e) => setAbsenceReason(e.target.value)}
                  onBlur={() => setAttendance(status)}
                  placeholder="الأم أبلغت — موعد عند الطبيب."
                />
              </Field>
              <p className="mt-2 text-xs text-muted">
                الجلسة اللي ما تمّت بتوصل ولي الأمر مكتوب عليها غياب — بدون تقرير. السكوت
                بيتقرأ إهمال.
              </p>
            </div>
          )}
        </Card>

        {status === "held" && (
          <>
            {/* ---- mood ---- */}
            <Card title="كيف وصل اليوم">
              <div className="flex flex-wrap gap-2 p-4">
                {MOODS.map((mood) => (
                  <button
                    key={mood}
                    type="button"
                    onClick={() => set("mood", form.mood === mood ? "" : mood)}
                    className={`flex items-center gap-2 rounded-lg border px-3 py-2 text-sm font-semibold transition ${
                      form.mood === mood
                        ? "border-brand bg-brand-soft text-brand"
                        : "border-line bg-panel text-muted hover:text-ink"
                    }`}
                  >
                    <span aria-hidden>{MOOD_FACES[mood]}</span>
                    {MOOD_LABELS[mood]}
                  </button>
                ))}
              </div>
            </Card>

            {/* ---- the five boxes ---- */}
            <Card title="التقرير" hint="هاد اللي بيقرأه ولي الأمر — اكتبه كأنك بتحكيله">
              <div className="space-y-4 p-4">
                {BOXES.map((box) => (
                  <Field
                    key={box.key}
                    label={box.required ? `${box.label} *` : box.label}
                    hint={
                      box.key === "home_plan"
                        ? "هاد الجزء الوحيد اللي الأهل بيقدروا يشتغلوا عليه — بدونه التقرير بينقرأ مرة وبس."
                        : undefined
                    }
                  >
                    <Textarea
                      rows={box.key === "activities" || box.key === "home_plan" ? 4 : 3}
                      value={form[box.key]}
                      onChange={(e) => set(box.key, e.target.value)}
                      placeholder={box.placeholder}
                    />
                  </Field>
                ))}
              </div>
            </Card>

            {/* ---- goal ratings ---- */}
            <Card
              title="قياس الأهداف"
              hint="اللي اشتغلتوا عليه اليوم فقط — الهدف اللي ما لمستوه، اتركه فاضي"
            >
              {goals.length === 0 ? (
                <Empty
                  title="ما في أهداف شغّالة"
                  hint="افتح أهداف للبرنامج أولاً من ملف الطفل."
                />
              ) : (
                <div className="divide-y divide-line-soft">
                  {goals.map((goal) => (
                    <GoalRatingRow
                      key={goal.id}
                      goal={goal}
                      value={ratings[goal.id]}
                      onChange={(next) =>
                        setRatings((r) => {
                          if (next === null) {
                            const { [goal.id]: _drop, ...rest } = r;
                            return rest;
                          }
                          return { ...r, [goal.id]: next };
                        })
                      }
                    />
                  ))}
                </div>
              )}
              <div className="border-t border-line px-4 py-3">
                <LevelKey />
              </div>
            </Card>

            {/* ---- attachments ---- */}
            <Attachments session={session} onChanged={onSaved} mayWrite />

            {/* ---- private notes ---- */}
            <Card
              title="ملاحظاتك الخاصة"
              hint="ما بتوصل ولي الأمر أبداً — لا في التقرير ولا في أي شاشة عنده"
            >
              <div className="p-4">
                <Textarea
                  rows={3}
                  value={form.private_notes}
                  onChange={(e) => set("private_notes", e.target.value)}
                  placeholder="ملاحظات إكلينيكية، أو شي بدك تتذكره بالجلسة الجاية…"
                />
              </div>
            </Card>
          </>
        )}
      </div>

      <Confirm
        open={removing}
        onClose={() => setRemoving(false)}
        onConfirm={async () => {
          await api(`/sessions/${session.id}`, { method: "DELETE" });
          router.replace("/sessions");
        }}
        title="حذف الجلسة"
        body="حذف هذه الجلسة وكل قياساتها ومرفقاتها. بينفع طالما التقرير لسه ما وصل الأهل."
      />

      {/* ---- the sticky action rail ---- */}
      <aside className="lg:sticky lg:top-20 lg:self-start">
        <Card title="الإرسال">
          <div className="space-y-3 p-4">
            {error && <ErrorNote message={error} />}
            {saved && <Note>تم الحفظ كمسوّدة. لسه ما وصل الأهل.</Note>}

            {status === "held" ? (
              <>
                {missing.length > 0 && (
                  <div className="rounded-lg border border-warn/30 bg-warn-soft px-3 py-2 text-xs font-medium text-warn">
                    ناقص قبل الإرسال: {missing.join("، ")}
                  </div>
                )}

                <Button
                  variant="ghost"
                  className="w-full"
                  disabled={busy !== null}
                  onClick={saveDraft}
                >
                  {busy === "save" ? "عم نحفظ…" : "حفظ كمسوّدة"}
                </Button>

                <Button
                  className="w-full"
                  disabled={busy !== null || missing.length > 0}
                  onClick={publish}
                >
                  {busy === "publish" ? "عم نبعت…" : "أرسل لولي الأمر"}
                </Button>

                <p className="text-xs text-muted">
                  بعد الإرسال ما بينعدّل التقرير. التصحيح بينضاف كسطر جديد تحته بتاريخه —
                  عشان اللي قرأته الأم امبارح يضلّ نفسه.
                </p>

                <div className="border-t border-line pt-3">
                  <Button
                    variant="danger"
                    className="w-full"
                    disabled={busy !== null}
                    onClick={() => setRemoving(true)}
                  >
                    احذف الجلسة
                  </Button>
                  <p className="mt-2 text-xs text-muted">
                    بينفع طالما التقرير لسه مسوّدة. بعد ما يوصل الأهل، ما بينحذف.
                  </p>
                </div>
              </>
            ) : (
              <p className="text-xs text-muted">
                الجلسة ما تمّت، فما في تقرير يُرسل. ولي الأمر رح يشوف الغياب بسببه.
              </p>
            )}
          </div>
        </Card>
      </aside>
    </div>
  );
}

/**
 * One goal, scored.
 *
 * The five buttons carry the scale's colours and their meaning is written
 * under the selected one — because the gap between "partial" and "full" is
 * where two specialists drift apart, and a drifting scale makes every curve
 * drawn from it fiction.
 */
function GoalRatingRow({
  goal,
  value,
  onChange,
}: {
  goal: Goal;
  value?: { level: number; trials: string; successes: string; note: string };
  onChange: (next: { level: number; trials: string; successes: string; note: string } | null) => void;
}) {
  const active = value !== undefined;

  return (
    <div className={`p-4 ${active ? "bg-brand-soft/25" : ""}`}>
      <div className="flex flex-wrap items-start justify-between gap-2">
        <div className="min-w-0">
          <p className="text-sm font-bold text-ink">{goal.title}</p>
          {goal.criteria && (
            <p className="mt-0.5 text-xs text-muted">معيار الإتقان: {goal.criteria}</p>
          )}
        </div>
        {active && (
          <button
            type="button"
            onClick={() => onChange(null)}
            className="text-xs font-semibold text-muted hover:text-bad"
          >
            ما اشتغلنا عليه
          </button>
        )}
      </div>

      <div className="mt-3 flex flex-wrap gap-1.5">
        {[0, 1, 2, 3, 4].map((level) => {
          const selected = value?.level === level;

          return (
            <button
              key={level}
              type="button"
              onClick={() =>
                onChange({
                  level,
                  trials: value?.trials ?? "",
                  successes: value?.successes ?? "",
                  note: value?.note ?? "",
                })
              }
              className={`flex items-center gap-1.5 rounded-lg border px-2.5 py-1.5 text-xs font-semibold transition ${
                selected ? "border-transparent" : "border-line bg-panel text-muted hover:text-ink"
              }`}
              style={
                selected
                  ? { background: levelColor(level), color: levelInk(level) }
                  : undefined
              }
            >
              <span className="tabular">{level}</span>
              <span>{LEVEL_LABELS[level]}</span>
            </button>
          );
        })}
      </div>

      {active && (
        <>
          <p className="mt-2 text-xs text-muted">{LEVEL_HINTS[value!.level]}</p>

          <div className="mt-3 grid gap-2 sm:grid-cols-3">
            <Field label="عدد المحاولات">
              <Input
                type="number"
                min={0}
                max={999}
                value={value!.trials}
                onChange={(e) => onChange({ ...value!, trials: e.target.value })}
              />
            </Field>
            <Field label="نجح منها">
              <Input
                type="number"
                min={0}
                max={999}
                value={value!.successes}
                onChange={(e) => onChange({ ...value!, successes: e.target.value })}
              />
            </Field>
            <Field label="ملاحظة قصيرة">
              <Input
                value={value!.note}
                onChange={(e) => onChange({ ...value!, note: e.target.value })}
                placeholder="اختياري"
              />
            </Field>
          </div>
        </>
      )}
    </div>
  );
}

/* -------------------------------------------------------------------------
 * Reading
 * ---------------------------------------------------------------------- */

/**
 * What the family opens.
 *
 * Set as prose rather than as a form read-only: this is a letter about their
 * child, and it should look like one. The specialist's name is at the bottom
 * where a signature goes.
 */
function ReadReport({
  session,
  mayWrite,
  onChanged,
}: {
  session: TherapySession;
  mayWrite: boolean;
  onChanged: () => Promise<void>;
}) {
  const { isStaff } = useAuth();
  const [asking, setAsking] = useState(false);
  const [correcting, setCorrecting] = useState(false);

  if (session.status !== "held") {
    return (
      <Card>
        <div className="px-4 py-10 text-center">
          <p className="text-2xl" aria-hidden>
            {session.status === "cancelled" ? "🗓️" : "🚪"}
          </p>
          <p className="mt-2 text-base font-bold text-ink">
            {SESSION_LABELS[session.status]}
          </p>
          {session.absence_reason && (
            <p className="mt-1 text-sm text-muted">{session.absence_reason}</p>
          )}
          <p className="mt-3 text-xs text-muted">
            {dayDate(session.scheduled_at)} · {SPECIALTY_FULL[session.specialty]}
          </p>
        </div>
      </Card>
    );
  }

  const sections = BOXES.map((box) => ({
    ...box,
    value: session[box.key],
  })).filter((s) => s.value);

  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_18rem]">
      <div className="space-y-4">
        <Card className="print-plain">
          <div className="border-b border-line px-5 py-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p className="text-xs text-muted">
                  جلسة <span className="tabular">{session.number}</span> ·{" "}
                  {SPECIALTY_FULL[session.specialty]}
                </p>
                <p className="mt-0.5 text-base font-extrabold text-ink">
                  {dayDate(session.scheduled_at)}
                </p>
              </div>
              {session.mood && (
                <div className="flex items-center gap-2 rounded-lg bg-surface px-3 py-2">
                  <span className="text-lg" aria-hidden>
                    {MOOD_FACES[session.mood]}
                  </span>
                  <span className="text-xs">
                    <span className="block text-muted">وصل اليوم</span>
                    <span className="block font-bold text-ink">{MOOD_LABELS[session.mood]}</span>
                  </span>
                </div>
              )}
            </div>
          </div>

          <div className="space-y-5 px-5 py-5">
            {sections.map((section) => (
              <section key={section.key}>
                <h3
                  className={`mb-1.5 text-sm font-extrabold ${
                    section.key === "home_plan" ? "text-brand" : "text-ink"
                  }`}
                >
                  {section.label}
                </h3>
                <p
                  className={`report-prose text-ink ${
                    section.key === "home_plan"
                      ? "rounded-xl border border-brand/25 bg-brand-soft/50 px-4 py-3"
                      : ""
                  }`}
                >
                  {section.value}
                </p>
              </section>
            ))}

            {sections.length === 0 && (
              <p className="text-sm text-muted">ما في تفاصيل مكتوبة لهذه الجلسة.</p>
            )}
          </div>

          <footer className="flex flex-wrap items-center justify-between gap-2 border-t border-line px-5 py-3">
            <p className="text-xs text-muted">
              كتبته{" "}
              <span className="font-bold text-ink">{session.specialist?.name ?? "—"}</span>
              {session.specialist?.title && ` · ${session.specialist.title}`}
            </p>
            {session.published_at && (
              <p className="text-xs text-muted">وصلكم {relative(session.published_at)}</p>
            )}
          </footer>
        </Card>

        {/* ---- corrections ---- */}
        {(session.addenda?.length ?? 0) > 0 && (
          <Card title="تصحيحات على التقرير">
            <ul className="divide-y divide-line-soft">
              {session.addenda!.map((addendum) => (
                <li key={addendum.id} className="px-5 py-3">
                  <p className="report-prose text-ink">{addendum.body}</p>
                  <p className="mt-1 text-xs text-muted">
                    {addendum.author?.name} · {dateTime(addendum.created_at)}
                  </p>
                </li>
              ))}
            </ul>
          </Card>
        )}

        {/* ---- what was measured ---- */}
        {(session.ratings?.length ?? 0) > 0 && (
          <Card
            title="الأهداف اللي اشتغلنا عليها"
            hint="الرقم بيقول قدّيش احتاج مساعدة — كل ما زاد، كل ما صار أكثر استقلالية"
          >
            <ul className="divide-y divide-line-soft">
              {session.ratings!.map((rating) => (
                <li key={rating.id} className="flex items-start gap-3 px-4 py-3">
                  <LevelChip level={rating.level} />
                  <div className="min-w-0 flex-1">
                    <Link
                      href={`/goals/view?id=${rating.goal_id}`}
                      className="text-sm font-semibold text-ink hover:text-brand"
                    >
                      {rating.goal?.title}
                    </Link>
                    <p className="mt-0.5 text-xs text-muted">
                      {LEVEL_LABELS[rating.level]}
                      {rating.trials
                        ? ` · نجح ${rating.successes} من ${rating.trials} محاولة`
                        : ""}
                    </p>
                    {rating.note && (
                      <p className="mt-1 text-xs text-ink">{rating.note}</p>
                    )}
                  </div>
                </li>
              ))}
            </ul>
            <div className="border-t border-line px-4 py-3">
              <LevelKey />
            </div>
          </Card>
        )}

        <Attachments session={session} onChanged={onChanged} mayWrite={false} />

        {/* ---- the specialist's own notes ---- */}
        {isStaff && session.private_notes && (
          <Card
            title="ملاحظات الأخصائية الخاصة"
            hint="ما وصلت ولي الأمر ولا رح توصله"
          >
            <p className="report-prose px-5 py-4 text-ink">{session.private_notes}</p>
          </Card>
        )}
      </div>

      {/* ---- rail ---- */}
      <aside className="no-print space-y-4 lg:sticky lg:top-20 lg:self-start">
        {!isStaff && (
          <Card>
            <div className="space-y-3 p-4">
              <Button className="w-full" onClick={() => setAsking(true)}>
                اسأل عن هذه الجلسة
              </Button>
              <p className="text-xs text-muted">
                سؤالك بيوصل الأخصائية مربوط بهذا اليوم بالذات، فما بتحتاج تدوّر عليه.
              </p>
            </div>
          </Card>
        )}

        {mayWrite && (
          <Card title="تصحيح">
            <div className="space-y-3 p-4">
              <Button variant="ghost" className="w-full" onClick={() => setCorrecting(true)}>
                أضف تصحيحاً
              </Button>
              <p className="text-xs text-muted">
                التقرير وصل الأهل، فما بينعدّل. التصحيح بينضاف تحته بتاريخه، والنصّ الأصلي
                بيضلّ ظاهر.
              </p>
            </div>
          </Card>
        )}

        {isStaff && (
          <Card title="مين قرأ التقرير">
            {(session.read_by?.length ?? 0) === 0 ? (
              <p className="px-4 py-4 text-xs text-muted">
                ما حدا من الأهل فتحه لهلق.
              </p>
            ) : (
              <ul className="divide-y divide-line-soft">
                {session.read_by!.map((read, i) => (
                  <li key={i} className="px-4 py-2.5">
                    <p className="text-sm font-semibold text-ink">{read.name}</p>
                    <p className="text-xs text-muted">{relative(read.read_at)}</p>
                  </li>
                ))}
              </ul>
            )}
          </Card>
        )}
      </aside>

      <AskModal
        open={asking}
        onClose={() => setAsking(false)}
        studentId={session.student_id}
        sessionId={session.id}
      />

      <CorrectionModal
        open={correcting}
        onClose={() => setCorrecting(false)}
        sessionId={session.id}
        onDone={onChanged}
      />
    </div>
  );
}

/* -------------------------------------------------------------------------
 * Attachments
 * ---------------------------------------------------------------------- */

function Attachments({
  session,
  onChanged,
  mayWrite,
}: {
  session: TherapySession;
  onChanged: () => Promise<void>;
  mayWrite: boolean;
}) {
  const fileRef = useRef<HTMLInputElement>(null);
  const [caption, setCaption] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const items = session.attachments ?? [];

  if (items.length === 0 && !mayWrite) return null;

  async function send(file: File) {
    setBusy(true);
    setError(null);

    const form = new FormData();
    form.append("file", file);
    if (caption) form.append("caption", caption);

    try {
      await upload(`/sessions/${session.id}/attachments`, form);
      setCaption("");
      if (fileRef.current) fileRef.current.value = "";
      await onChanged();
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Card
      title="صور وفيديو من الجلسة"
      hint={
        mayWrite
          ? "١٢ ثانية لطفل بيمسك المقص بتساوي أكثر من فقرة كاملة"
          : undefined
      }
    >
      {items.length > 0 && (
        <div className="grid gap-3 p-4 sm:grid-cols-2">
          {items.map((item) => (
            <AttachmentTile
              key={item.id}
              id={item.id}
              kind={item.kind}
              caption={item.caption}
            />
          ))}
        </div>
      )}

      {mayWrite && (
        <div className="space-y-3 border-t border-line p-4">
          {error && <ErrorNote message={error} />}
          <Field label="تعليق على المرفق">
            <Input
              value={caption}
              onChange={(e) => setCaption(e.target.value)}
              placeholder="أول مرة يمسك المقص لحاله"
            />
          </Field>
          <input
            ref={fileRef}
            type="file"
            accept="image/jpeg,image/png,image/webp,video/mp4,video/quicktime"
            disabled={busy}
            onChange={(e) => {
              const file = e.target.files?.[0];
              if (file) send(file);
            }}
            className="block w-full text-xs text-muted file:mr-0 file:ml-3 file:rounded-lg file:border-0 file:bg-brand-soft file:px-3 file:py-2 file:text-xs file:font-semibold file:text-brand"
          />
          {busy && <p className="text-xs text-muted">عم نرفع…</p>}
        </div>
      )}
    </Card>
  );
}

/* -------------------------------------------------------------------------
 * Dialogs
 * ---------------------------------------------------------------------- */

function AskModal({
  open,
  onClose,
  studentId,
  sessionId,
}: {
  open: boolean;
  onClose: () => void;
  studentId: number;
  sessionId: number;
}) {
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function submit() {
    setBusy(true);
    setError(null);

    try {
      await api(`/students/${studentId}/messages`, {
        method: "POST",
        body: { body, therapy_session_id: sessionId },
      });
      setDone(true);
      setBody("");
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="اسأل عن هذه الجلسة">
      {done ? (
        <div className="space-y-3">
          <Note>وصل سؤالك. رح تلاقي الردّ في «الرسائل».</Note>
          <Button variant="ghost" className="w-full" onClick={onClose}>
            تمام
          </Button>
        </div>
      ) : (
        <div className="space-y-3">
          {error && <ErrorNote message={error} />}
          <Field label="سؤالك">
            <Textarea
              rows={4}
              value={body}
              onChange={(e) => setBody(e.target.value)}
              placeholder="بالبيت بلاحظ إنه… في شي بتنصحوني فيه؟"
            />
          </Field>
          <Button className="w-full" disabled={busy || !body.trim()} onClick={submit}>
            {busy ? "عم نبعت…" : "أرسل"}
          </Button>
        </div>
      )}
    </Modal>
  );
}

function CorrectionModal({
  open,
  onClose,
  sessionId,
  onDone,
}: {
  open: boolean;
  onClose: () => void;
  sessionId: number;
  onDone: () => Promise<void>;
}) {
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function submit() {
    setBusy(true);
    setError(null);

    try {
      await api(`/sessions/${sessionId}/addendum`, { method: "POST", body: { body } });
      setBody("");
      await onDone();
      onClose();
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title="أضف تصحيحاً">
      <div className="space-y-3">
        {error && <ErrorNote message={error} />}
        <p className="text-xs text-muted">
          بينضاف تحت التقرير بتاريخه. النصّ الأصلي ما بينشال — عشان اللي قرأته الأم امبارح
          يضلّ نفسه.
        </p>
        <Field label="التصحيح">
          <Textarea
            rows={4}
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="تصحيح: الجلسة كانت ٤٥ دقيقة وليس ٣٠."
          />
        </Field>
        <Button className="w-full" disabled={busy || !body.trim()} onClick={submit}>
          {busy ? "عم نضيف…" : "أضف"}
        </Button>
      </div>
    </Modal>
  );
}
