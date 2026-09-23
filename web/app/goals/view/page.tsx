"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ApiError, api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { PageHead } from "@/components/shell";
import { CurveTable, Figure, GoalCurve } from "@/components/charts";
import { Badge, Button, Card, Confirm, Empty, LevelChip, Loading, Stat, WithId } from "@/components/ui";
import {
  GOAL_LABELS,
  GOAL_TONES,
  LEVEL_LABELS,
  TREND_LABELS,
  TREND_TONES,
  date,
  number,
} from "@/lib/format";
import type { GoalCurve as Curve } from "@/lib/types";

export default function GoalPage() {
  return <WithId>{(id) => <GoalScreen id={id} />}</WithId>;
}

/**
 * One goal, from the day it was opened until the last session.
 *
 * This is the screen that makes the whole scoring discipline worth doing. A
 * parent asked to believe "تحسّن ملحوظ" has to take it on trust; the same
 * parent looking at a line that went from 1 to 3 over six weeks is looking at
 * something the academy can be held to.
 */
function GoalScreen({ id }: { id: number }) {
  const { isStaff } = useAuth();
  const router = useRouter();
  const [curve, setCurve] = useState<Curve | null>(null);
  const [removing, setRemoving] = useState(false);
  const [loading, setLoading] = useState(true);
  const [notFound, setNotFound] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await api<{ data: Curve }>(`/goals/${id}`);
      setCurve(res.data);
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
  if (notFound || !curve) return <Empty boxed title="الهدف غير متاح" hint="يمكن يكون مش من ملفاتك، أو انحذف." />;

  const { goal, summary, points } = curve;

  return (
    <>
      <PageHead
        title={goal.title}
        subtitle={goal.criteria ? `معيار الإتقان: ${goal.criteria}` : undefined}
        action={
          <div className="flex flex-wrap items-center gap-2">
            {summary.trend && (
              <Badge className={TREND_TONES[summary.trend]}>
                {TREND_LABELS[summary.trend]}
              </Badge>
            )}
            <Badge className={GOAL_TONES[goal.status]}>{GOAL_LABELS[goal.status]}</Badge>
            {isStaff && (
              <>
                <Button
                  variant="ghost"
                  onClick={() => router.push(`/students/view?id=${goal.student_id}`)}
                >
                  ملف الطفل
                </Button>
                <Button variant="danger" onClick={() => setRemoving(true)}>
                  حذف
                </Button>
              </>
            )}
          </div>
        }
      />

      <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <Stat
          label="بدأ من"
          value={`${goal.baseline} — ${LEVEL_LABELS[goal.baseline]}`}
          hint={date(goal.started_at)}
        />
        <Stat
          label="وين وصل"
          value={
            summary.latest === null ? "—" : `${summary.latest} — ${LEVEL_LABELS[summary.latest]}`
          }
          tone={
            summary.delta === null ? "plain" : summary.delta > 0 ? "good" : summary.delta < 0 ? "warn" : "plain"
          }
          hint={
            summary.delta === null
              ? "لسه ما انقاس"
              : summary.delta > 0
                ? `تقدّم ${summary.delta} درجة عن البداية`
                : summary.delta < 0
                  ? `تراجع ${Math.abs(summary.delta)} درجة عن البداية`
                  : "نفس نقطة البداية"
          }
        />
        <Stat label="عدد القياسات" value={number(summary.sessions)} />
        <Stat
          label="المطلوب"
          value={`${goal.target} — ${LEVEL_LABELS[goal.target]}`}
          tone="brand"
        />
      </div>

      <Figure
        title="المنحنى"
        hint="المحور من ٠ إلى ٤ دائماً — عشان المسافة اللي بعدها ما توصلنا تضلّ ظاهرة"
        table={<CurveTable points={points} />}
      >
        {points.length === 0 ? (
          <Empty
            title="لسه ما انقاس هذا الهدف"
            hint="أول قياس بيصير أول ما تنكتب جلسة اشتغلتوا فيها عليه."
          />
        ) : (
          <GoalCurve
            points={points}
            baseline={goal.baseline}
            target={goal.target}
            startedAt={curve.baseline_point.date}
          />
        )}
      </Figure>

      {points.length > 0 && (
        <Card title="كل قياس" className="mt-4">
          <ul className="divide-y divide-line-soft">
            {[...points].reverse().map((point) => (
              <li key={point.session} className="flex items-start gap-3 px-4 py-3">
                <LevelChip level={point.level} />
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-semibold text-ink">
                    {LEVEL_LABELS[point.level]}
                    {point.trials ? (
                      <span className="tabular mr-2 font-normal text-muted">
                        · نجح {point.successes} من {point.trials}
                        {point.rate !== null && ` (${point.rate}%)`}
                      </span>
                    ) : null}
                  </p>
                  <p className="mt-0.5 text-xs text-muted">
                    {date(point.date)} · جلسة <span className="tabular">{point.session}</span>
                  </p>
                  {point.note && <p className="mt-1 text-xs text-ink">{point.note}</p>}
                </div>
              </li>
            ))}
          </ul>
        </Card>
      )}

      <Confirm
        open={removing}
        onClose={() => setRemoving(false)}
        onConfirm={async () => {
          await api(`/goals/${goal.id}`, { method: "DELETE" });
          router.replace(`/students/view?id=${goal.student_id}`);
        }}
        title="حذف الهدف"
        body={
          <>
            حذف <b>{goal.title}</b>. لو عليه قياسات، النظام رح يرفض ويطلب توقيفه أو تعليمه
            محقّقاً — عشان منحنى قرأه الأهل ما ينمسح من تحتهم.
          </>
        }
      />

      {goal.achieved_at && (
        <div className="mt-4 rounded-xl border border-good/25 bg-good-soft px-4 py-3 text-sm font-semibold text-good">
          تحقّق هذا الهدف في {date(goal.achieved_at)}. 🎉
        </div>
      )}
    </>
  );
}
