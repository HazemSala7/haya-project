"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { PageHead } from "@/components/shell";
import { Card, Empty, Loading, Select, Stat, Table } from "@/components/ui";
import {
  Donut,
  Figure,
  HBars,
  LineChart,
  RowsTable,
  SeriesTable,
  StackedBars,
} from "@/components/viz";
import {
  LEVEL_LABELS,
  MOOD_FACES,
  MOOD_LABELS,
  SPECIALTY_LABELS,
  levelColor,
  number,
  percent,
} from "@/lib/format";
import type { Analytics } from "@/lib/types";

const SPECIALTY_COLOR: Record<string, string> = {
  speech: "var(--viz-speech)",
  occupational: "var(--viz-occupational)",
  behavioral: "var(--viz-behavioral)",
  special_ed: "var(--viz-special-ed)",
};

/** "٣ أغسطس" — a week is named by the Monday it starts on. */
function weekLabel(iso: string): string {
  const months = [
    "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو",
    "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر",
  ];
  const d = new Date(iso);
  return `${d.getDate()} ${months[d.getMonth()]}`;
}

/**
 * The analytics screen.
 *
 * Nine figures, and each one is here because somebody has to act on it —
 * not because a dashboard looks busier with charts on it. The order is the
 * order the questions get asked in: is the work happening, is it landing, are
 * the children moving, and is anyone reading any of it.
 */
export default function AnalyticsPage() {
  const { user, can } = useAuth();
  const [weeks, setWeeks] = useState("12");
  const [data, setData] = useState<Analytics | null>(null);
  const [loading, setLoading] = useState(true);

  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const res = await api<{ data: Analytics }>("/analytics", { query: { weeks } });
      setData(res.data);
    } catch (e) {
      // Without this the rejection escapes the effect entirely — a guardian
      // who types the URL gets a blank screen and an unhandled rejection in
      // the console rather than being told the page is not hers.
      setError((e as { message?: string }).message ?? "تعذّر تحميل التحليلات.");
    } finally {
      setLoading(false);
    }
  }, [weeks]);

  useEffect(() => {
    load();
  }, [load]);

  if (loading && !data) return <Loading />;

  if (!data) {
    return (
      <>
        <PageHead title="التحليلات" />
        <Empty
          title={error ?? "تعذّر تحميل التحليلات"}
          hint="هذه الشاشة للإدارة والأخصائيات."
        />
      </>
    );
  }

  const labels = data.weekly.map((w) => weekLabel(w.week));

  /* ---- headline numbers ---- */
  const held = data.weekly.reduce((s, w) => s + w.held, 0);
  const missed = data.weekly.reduce((s, w) => s + w.absent + w.excused, 0);
  const expected = held + missed;
  const rate = expected > 0 ? Math.round((held / expected) * 100) : null;

  const trend = data.level_trend.filter((w) => w.avg !== null);
  const first = trend[0]?.avg ?? null;
  const last = trend[trend.length - 1]?.avg ?? null;
  const drift = first !== null && last !== null ? +(last - first).toFixed(2) : null;

  const unwritten = data.specialists.reduce((s, p) => s + p.unwritten, 0);

  return (
    <>
      <PageHead
        title="التحليلات"
        subtitle={
          can("admin")
            ? "كل الأكاديمية — آخر فترة مختارة."
            : `حالاتك إنت، ${user?.name?.split(" ")[0] ?? ""}.`
        }
        action={
          <Select value={weeks} onChange={(e) => setWeeks(e.target.value)} className="w-40">
            <option value="4">آخر ٤ أسابيع</option>
            <option value="12">آخر ١٢ أسبوع</option>
            <option value="26">آخر نصف سنة</option>
            <option value="52">آخر سنة</option>
          </Select>
        }
      />

      {/* ---- the four numbers everything else explains ---- */}
      <div className="rise-grid mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="جلسات تمّت"
          value={number(held)}
          hint={`من أصل ${number(expected)} مجدولة`}
          tone="brand"
        />
        <Stat
          label="نسبة الحضور"
          value={percent(rate)}
          hint={`${number(missed)} غياب`}
          tone={rate !== null && rate < 80 ? "warn" : "good"}
        />
        <Stat
          label="متوسّط الاستقلالية"
          value={last === null ? "—" : last.toFixed(2)}
          hint={
            drift === null
              ? "لسه ما في قياسات كفاية"
              : drift > 0
                ? `تحسّن ${drift.toFixed(2)} درجة عن بداية الفترة`
                : drift < 0
                  ? `تراجع ${Math.abs(drift).toFixed(2)} درجة`
                  : "ثابت من بداية الفترة"
          }
          tone={drift !== null && drift > 0 ? "good" : drift !== null && drift < 0 ? "bad" : "plain"}
        />
        <Stat
          label="وسيط زمن الإرسال"
          value={
            data.turnaround.median_days === null
              ? "—"
              : data.turnaround.median_days === 0
                ? "نفس اليوم"
                : `${data.turnaround.median_days} يوم`
          }
          hint={`${number(data.turnaround.published)} تقرير مُرسل`}
          tone={
            data.turnaround.median_days !== null && data.turnaround.median_days <= 1
              ? "good"
              : "warn"
          }
        />
      </div>

      <div className="rise-grid grid gap-4 lg:grid-cols-2">
        {/* ---- 1. is the work happening? ---- */}
        <Figure
          title="الجلسات أسبوعاً بأسبوع"
          hint="الأقدم على اليمين — والملغية من طرف الأكاديمية مرسومة لحالها"
          legend={[
            { name: "تمّت", color: "var(--viz-held)" },
            { name: "ما إجا", color: "var(--viz-absent)" },
            { name: "غياب بعذر", color: "var(--viz-excused)" },
            { name: "ملغية", color: "var(--color-line)" },
          ]}
          table={
            <SeriesTable
              head="الأسبوع"
              labels={labels}
              series={[
                { name: "تمّت", color: "", values: data.weekly.map((w) => w.held) },
                { name: "ما إجا", color: "", values: data.weekly.map((w) => w.absent) },
                { name: "غياب بعذر", color: "", values: data.weekly.map((w) => w.excused) },
                { name: "ملغية", color: "", values: data.weekly.map((w) => w.cancelled) },
              ]}
            />
          }
        >
          <StackedBars
            labels={labels}
            series={[
              { name: "تمّت", color: "var(--viz-held)", values: data.weekly.map((w) => w.held) },
              { name: "ما إجا", color: "var(--viz-absent)", values: data.weekly.map((w) => w.absent) },
              { name: "غياب بعذر", color: "var(--viz-excused)", values: data.weekly.map((w) => w.excused) },
              { name: "ملغية", color: "var(--color-line)", values: data.weekly.map((w) => w.cancelled) },
            ]}
          />
        </Figure>

        {/* ---- 2. is attendance holding? ---- */}
        <Figure
          title="نسبة الحضور"
          hint="المحور ثابت من ٠ إلى ١٠٠ — نسبة تتأرجح بين ٨٥ و٩٥ مش أزمة"
          table={
            <SeriesTable
              head="الأسبوع"
              labels={labels}
              series={[{ name: "الحضور %", color: "", values: data.weekly.map((w) => w.rate) }]}
            />
          }
        >
          <LineChart
            labels={labels}
            yMax={100}
            suffix="٪"
            series={[
              {
                name: "نسبة الحضور",
                color: "var(--viz-brand)",
                values: data.weekly.map((w) => w.rate),
              },
            ]}
          />
        </Figure>

        {/* ---- 3. the number the whole system exists for ---- */}
        <Figure
          title="متوسّط الاستقلالية أسبوعاً بأسبوع"
          hint="المحور من ٠ إلى ٤ دائماً — التحسّن هنا بيزحف، وما بينفع نكبّره برسم"
          className="lg:col-span-2"
          table={
            <SeriesTable
              head="الأسبوع"
              labels={data.level_trend.map((w) => weekLabel(w.week))}
              series={[
                { name: "المتوسّط", color: "", values: data.level_trend.map((w) => w.avg) },
                { name: "عدد القياسات", color: "", values: data.level_trend.map((w) => w.count) },
              ]}
            />
          }
        >
          <LineChart
            labels={data.level_trend.map((w) => weekLabel(w.week))}
            yMax={4}
            height={220}
            formatValue={(v) => v.toFixed(1)}
            series={[
              {
                name: "متوسّط الاستقلالية",
                color: "var(--viz-brand)",
                values: data.level_trend.map((w) => w.avg),
              },
            ]}
          />
        </Figure>

        {/* ---- 4. where the scores actually sit ---- */}
        <Figure
          title="توزيع درجات الاستقلالية"
          hint="كل قياس في الفترة — الهرم بينقلب لفوق مع الوقت"
          table={
            <RowsTable
              head={["الدرجة", "عدد القياسات"]}
              rows={data.levels.map((l) => ({ label: `${l.level} — ${LEVEL_LABELS[l.level]}`, value: l.count }))}
            />
          }
        >
          <HBars
            rows={data.levels.map((l) => ({
              label: `${l.level} — ${LEVEL_LABELS[l.level]}`,
              value: l.count,
              color: levelColor(l.level),
            }))}
          />
        </Figure>

        {/* ---- 5. the four programmes ---- */}
        <Figure
          title="الجلسات حسب البرنامج"
          hint="وعدد الأطفال في كل برنامج"
          table={
            <RowsTable
              head={["البرنامج", "جلسات"]}
              rows={data.by_specialty.map((s) => ({
                label: s.label,
                value: s.sessions,
                hint: `· ${s.students} طفل`,
              }))}
            />
          }
        >
          <HBars
            rows={data.by_specialty.map((s) => ({
              label: s.label,
              value: s.sessions,
              color: SPECIALTY_COLOR[s.specialty],
              hint: `· ${s.students} طفل`,
            }))}
          />
        </Figure>

        {/* ---- 6. is anyone reading it? ---- */}
        <Figure
          title="هل بيقرأوا التقارير؟"
          hint="أهدأ فشل ممكن: كل شي بينكتب وبينبعت، وما حدا بيفتحه"
          table={
            <RowsTable
              head={["", "عدد"]}
              rows={[
                { label: "تقارير فتحها الأهل", value: data.engagement.opened },
                { label: "ما انفتحت", value: data.engagement.unopened },
              ]}
            />
          }
        >
          <Donut
            centerValue={percent(data.engagement.rate)}
            centerLabel="انفتحت"
            slices={[
              { name: "انفتحت", value: data.engagement.opened, color: "var(--viz-held)" },
              { name: "ما انفتحت", value: data.engagement.unopened, color: "var(--viz-absent)" },
            ]}
          />
        </Figure>

        {/* ---- 7. how fast does it reach them? ---- */}
        <Figure
          title="بعد قدّيش بيوصل التقرير"
          hint="تقرير بيوصل نفس المسا بيساوي كذا تقرير بيوصل بعد أسبوعين"
          table={
            <RowsTable
              head={["المدة", "تقارير"]}
              rows={[
                { label: "نفس اليوم", value: data.turnaround.buckets.same_day },
                { label: "اليوم التالي", value: data.turnaround.buckets.next_day },
                { label: "خلال ٣ أيام", value: data.turnaround.buckets.within_3 },
                { label: "خلال أسبوع", value: data.turnaround.buckets.within_7 },
                { label: "أكثر من أسبوع", value: data.turnaround.buckets.later },
              ]}
            />
          }
        >
          <HBars
            rows={[
              { label: "نفس اليوم", value: data.turnaround.buckets.same_day, color: "var(--viz-level-4)" },
              { label: "اليوم التالي", value: data.turnaround.buckets.next_day, color: "var(--viz-level-3)" },
              { label: "خلال ٣ أيام", value: data.turnaround.buckets.within_3, color: "var(--viz-level-2)" },
              { label: "خلال أسبوع", value: data.turnaround.buckets.within_7, color: "var(--viz-excused)" },
              { label: "أكثر من أسبوع", value: data.turnaround.buckets.later, color: "var(--viz-absent)" },
            ]}
          />
        </Figure>

        {/* ---- 8. how do they arrive? ---- */}
        <Figure
          title="كيف بيوصلوا الأطفال"
          hint="الشي الوحيد هون اللي مش بيد الأكاديمية — شهر بيتضاعف فيه التوتّر سؤال عن الطريق والجدول"
          table={
            <RowsTable
              head={["المزاج", "جلسات"]}
              rows={data.moods.map((m) => ({ label: MOOD_LABELS[m.mood], value: m.count }))}
            />
          }
        >
          <HBars
            rows={data.moods.map((m) => ({
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

        {/* ---- 9. who is carrying what ---- */}
        {can("admin") && data.specialists.length > 0 && (
          <Figure
            title="الأخصائيات"
            hint={
              unwritten > 0
                ? `${unwritten} تقرير مستنّي الكتابة عبر الفريق`
                : "كل التقارير مكتوبة"
            }
            className="lg:col-span-2"
            table={
              <Table head={["الأخصائية", "جلسات", "أطفال", "بدون تقرير"]}>
                {data.specialists.map((p) => (
                  <tr key={p.id}>
                    <td className="px-4 py-2 font-semibold text-ink">{p.name}</td>
                    <td className="tabular px-4 py-2 text-muted">{number(p.sessions)}</td>
                    <td className="tabular px-4 py-2 text-muted">{number(p.students)}</td>
                    <td className="tabular px-4 py-2 text-muted">{number(p.unwritten)}</td>
                  </tr>
                ))}
              </Table>
            }
          >
            <div className="divide-y divide-line-soft">
              {data.specialists.map((p) => (
                <div key={p.id} className="flex flex-wrap items-center gap-x-6 gap-y-2 px-4 py-3">
                  <div className="min-w-44">
                    <p className="text-sm font-bold text-ink">{p.name}</p>
                    <p className="text-xs text-muted">{p.title ?? "أخصائية"}</p>
                  </div>

                  <div className="min-w-52 flex-1">
                    <div className="mb-1 flex justify-between text-[11px] text-muted">
                      <span>
                        <span className="tabular font-bold text-ink">{number(p.held)}</span> جلسة
                        تمّت
                      </span>
                      <span>
                        <span className="tabular font-bold text-ink">{number(p.students)}</span> طفل
                      </span>
                    </div>
                    <div className="h-2.5 w-full overflow-hidden rounded-full bg-line/50">
                      <div
                        className="h-full rounded-full bg-brand"
                        style={{
                          width: `${(p.held / Math.max(1, ...data.specialists.map((s) => s.sessions))) * 100}%`,
                        }}
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
              ))}
            </div>
          </Figure>
        )}
      </div>

      <Card className="mt-4">
        <p className="px-4 py-3 text-xs text-muted">
          كل الأرقام محسوبة على الفترة المختارة فوق، والجلسات الملغية من طرف الأكاديمية
          مستثناة من مقام نسبة الحضور — تحميل عيلة نسبة غياب عن جلسة إحنا ألغيناها رقم بيستاهل
          خلاف. كل رسم إله «جدول» بيعطي نفس الأرقام بالضبط.
        </p>
      </Card>
    </>
  );
}
