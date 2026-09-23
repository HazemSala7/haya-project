"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { PageHead } from "@/components/shell";
import { Badge, Card, Empty, Loading, Table } from "@/components/ui";
import { Donut, Figure, Gauge, HBars, Kpi, LineChart, RowsTable, SeriesTable, Spark, StackedBars } from "@/components/viz";
import {
  MOOD_FACES,
  MOOD_LABELS,
  SESSION_LABELS,
  SESSION_TONES,
  SPECIALTY_LABELS,
  dayDate,
  number,
  percent,
  relative,
  time,
} from "@/lib/format";
import type {
  AdminDashboard,
  Analytics,
  Dashboard,
  GuardianDashboard,
  SpecialistDashboard,
  TherapySession,
} from "@/lib/types";

const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

const SPECIALTY_COLOR: Record<string, string> = {
  speech: "var(--viz-speech)",
  occupational: "var(--viz-occupational)",
  behavioral: "var(--viz-behavioral)",
  special_ed: "var(--viz-special-ed)",
};

const MONTHS = [
  "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
  "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
];

function weekLabel(iso: string): string {
  const d = new Date(iso);
  return `${d.getDate()} ${MONTHS[d.getMonth()]}`;
}

function today(): string {
  const days = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"];
  const d = new Date();
  return `${days[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}`;
}

/**
 * The first screen — three of them, because three different jobs open it.
 *
 * All three pull `/dashboard` for what is happening now and `/analytics` for
 * the shape of the last two months, in parallel. Two requests rather than one
 * fat endpoint: the dashboard is the part that must be right this second, and
 * it renders the moment it lands even if the charts are still coming.
 */
export default function HomePage() {
  const { user } = useAuth();
  const [data, setData] = useState<Dashboard | null>(null);
  const [stats, setStats] = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    try {
      const dash = await api<{ data: Dashboard }>("/dashboard");
      setData(dash.data);

      // Guardians have no analytics endpoint, and asking would be a certain
      // 403 in their console on every page load.
      if (dash.data.kind !== "guardian") {
        try {
          const a = await api<{ data: Analytics }>("/analytics", { query: { weeks: 8 } });
          setStats(a.data);
        } catch {
          /* the charts are a bonus; the queues below are the page */
        }
      }
    } catch (e) {
      setError((e as { message?: string }).message ?? "تعذّر تحميل الصفحة.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  if (loading) return <Loading boxed rows={5} />;
  if (!data) return <Empty boxed title={error ?? "تعذّر تحميل الصفحة"} hint="جرّب تحديث الصفحة." />;

  if (data.kind === "guardian") return <GuardianHome data={data} name={user?.name ?? ""} />;
  if (data.kind === "specialist")
    return <SpecialistHome data={data} stats={stats} name={user?.name ?? ""} />;
  return <AdminHome data={data} stats={stats} />;
}

/* -------------------------------------------------------------------------
 * A greeting that carries the date
 * ---------------------------------------------------------------------- */

function Hero({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <div className="brand-wash rise sheen relative mb-5 overflow-hidden rounded-2xl border border-sky/50 bg-panel shadow-card">
      {/*
        Two rings drawn off the far edge, in the logo's own blue and sage.
        They are the canopy of the mark abstracted — enough to make the block
        feel designed rather than filled, and far enough out of the way that
        nothing is ever read over them.
      */}
      <span
        aria-hidden
        className="pointer-events-none absolute -top-24 -start-16 size-56 rounded-full border-[14px] border-sky/25"
      />
      <span
        aria-hidden
        className="pointer-events-none absolute -bottom-28 start-24 size-52 rounded-full border-[12px] border-sage/25"
      />

      <div className="relative flex items-center justify-between gap-4 px-5 py-5 sm:px-6">
        <div className="min-w-0">
          <p className="inline-flex items-center gap-1.5 rounded-full bg-panel/70 px-2.5 py-1 text-[11px] font-bold tracking-wide text-brand ring-1 ring-brand/15">
            <span aria-hidden className="size-1.5 rounded-full bg-brand" />
            {today()}
          </p>
          <h1 className="mt-2 text-2xl font-extrabold tracking-tight text-ink sm:text-[1.7rem]">
            {title}
          </h1>
          <p className="mt-1 text-sm leading-relaxed text-ink-soft">{subtitle}</p>
        </div>

        <span className="hidden shrink-0 rounded-2xl bg-panel/60 p-2 shadow-soft ring-1 ring-panel/80 sm:block">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={`${BASE_PATH}/mark.png`} alt="" className="size-16 object-contain" />
        </span>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------
 * The office
 * ---------------------------------------------------------------------- */

/**
 * Three failures, the shape of the term, then the two lists that fix them.
 *
 * The counts that lead are not "how many children" and "how many staff" —
 * those never change and nobody acts on them. They are the three things that
 * are quietly going wrong right now.
 */
function AdminHome({ data, stats }: { data: AdminDashboard; stats: Analytics | null }) {
  const { stats: s } = data;

  const weekly = stats?.weekly ?? [];
  const labels = weekly.map((w) => weekLabel(w.week));
  const rates = weekly.map((w) => w.rate);
  const trend = stats?.level_trend ?? [];
  const trendValues = trend.map((t) => t.avg);

  const measured = trend.filter((t) => t.avg !== null);
  const firstAvg = measured[0]?.avg ?? null;
  const lastAvg = measured[measured.length - 1]?.avg ?? null;
  const drift = firstAvg !== null && lastAvg !== null ? +(lastAvg - firstAvg).toFixed(2) : null;

  const problems = s.unwritten + s.unanswered + s.unassigned;

  return (
    <>
      <Hero
        title="اليوم في الأكاديمية"
        subtitle={
          problems === 0
            ? `${s.students} طفل مستمرّ · ${s.sessions_today} جلسة اليوم · ما في شي عالق`
            : `${s.students} طفل مستمرّ · ${s.sessions_today} جلسة اليوم · ${problems} بند بدّه تدخّل`
        }
      />

      {/* ---- what is going wrong right now ---- */}
      <div className="rise-grid mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Kpi
          label="تقارير ما وصلت الأهل"
          value={number(s.unwritten)}
          hint="جلسات تمّت وما انكتب تقريرها"
          tone={s.unwritten > 0 ? "warn" : "good"}
          href="/sessions?unwritten=1"
        />
        <Kpi
          label="أسئلة أهل بلا ردّ"
          value={number(s.unanswered)}
          hint={s.unanswered > 0 ? "كل يوم تأخير بيكلّف ثقة" : "ما في سؤال معلّق"}
          tone={s.unanswered > 0 ? "bad" : "good"}
          href="/messages"
        />
        <Kpi
          label="برامج بلا أخصائية"
          value={number(s.unassigned)}
          hint={s.unassigned > 0 ? "أطفال بلا حدا مسؤول عنهم" : "كل برنامج مسند"}
          tone={s.unassigned > 0 ? "bad" : "good"}
          href="/students"
        />
        <Kpi
          label="نسبة الحضور"
          value={percent(s.attendance_rate)}
          hint={`آخر أسبوع · ${s.absent_week} غياب بدون عذر`}
          tone={s.attendance_rate !== null && s.attendance_rate < 80 ? "warn" : "brand"}
          spark={rates}
        />
      </div>

      {/* ---- the shape of the term ---- */}
      {stats && (
        <div className="rise-grid mb-4 grid gap-4 lg:grid-cols-3">
          <Figure
            title="الجلسات أسبوعاً بأسبوع"
            hint="الأقدم على اليمين"
            className="lg:col-span-2"
            legend={[
              { name: "تمّت", color: "var(--viz-held)" },
              { name: "ما إجا", color: "var(--viz-absent)" },
              { name: "غياب بعذر", color: "var(--viz-excused)" },
              { name: "ملغية", color: "var(--color-line)" },
            ]}
            action={
              <Link href="/analytics" className="text-xs font-semibold text-brand">
                التحليلات ←
              </Link>
            }
            table={
              <SeriesTable
                head="الأسبوع"
                labels={labels}
                series={[
                  { name: "تمّت", color: "", values: weekly.map((w) => w.held) },
                  { name: "ما إجا", color: "", values: weekly.map((w) => w.absent) },
                  { name: "غياب بعذر", color: "", values: weekly.map((w) => w.excused) },
                  { name: "ملغية", color: "", values: weekly.map((w) => w.cancelled) },
                ]}
              />
            }
          >
            <StackedBars
              labels={labels}
              height={190}
              series={[
                { name: "تمّت", color: "var(--viz-held)", values: weekly.map((w) => w.held) },
                { name: "ما إجا", color: "var(--viz-absent)", values: weekly.map((w) => w.absent) },
                { name: "غياب بعذر", color: "var(--viz-excused)", values: weekly.map((w) => w.excused) },
                { name: "ملغية", color: "var(--color-line)", values: weekly.map((w) => w.cancelled) },
              ]}
            />
          </Figure>

          <Card title="هل بيقرأوا التقارير؟" hint="من كل تقرير أرسلناه">
            <div className="flex flex-col items-center gap-4 p-4">
              <Gauge
                value={stats.engagement.rate}
                label="فتحها الأهل"
                caption={`من ${number(stats.engagement.total)}`}
                color="var(--viz-held)"
              />
              <div className="grid w-full grid-cols-2 gap-2 text-center">
                <div className="rounded-xl bg-good-soft px-2 py-2">
                  <div className="tabular text-lg font-bold text-good">
                    {number(stats.engagement.opened)}
                  </div>
                  <div className="text-[11px] text-muted">انفتحت</div>
                </div>
                <div className="rounded-xl bg-bad-soft px-2 py-2">
                  <div className="tabular text-lg font-bold text-bad">
                    {number(stats.engagement.unopened)}
                  </div>
                  <div className="text-[11px] text-muted">ما انفتحت</div>
                </div>
              </div>
            </div>
          </Card>
        </div>
      )}

      {stats && (
        <div className="mb-4 grid items-start gap-4 lg:grid-cols-3">
          <Figure
            title="متوسّط الاستقلالية"
            hint="المحور من ٠ إلى ٤ دائماً — التحسّن هنا بيزحف"
            className="lg:col-span-2"
            table={
              <SeriesTable
                head="الأسبوع"
                labels={trend.map((t) => weekLabel(t.week))}
                series={[{ name: "المتوسّط", color: "", values: trendValues }]}
              />
            }
          >
            <div className="px-4 pt-3">
              <div className="flex items-baseline gap-3">
                <span className="tabular text-3xl font-extrabold text-ink">
                  {lastAvg === null ? "—" : lastAvg.toFixed(2)}
                </span>
                {drift !== null && drift !== 0 && (
                  <span
                    className={`tabular rounded-md px-2 py-0.5 text-xs font-bold ${
                      drift > 0 ? "bg-good/10 text-good" : "bg-bad/10 text-bad"
                    }`}
                  >
                    {drift > 0 ? "▲" : "▼"} {Math.abs(drift).toFixed(2)} عن بداية الفترة
                  </span>
                )}
              </div>
            </div>
            <LineChart
              labels={trend.map((t) => weekLabel(t.week))}
              yMax={4}
              height={170}
              formatValue={(v) => v.toFixed(1)}
              series={[
                { name: "متوسّط الاستقلالية", color: "var(--viz-brand)", values: trendValues },
              ]}
            />
          </Figure>

          <Figure
            title="الجلسات حسب البرنامج"
            hint="آخر ٨ أسابيع"
            table={
              <RowsTable
                head={["البرنامج", "جلسات"]}
                rows={stats.by_specialty.map((x) => ({
                  label: x.label,
                  value: x.sessions,
                  hint: `· ${x.students} طفل`,
                }))}
              />
            }
          >
            <HBars
              rows={stats.by_specialty.map((x) => ({
                label: x.label,
                value: x.sessions,
                color: SPECIALTY_COLOR[x.specialty],
                hint: `· ${x.students} طفل`,
              }))}
            />
          </Figure>
        </div>
      )}

      {/* ---- the two lists that fix things ---- */}
      <div className="grid items-start gap-4 lg:grid-cols-2">
        <UnwrittenQueue queue={data.queue} showSpecialist />

        {/*
          The quietest failure in the building: the reports are written, they
          are published, every number above looks healthy, and nobody is
          reading them. It is only visible because something goes looking.
        */}
        <Card
          title="عائلات ما فتحت التطبيق"
          hint="أكثر من ٣ أسابيع — التقارير بتنكتب وما حدا بيقرأها"
        >
          {data.silent_families.length === 0 ? (
            <Empty title="كل العائلات بتتابع" hint="ما في حدا انقطع." />
          ) : (
            <Table head={["ولي الأمر", "الأطفال", "آخر دخول"]}>
              {data.silent_families.map((family) => (
                <tr key={family.id}>
                  <td className="px-4 py-2.5">
                    <div className="font-semibold text-ink">{family.name}</div>
                    {family.phone && (
                      <div dir="ltr" className="tabular text-right text-xs text-muted">
                        {family.phone}
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-2.5 text-xs text-muted">
                    {family.children.map((c) => c.name).join("، ")}
                  </td>
                  <td className="px-4 py-2.5 text-xs font-semibold text-bad">
                    {family.last_seen_at ? relative(family.last_seen_at) : "ولا مرة"}
                  </td>
                </tr>
              ))}
            </Table>
          )}
        </Card>
      </div>

      {/* ---- who is carrying what ---- */}
      {stats && stats.specialists.length > 0 && (
        <Card title="الفريق" hint="آخر ٨ أسابيع" className="mt-4">
          <div className="divide-y divide-line-soft">
            {stats.specialists.map((p) => {
              const busiest = Math.max(1, ...stats.specialists.map((x) => x.sessions));

              return (
                <div key={p.id} className="flex flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
                  <div className="min-w-44">
                    <p className="text-sm font-bold text-ink">{p.name}</p>
                    <p className="text-xs text-muted">{p.title ?? "أخصائية"}</p>
                  </div>

                  <div className="min-w-52 flex-1">
                    <div className="mb-1 flex justify-between text-[11px] text-muted">
                      <span>
                        <span className="tabular font-bold text-ink">{number(p.held)}</span> جلسة تمّت
                      </span>
                      <span>
                        <span className="tabular font-bold text-ink">{number(p.students)}</span> طفل
                      </span>
                    </div>
                    <div className="h-2.5 w-full overflow-hidden rounded-full bg-line/50">
                      <div
                        className="h-full rounded-full bg-brand transition-[width] duration-700"
                        style={{ width: `${(p.held / busiest) * 100}%` }}
                      />
                    </div>
                  </div>

                  <div
                    className={`rounded-lg px-2.5 py-1 text-xs font-bold ${
                      p.unwritten > 0 ? "bg-warn-soft text-warn" : "bg-good-soft text-good"
                    }`}
                  >
                    {p.unwritten > 0 ? `${p.unwritten} بدون تقرير` : "كل شي مكتوب"}
                  </div>
                </div>
              );
            })}
          </div>
        </Card>
      )}
    </>
  );
}

/* -------------------------------------------------------------------------
 * The specialist
 * ---------------------------------------------------------------------- */

function SpecialistHome({
  data,
  stats,
  name,
}: {
  data: SpecialistDashboard;
  stats: Analytics | null;
  name: string;
}) {
  const { stats: s } = data;

  const trend = stats?.level_trend ?? [];
  const measured = trend.filter((t) => t.avg !== null);
  const firstAvg = measured[0]?.avg ?? null;
  const lastAvg = measured[measured.length - 1]?.avg ?? null;
  const drift = firstAvg !== null && lastAvg !== null ? +(lastAvg - firstAvg).toFixed(2) : null;

  return (
    <>
      <Hero
        title={`صباح الخير ${name.split(" ")[0]}`}
        subtitle={
          s.today_total === 0
            ? "ما في جلسات مجدولة اليوم."
            : `عندك ${s.today_total} جلسة اليوم — ${s.today_held} منها خلصت.`
        }
      />

      <div className="rise-grid mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Kpi label="جلسات اليوم" value={number(s.today_total)} hint={`${s.today_held} خلصت`} tone="brand" />
        <Kpi label="أطفالي" value={number(s.students)} />
        <Kpi
          label="تقارير ما انكتبت"
          value={number(s.unwritten)}
          tone={s.unwritten > 0 ? "warn" : "good"}
          hint={s.oldest_unwritten ? `أقدم وحدة ${relative(s.oldest_unwritten)}` : "كل شي مكتوب"}
          href="/sessions?unwritten=1"
        />
        <Kpi
          label="متوسّط الاستقلالية"
          value={lastAvg === null ? "—" : lastAvg.toFixed(2)}
          delta={drift !== null && drift !== 0 ? { value: drift } : null}
          hint="لأطفالك"
          tone={drift !== null && drift > 0 ? "good" : "plain"}
          spark={trend.map((t) => t.avg)}
        />
      </div>

      <div className="mb-4 grid items-start gap-4 lg:grid-cols-2">
        <Card title="جلسات اليوم">
          {data.today.length === 0 ? (
            <Empty title="ما في جلسات اليوم" hint="خُد راحتك." />
          ) : (
            <ul className="divide-y divide-line-soft">
              {data.today.map((session) => (
                <li key={session.id}>
                  <Link
                    href={`/sessions/view?id=${session.id}`}
                    className="block px-4 py-3 transition hover:bg-brand-soft/45"
                  >
                    <div className="flex items-center justify-between gap-3">
                      <div>
                        <span className="tabular text-sm font-bold text-ink">
                          {time(session.scheduled_at)}
                        </span>
                        <span className="mr-2 text-sm font-semibold text-ink">
                          {session.student?.name}
                        </span>
                      </div>
                      <Badge className={SESSION_TONES[session.status]}>
                        {SESSION_LABELS[session.status]}
                      </Badge>
                    </div>
                    {session.student?.medical_alert && (
                      <p className="mt-1.5 text-xs font-semibold text-alert">
                        ⚠️ {session.student.medical_alert}
                      </p>
                    )}
                  </Link>
                </li>
              ))}
            </ul>
          )}
        </Card>

        {stats ? (
          <Figure
            title="متوسّط الاستقلالية لأطفالك"
            hint="المحور من ٠ إلى ٤ دائماً"
            table={
              <SeriesTable
                head="الأسبوع"
                labels={trend.map((t) => weekLabel(t.week))}
                series={[{ name: "المتوسّط", color: "", values: trend.map((t) => t.avg) }]}
              />
            }
          >
            <LineChart
              labels={trend.map((t) => weekLabel(t.week))}
              yMax={4}
              height={200}
              formatValue={(v) => v.toFixed(1)}
              series={[
                { name: "متوسّط الاستقلالية", color: "var(--viz-brand)", values: trend.map((t) => t.avg) },
              ]}
            />
          </Figure>
        ) : (
          <UnwrittenQueue queue={data.queue} showSpecialist={false} />
        )}
      </div>

      <div className="grid items-start gap-4 lg:grid-cols-2">
        {stats && <UnwrittenQueue queue={data.queue} showSpecialist={false} />}

        {stats && (
          <Figure
            title="كيف بيوصلوا أطفالك"
            hint="الشي الوحيد هون اللي مش بإيدك"
            table={
              <RowsTable
                head={["المزاج", "جلسات"]}
                rows={stats.moods.map((m) => ({ label: MOOD_LABELS[m.mood], value: m.count }))}
              />
            }
          >
            <HBars
              rows={stats.moods.map((m) => ({
                label: `${MOOD_FACES[m.mood]}  ${MOOD_LABELS[m.mood]}`,
                value: m.count,
                color:
                  m.mood === "happy" || m.mood === "calm"
                    ? "var(--viz-held)"
                    : m.mood === "tired"
                      ? "var(--viz-excused)"
                      : "var(--viz-absent)",
              }))}
            />
          </Figure>
        )}
      </div>
    </>
  );
}

/* -------------------------------------------------------------------------
 * The family
 * ---------------------------------------------------------------------- */

/**
 * A parent's first screen is her children — one card each, and nothing else
 * above them.
 *
 * The number that leads is "how many reports you have not opened", because
 * that is the question she came with. Everything else is context for it.
 */
function GuardianHome({ data, name }: { data: GuardianDashboard; name: string }) {
  return (
    <>
      <Hero
        title={`أهلاً ${name.split("—")[0].trim()}`}
        subtitle={
          data.unread_messages > 0
            ? `عندك ${data.unread_messages} رسالة جديدة من الأكاديمية.`
            : "هاي آخر أخبار أطفالك بالأكاديمية."
        }
      />

      <div className={`grid gap-4 ${data.children.length > 1 ? "lg:grid-cols-2" : "max-w-3xl"}`}>
        {data.children.map((child) => {
          const a = child.summary.attendance;

          return (
            <Card key={child.id} className="overflow-hidden">
              <div className="border-b border-line bg-gradient-to-l from-brand-soft via-sky-soft/50 to-transparent px-4 py-4">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex min-w-0 items-center gap-3">
                    {/*
                      The child's initial, in the logo's own two colours. On a
                      screen a mother opens to read about one specific person,
                      a face-shaped mark is what makes the card hers before a
                      word of it is read.
                    */}
                    <span
                      aria-hidden
                      className="grid size-11 shrink-0 place-items-center rounded-2xl bg-gradient-to-br from-sky to-sage text-lg font-extrabold text-ink/75 shadow-soft ring-2 ring-panel"
                    >
                      {child.name.trim().charAt(0)}
                    </span>
                    <div className="min-w-0">
                      <Link
                        href={`/students/view?id=${child.id}`}
                        className="text-base font-extrabold text-ink transition hover:text-brand"
                      >
                        {child.name}
                      </Link>
                      <p className="mt-0.5 text-xs text-muted">
                        {child.age_label} · ملف <span className="tabular">{child.file_number}</span>
                      </p>
                    </div>
                  </div>
                  {child.unread_reports > 0 && (
                    <Badge className="bg-brand text-white shadow-glow">
                      {child.unread_reports} تقرير جديد
                    </Badge>
                  )}
                </div>

                <div className="mt-3 flex flex-wrap gap-1.5">
                  {child.programmes.map((p) => (
                    <Badge key={p.id} className="bg-panel text-ink-soft shadow-soft">
                      {SPECIALTY_LABELS[p.specialty]}
                      {p.specialist && ` · ${p.specialist}`}
                    </Badge>
                  ))}
                </div>
              </div>

              {/* attendance ring + the two goal counts */}
              <div className="flex flex-wrap items-center justify-around gap-4 border-b border-line px-4 py-4">
                <Gauge
                  value={a.rate}
                  size={116}
                  label="الحضور"
                  caption={`آخر ${a.window_days} يوم`}
                  color={a.rate !== null && a.rate < 70 ? "var(--viz-excused)" : "var(--viz-held)"}
                />

                <div className="grid grid-cols-2 gap-3 text-center">
                  <div className="rounded-2xl bg-brand-soft px-4 py-3 shadow-soft ring-1 ring-brand/10">
                    <div className="figure-xl text-2xl font-extrabold text-brand-deep">
                      {number(child.summary.goals.active)}
                    </div>
                    <div className="mt-1 text-[11px] text-muted">أهداف شغّالة</div>
                    <div className="mt-1 text-[11px] font-semibold text-good">
                      {child.summary.goals.moving} بتتحرّك
                    </div>
                  </div>
                  <div className="rounded-2xl bg-good-soft px-4 py-3 shadow-soft ring-1 ring-good/10">
                    <div className="figure-xl text-2xl font-extrabold text-good">
                      {number(child.summary.goals.achieved)}
                    </div>
                    <div className="mt-1 text-[11px] text-muted">أهداف تحقّقت</div>
                  </div>
                </div>
              </div>

              {/* the attendance split, written out */}
              <div className="border-b border-line px-4 py-3">
                <HBars
                  rows={[
                    { label: "حضر", value: a.held, color: "var(--viz-held)" },
                    { label: "ما إجا", value: a.absent, color: "var(--viz-absent)" },
                    { label: "غياب بعذر", value: a.excused, color: "var(--viz-excused)" },
                  ]}
                  max={Math.max(1, a.expected)}
                />
              </div>

              <div className="px-4 py-3 text-sm">
                {child.summary.last_session ? (
                  <Link
                    href={`/sessions/view?id=${child.summary.last_session.id}`}
                    className="flex items-center justify-between gap-3 rounded-lg px-2 py-2 transition hover:bg-brand-soft/45"
                  >
                    <span>
                      <span className="block text-xs text-muted">آخر جلسة</span>
                      <span className="font-semibold text-ink">
                        {dayDate(child.summary.last_session.scheduled_at)}
                        {" · "}
                        {SPECIALTY_LABELS[child.summary.last_session.specialty]}
                      </span>
                    </span>
                    <span className="text-xs font-bold text-brand">اقرأ التقرير ←</span>
                  </Link>
                ) : (
                  <p className="px-2 py-2 text-xs text-muted">ما في جلسات مسجّلة بعد.</p>
                )}

                {child.summary.next_session && (
                  <p className="mt-1 px-2 text-xs text-muted">
                    الجلسة الجاية: {dayDate(child.summary.next_session)} الساعة{" "}
                    <span className="tabular">{time(child.summary.next_session)}</span>
                  </p>
                )}
              </div>
            </Card>
          );
        })}
      </div>

      {data.children.length === 0 && (
        <Empty
          title="ما في أطفال مربوطين بحسابك"
          hint="راجع إدارة الأكاديمية ليربطوا ملف طفلك بحسابك."
        />
      )}
    </>
  );
}

/* -------------------------------------------------------------------------
 * Shared
 * ---------------------------------------------------------------------- */

/**
 * Oldest first, deliberately.
 *
 * The report nobody has written from eleven days ago is the one that has
 * stopped being writable — she no longer remembers the session — and it is the
 * one a family has been waiting on since.
 */
function UnwrittenQueue({
  queue,
  showSpecialist,
}: {
  queue: TherapySession[];
  showSpecialist: boolean;
}) {
  return (
    <Card
      title="تقارير مستنية الكتابة"
      hint="الأقدم أولاً — الجلسة اللي مرّ عليها أسبوع صعب تنكتب صح"
      action={
        <Link href="/sessions?unwritten=1" className="text-xs font-semibold text-brand">
          الكل ←
        </Link>
      }
    >
      {queue.length === 0 ? (
        <Empty title="ما في تقارير متأخرة" hint="كل جلسة تمّت وصل تقريرها." />
      ) : (
        <ul className="divide-y divide-line-soft">
          {/*
            Six, not all of them. This is a triage list: past about six rows it
            stops being something you work through this morning and starts
            being a wall you scroll past. "الكل" in the header is the archive.
          */}
          {queue.slice(0, 6).map((session) => {
            const late = new Date(session.scheduled_at) < new Date(Date.now() - 3 * 864e5);

            return (
              <li key={session.id}>
                <Link
                  href={`/sessions/view?id=${session.id}`}
                  className="flex items-center justify-between gap-3 px-4 py-2.5 transition hover:bg-brand-soft/45"
                >
                  <div>
                    <div className="text-sm font-semibold text-ink">{session.student?.name}</div>
                    <div className="text-xs text-muted">
                      {dayDate(session.scheduled_at)}
                      {showSpecialist && session.specialist && ` · ${session.specialist.name}`}
                    </div>
                  </div>
                  <span className={`text-xs font-bold ${late ? "text-bad" : "text-muted"}`}>
                    {relative(session.scheduled_at)}
                  </span>
                </Link>
              </li>
            );
          })}
        </ul>
      )}

      {queue.length > 6 && (
        <div className="border-t border-line px-4 py-2.5 text-center">
          <Link href="/sessions?unwritten=1" className="text-xs font-semibold text-brand">
            و{queue.length - 6} غيرها ←
          </Link>
        </div>
      )}
    </Card>
  );
}
