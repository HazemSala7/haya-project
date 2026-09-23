"use client";

/**
 * The academy's figures.
 *
 * Hand-drawn in SVG rather than pulled from a charting library: the dashboard
 * ships as a static export to shared hosting, and a 300KB dependency to draw
 * two figures is a bad trade for a page a mother opens on a phone at ten at
 * night.
 *
 * Every colour comes from the validated ramps in globals.css — see the comment
 * above them for what was measured. The marks follow one set of rules
 * throughout: 2px lines, ≥8px markers, a 2px surface ring where marks overlap,
 * hairline gridlines, and text in ink tokens — never in the series colour,
 * which is unreadable at label sizes and is the mark's job anyway.
 *
 * Everything reads right to left, like the rest of the app: on a time axis the
 * oldest session sits at the right edge, where an Arabic reader starts.
 */

import { useEffect, useRef, useState } from "react";
import { Card, LevelKey, Table } from "@/components/ui";
import { LEVEL_LABELS, date, levelColor, number, percent } from "@/lib/format";
import type { CurvePoint, Level } from "@/lib/types";

/** The plot's own width in real pixels, so 1px lines stay 1px. */
function useWidth<T extends HTMLElement>() {
  const ref = useRef<T>(null);
  const [width, setWidth] = useState(0);

  useEffect(() => {
    const element = ref.current;
    if (!element) return;

    const observer = new ResizeObserver(([entry]) => setWidth(entry.contentRect.width));

    observer.observe(element);
    setWidth(element.clientWidth);

    return () => observer.disconnect();
  }, []);

  return [ref, width] as const;
}

/**
 * The frame every figure sits in: title, and the table view.
 *
 * The table is not a fallback — it is the same data in the form that never
 * fails, for the reader who cannot separate two teals, for the one who wants
 * an exact figure rather than a position on an axis, and for print.
 */
export function Figure({
  title,
  hint,
  table,
  children,
  action,
}: {
  title: string;
  hint?: string;
  table: React.ReactNode;
  children: React.ReactNode;
  action?: React.ReactNode;
}) {
  const [asTable, setAsTable] = useState(false);

  return (
    <Card
      title={title}
      hint={hint}
      action={
        <div className="flex items-center gap-2">
          {action}
          <button
            type="button"
            onClick={() => setAsTable((v) => !v)}
            aria-pressed={asTable}
            className="no-print rounded-lg border border-line bg-panel px-2.5 py-1 text-xs font-semibold text-muted shadow-soft transition hover:border-brand/35 hover:bg-brand-soft hover:text-brand"
          >
            {asTable ? "رسم" : "جدول"}
          </button>
        </div>
      }
    >
      {asTable ? table : children}
    </Card>
  );
}

/* -------------------------------------------------------------------------
 * The goal curve
 * ---------------------------------------------------------------------- */

/**
 * One goal, session by session, on the 0–4 prompt scale.
 *
 * The single screen that justifies the whole scoring discipline. Three things
 * are deliberate:
 *
 *  - The y-axis is the fixed five-step scale, never fitted to the data. A
 *    child who has moved from 1 to 2 must not be drawn filling the plot as
 *    though he had arrived — the distance still to go is the point.
 *  - The baseline is the first point, drawn hollow and dated from the day the
 *    goal was opened. Without it the line starts wherever the first session
 *    happened to land and the months since look like nothing.
 *  - The target sits as a dashed rule across the top. It is the only dashed
 *    line in the app, and it is dashed precisely because it is not data.
 */
export function GoalCurve({
  points,
  baseline,
  target,
  startedAt,
}: {
  points: CurvePoint[];
  baseline: Level;
  target: Level;
  startedAt: string | null;
}) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const [hover, setHover] = useState<number | null>(null);

  const height = 220;
  const pad = { top: 16, right: 44, bottom: 34, left: 16 };

  /*
   * The baseline is the first point, not a separate number beside the chart.
   * Typed explicitly because the two shapes differ — the baseline has no
   * session behind it — and letting TypeScript infer the union widens `point`
   * to `{}` and loses every field on it.
   */
  type Mark = {
    level: number;
    label: string;
    date: string | null;
    isBaseline: boolean;
    point?: CurvePoint;
  };

  const series: Mark[] = [
    { level: baseline, label: "خط البداية", date: startedAt, isBaseline: true },
    ...points.map((p) => ({
      level: p.level,
      label: p.session,
      date: p.date,
      isBaseline: false,
      point: p,
    })),
  ];

  const plotW = Math.max(0, width - pad.left - pad.right);
  const plotH = height - pad.top - pad.bottom;

  // Right-to-left: the oldest session is at the right edge.
  const x = (i: number) =>
    pad.left + plotW - (series.length === 1 ? plotW / 2 : (i / (series.length - 1)) * plotW);
  const y = (level: number) => pad.top + plotH - (level / 4) * plotH;

  const path = series.map((s, i) => `${i === 0 ? "M" : "L"} ${x(i)} ${y(s.level)}`).join(" ");

  const active = hover === null ? null : series[hover];

  return (
    <div className="p-4">
      <div ref={ref} className="relative">
        {width > 0 && (
          <svg
            width={width}
            height={height}
            role="img"
            aria-label={`منحنى الهدف: ${series.length} قياس على سلّم من ٠ إلى ٤`}
            onMouseLeave={() => setHover(null)}
          >
            {/* Gridlines — one per step of the scale, hairline, never dashed. */}
            {[0, 1, 2, 3, 4].map((level) => (
              <g key={level}>
                <line
                  x1={pad.left}
                  x2={pad.left + plotW}
                  y1={y(level)}
                  y2={y(level)}
                  stroke="var(--viz-grid)"
                  strokeWidth={1}
                />
                <text
                  x={pad.left + plotW + 8}
                  y={y(level) + 4}
                  className="fill-muted text-[10px]"
                  style={{ fontSize: 10 }}
                >
                  {level}
                </text>
              </g>
            ))}

            {/* The target. The only dashed line in the app — it is not data. */}
            {target < 4 && (
              <line
                x1={pad.left}
                x2={pad.left + plotW}
                y1={y(target)}
                y2={y(target)}
                stroke="var(--viz-brand)"
                strokeWidth={1.5}
                strokeDasharray="4 4"
                opacity={0.5}
              />
            )}

            <path d={path} fill="none" stroke="var(--viz-brand)" strokeWidth={2} />

            {series.map((s, i) => (
              <g key={i}>
                {/* A hit target far bigger than the mark. */}
                <circle
                  cx={x(i)}
                  cy={y(s.level)}
                  r={14}
                  fill="transparent"
                  onMouseEnter={() => setHover(i)}
                />
                <circle
                  cx={x(i)}
                  cy={y(s.level)}
                  r={hover === i ? 6.5 : 5}
                  fill={s.isBaseline ? "var(--color-panel)" : levelColor(s.level)}
                  stroke={s.isBaseline ? "var(--viz-brand)" : "var(--color-panel)"}
                  strokeWidth={2}
                />
              </g>
            ))}

            {/* Only the ends are labelled. A date on every point is a wall. */}
            <text
              x={x(0)}
              y={height - 12}
              textAnchor="middle"
              className="fill-muted"
              style={{ fontSize: 10 }}
            >
              البداية
            </text>
            {series.length > 1 && (
              <text
                x={x(series.length - 1)}
                y={height - 12}
                textAnchor="middle"
                className="fill-muted"
                style={{ fontSize: 10 }}
              >
                آخر جلسة
              </text>
            )}
          </svg>
        )}

        {active && (
          <div
            className="pop pointer-events-none absolute z-10 rounded-xl border border-line bg-panel/95 px-3 py-2 text-xs shadow-float backdrop-blur"
            style={{
              right: Math.min(Math.max(width - x(hover!) - 70, 0), Math.max(width - 150, 0)),
              top: 4,
            }}
          >
            <div className="font-bold text-ink">
              {active.isBaseline ? "خط البداية" : active.label}
            </div>
            <div className="text-muted">{date(active.date)}</div>
            <div className="mt-1 flex items-center gap-1.5">
              <span
                className="h-3 w-3 rounded-sm"
                style={{ background: levelColor(active.level) }}
                aria-hidden
              />
              <span className="font-semibold text-ink">
                {active.level} — {LEVEL_LABELS[active.level]}
              </span>
            </div>
            {active.point?.trials ? (
              <div className="tabular mt-1 text-muted">
                {active.point.successes} من {active.point.trials} محاولة
              </div>
            ) : null}
            {active.point?.note ? (
              <div className="mt-1 max-w-48 text-muted">{active.point.note}</div>
            ) : null}
          </div>
        )}
      </div>

      <div className="mt-3 border-t border-line pt-3">
        <LevelKey />
      </div>
    </div>
  );
}

/** The same curve as rows — exact figures, and what prints. */
export function CurveTable({ points }: { points: CurvePoint[] }) {
  return (
    <Table head={["الجلسة", "التاريخ", "المستوى", "المحاولات", "ملاحظة"]}>
      {points.map((p) => (
        <tr key={p.session}>
          <td className="tabular px-4 py-2 font-semibold text-ink">{p.session}</td>
          <td className="px-4 py-2 text-muted">{date(p.date)}</td>
          <td className="px-4 py-2">
            <span className="tabular font-bold text-ink">{p.level}</span>{" "}
            <span className="text-muted">— {LEVEL_LABELS[p.level]}</span>
          </td>
          <td className="tabular px-4 py-2 text-muted">
            {p.trials ? `${p.successes}/${p.trials}` : "—"}
          </td>
          <td className="px-4 py-2 text-muted">{p.note ?? "—"}</td>
        </tr>
      ))}
    </Table>
  );
}

/* -------------------------------------------------------------------------
 * Attendance
 * ---------------------------------------------------------------------- */

/**
 * Three months of attendance as one bar.
 *
 * Held / absent / excused, in that order, with a 2px surface gap between the
 * segments so the boundary is a gap rather than a border. Cancellations are
 * not in it: a session the academy called off is not the family's attendance,
 * and putting it here would be charging them for it.
 *
 * Every segment is written out underneath — these are status colours and they
 * never travel alone.
 */
export function AttendanceBar({
  held,
  absent,
  excused,
}: {
  held: number;
  absent: number;
  excused: number;
}) {
  const total = held + absent + excused;

  if (total === 0) {
    return <p className="px-4 py-6 text-center text-sm text-muted">ما في جلسات مسجّلة بعد.</p>;
  }

  const segments = [
    { key: "held", label: "حضر", value: held, color: "var(--viz-held)" },
    { key: "absent", label: "ما إجا", value: absent, color: "var(--viz-absent)" },
    { key: "excused", label: "غياب بعذر", value: excused, color: "var(--viz-excused)" },
  ].filter((s) => s.value > 0);

  return (
    <div className="p-4">
      <div className="flex h-3 w-full gap-[2px] overflow-hidden rounded-full">
        {segments.map((s) => (
          <div
            key={s.key}
            style={{ background: s.color, width: `${(s.value / total) * 100}%` }}
            title={`${s.label}: ${s.value}`}
          />
        ))}
      </div>

      <ul className="mt-3 flex flex-wrap items-center gap-x-5 gap-y-2">
        {segments.map((s) => (
          <li key={s.key} className="flex items-center gap-1.5">
            <span className="h-3 w-3 rounded-sm" style={{ background: s.color }} aria-hidden />
            <span className="text-xs text-muted">
              {s.label} <span className="tabular font-bold text-ink">{number(s.value)}</span>
            </span>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function AttendanceTable({
  held,
  absent,
  excused,
  rate,
}: {
  held: number;
  absent: number;
  excused: number;
  rate: number | null;
}) {
  return (
    <Table head={["", "عدد"]}>
      <tr>
        <td className="px-4 py-2 text-ink">حضر</td>
        <td className="tabular px-4 py-2 font-semibold text-ink">{number(held)}</td>
      </tr>
      <tr>
        <td className="px-4 py-2 text-ink">ما إجا</td>
        <td className="tabular px-4 py-2 font-semibold text-ink">{number(absent)}</td>
      </tr>
      <tr>
        <td className="px-4 py-2 text-ink">غياب بعذر</td>
        <td className="tabular px-4 py-2 font-semibold text-ink">{number(excused)}</td>
      </tr>
      <tr>
        <td className="px-4 py-2 font-semibold text-ink">نسبة الحضور</td>
        <td className="tabular px-4 py-2 font-bold text-ink">{percent(rate)}</td>
      </tr>
    </Table>
  );
}
