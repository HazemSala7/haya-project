"use client";

/**
 * The academy's chart set.
 *
 * Hand-drawn in SVG rather than pulled from a charting library: the dashboard
 * ships as a static export to shared hosting, and a 300KB dependency to draw
 * nine figures is a bad trade for a page a mother opens on a phone at ten at
 * night. Everything here is one file and no runtime dependency.
 *
 * Every colour comes from the validated ramps in globals.css — see the comment
 * above them for exactly what was measured. One set of rules holds across all
 * of them:
 *
 *   · 2px lines, ≥8px markers, hairline gridlines, never a dashed data mark
 *   · a 2px gap in the surface colour between stacked segments, so the
 *     boundary is a gap rather than a border
 *   · text always in ink tokens, never in the series colour — a label in the
 *     mark's own hue is unreadable at label sizes and duplicates the mark's job
 *   · a legend whenever there is more than one series, and direct labels when
 *     there are four or fewer, so identity is never colour alone
 *   · every figure has a table view, which is the same data in the form that
 *     never fails — for the reader who cannot separate two hues, for the one
 *     who wants the exact figure, and for print
 *
 * Everything reads right to left, like the rest of the app: on a time axis the
 * oldest week sits at the right edge, where an Arabic reader starts.
 */

import { useEffect, useId, useRef, useState } from "react";
import { Card, Table } from "@/components/ui";
import { number } from "@/lib/format";

/* -------------------------------------------------------------------------
 * Plumbing
 * ---------------------------------------------------------------------- */

/** The plot's own width in real pixels, so 1px lines stay 1px. */
export function useWidth<T extends HTMLElement>() {
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
 * Axis ticks on round numbers — 0 / 25 / 50 — not on whatever the maximum
 * happens to be. The top tick becomes the scale, so the tallest mark never
 * touches the ceiling.
 */
export function niceTicks(max: number, count = 4): number[] {
  if (!Number.isFinite(max) || max <= 0) return [0, 1];

  const magnitude = 10 ** Math.floor(Math.log10(max / count));
  const normalised = max / count / magnitude;
  const step = (normalised <= 1 ? 1 : normalised <= 2 ? 2 : normalised <= 5 ? 5 : 10) * magnitude;

  const ticks: number[] = [];
  for (let value = 0; value < max + step; value += step) ticks.push(Number(value.toFixed(6)));

  return ticks;
}

export type Series = { name: string; color: string; values: (number | null)[] };

/** The frame every figure sits in: title, legend, and the table view. */
export function Figure({
  title,
  hint,
  legend,
  table,
  action,
  children,
  className = "",
}: {
  title: string;
  hint?: string;
  legend?: { name: string; color: string }[];
  table: React.ReactNode;
  action?: React.ReactNode;
  children: React.ReactNode;
  className?: string;
}) {
  const [asTable, setAsTable] = useState(false);

  return (
    <Card
      title={title}
      hint={hint}
      className={className}
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
      {/*
        Present whenever there is more than one series. Matching a colour to a
        key is the one identity channel that never depends on the reader seeing
        hue the way the author does.
      */}
      {legend && legend.length > 1 && !asTable && (
        <ul className="flex flex-wrap items-center gap-1.5 px-4 pt-3">
          {legend.map((item) => (
            <li
              key={item.name}
              className="inline-flex items-center gap-1.5 rounded-full bg-surface px-2 py-1 ring-1 ring-line-soft ring-inset"
            >
              <span
                className="size-2.5 rounded-full ring-1 ring-black/5"
                style={{ background: item.color }}
                aria-hidden
              />
              <span className="text-[11px] font-semibold text-ink-soft">{item.name}</span>
            </li>
          ))}
        </ul>
      )}

      {asTable ? table : children}
    </Card>
  );
}

/** The floating readout every chart shares. */
function Tip({
  x,
  width,
  children,
}: {
  x: number;
  width: number;
  children: React.ReactNode;
}) {
  return (
    <div
      className="pop pointer-events-none absolute z-10 min-w-32 rounded-xl border border-line bg-panel/95 px-3 py-2 text-xs shadow-float backdrop-blur"
      style={{
        right: Math.min(Math.max(width - x - 70, 4), Math.max(width - 160, 4)),
        top: 4,
      }}
    >
      {children}
    </div>
  );
}

/* -------------------------------------------------------------------------
 * Lines
 * ---------------------------------------------------------------------- */

/**
 * One or more series over time, with a crosshair.
 *
 * `yMax` is passed in rather than fitted whenever the scale means something on
 * its own — a prompt-level average has to sit on the full 0–4 axis, or a class
 * that crept from 1.8 to 2.4 gets drawn filling the plot as though it had
 * arrived.
 *
 * Null values break the line instead of being drawn as zero: a week with no
 * measurements is not a week the children scored nothing.
 */
export function LineChart({
  labels,
  series,
  yMax,
  yMin = 0,
  height = 200,
  formatValue = (v: number) => number(v),
  suffix = "",
}: {
  labels: string[];
  series: Series[];
  yMax?: number;
  yMin?: number;
  height?: number;
  formatValue?: (v: number) => string;
  suffix?: string;
}) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const [hover, setHover] = useState<number | null>(null);

  const pad = { top: 14, right: 40, bottom: 26, left: 10 };
  const plotW = Math.max(0, width - pad.left - pad.right);
  const plotH = height - pad.top - pad.bottom;

  const flat = series.flatMap((s) => s.values).filter((v): v is number => v !== null);
  const top = yMax ?? Math.max(1, ...flat);
  const ticks = yMax ? niceTicks(top, 4) : niceTicks(top, 4);

  const n = labels.length;
  // Right to left: the oldest point sits at the right edge.
  const x = (i: number) => pad.left + plotW - (n <= 1 ? plotW / 2 : (i / (n - 1)) * plotW);
  const y = (v: number) =>
    pad.top + plotH - ((v - yMin) / Math.max(1e-9, top - yMin)) * plotH;

  /** Break the path wherever the data does. */
  const path = (values: (number | null)[]) => {
    let d = "";
    let pen = false;

    values.forEach((v, i) => {
      if (v === null) {
        pen = false;
        return;
      }
      d += `${pen ? "L" : "M"} ${x(i)} ${y(v)} `;
      pen = true;
    });

    return d.trim();
  };

  /*
   * The same run of points, closed down to the floor.
   *
   * Only ever drawn when there is a single series: two translucent washes
   * overlapping produce a third colour that is in neither legend, and the
   * reader has no way to tell which series the darker patch belongs to. With
   * one line it is unambiguous, and the fill is what turns a thin stroke into
   * a shape the eye can weigh at a glance.
   *
   * A gap in the data breaks the fill exactly where it breaks the line, so a
   * week with no measurements never gets quietly coloured in.
   */
  const areas = (values: (number | null)[]) => {
    const floor = pad.top + plotH;
    const out: string[] = [];
    let run: number[] = [];

    const flush = () => {
      if (run.length > 1) {
        const line = run
          .map((i, k) => `${k === 0 ? "M" : "L"} ${x(i)} ${y(values[i]!)}`)
          .join(" ");
        out.push(`${line} L ${x(run[run.length - 1])} ${floor} L ${x(run[0])} ${floor} Z`);
      }
      run = [];
    };

    values.forEach((v, i) => (v === null ? flush() : run.push(i)));
    flush();

    return out;
  };

  // Sanitised because React's own ids carry punctuation that url(#…) chokes on.
  const gradientId = `ln${useId().replace(/[^a-zA-Z0-9]/g, "")}`;

  return (
    <div className="p-4">
      <div ref={ref} className="relative">
        {width > 0 && (
          <svg
            width={width}
            height={height}
            role="img"
            aria-label={`${series.map((s) => s.name).join("، ")} — ${n} نقطة`}
            onMouseLeave={() => setHover(null)}
          >
            {ticks.map((t) => (
              <g key={t}>
                <line
                  x1={pad.left}
                  x2={pad.left + plotW}
                  y1={y(t)}
                  y2={y(t)}
                  stroke="var(--viz-grid)"
                  strokeWidth={1}
                />
                <text
                  x={pad.left + plotW + 6}
                  y={y(t) + 4}
                  className="fill-muted"
                  style={{ fontSize: 10 }}
                >
                  {formatValue(t)}
                  {suffix}
                </text>
              </g>
            ))}

            {series.length === 1 && (
              <>
                <defs>
                  <linearGradient id={gradientId} x1="0" y1="0" x2="0" y2="1">
                    <stop offset="0%" stopColor={series[0].color} stopOpacity={0.24} />
                    <stop offset="70%" stopColor={series[0].color} stopOpacity={0.06} />
                    <stop offset="100%" stopColor={series[0].color} stopOpacity={0} />
                  </linearGradient>
                </defs>
                {areas(series[0].values).map((d, i) => (
                  <path key={i} d={d} fill={`url(#${gradientId})`} />
                ))}
              </>
            )}

            {series.map((s) => (
              <path
                key={s.name}
                d={path(s.values)}
                fill="none"
                stroke={s.color}
                strokeWidth={2.25}
                strokeLinejoin="round"
                strokeLinecap="round"
              />
            ))}

            {/* Crosshair + markers for the hovered column. */}
            {hover !== null && (
              <line
                x1={x(hover)}
                x2={x(hover)}
                y1={pad.top}
                y2={pad.top + plotH}
                stroke="var(--viz-axis)"
                strokeWidth={1}
              />
            )}

            {series.map((s) =>
              s.values.map((v, i) =>
                v === null ? null : (
                  <circle
                    key={`${s.name}-${i}`}
                    cx={x(i)}
                    cy={y(v)}
                    r={hover === i ? 5 : n > 20 ? 0 : 3.5}
                    fill={s.color}
                    stroke="var(--color-panel)"
                    strokeWidth={2}
                  />
                ),
              ),
            )}

            {/* Hit targets far bigger than the marks. */}
            {labels.map((_, i) => (
              <rect
                key={i}
                x={x(i) - (plotW / Math.max(1, n)) / 2}
                y={pad.top}
                width={Math.max(8, plotW / Math.max(1, n))}
                height={plotH}
                fill="transparent"
                onMouseEnter={() => setHover(i)}
              />
            ))}

            {/* Only the ends are labelled — a date under every point is a wall. */}
            <text x={x(0)} y={height - 8} textAnchor="middle" className="fill-muted" style={{ fontSize: 10 }}>
              {labels[0]}
            </text>
            {n > 1 && (
              <text
                x={x(n - 1)}
                y={height - 8}
                textAnchor="middle"
                className="fill-muted"
                style={{ fontSize: 10 }}
              >
                {labels[n - 1]}
              </text>
            )}
          </svg>
        )}

        {hover !== null && (
          <Tip x={x(hover)} width={width}>
            <div className="font-bold text-ink">{labels[hover]}</div>
            {series.map((s) => (
              <div key={s.name} className="mt-1 flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 rounded-sm" style={{ background: s.color }} aria-hidden />
                <span className="text-muted">{s.name}</span>
                <span className="tabular mr-auto font-semibold text-ink">
                  {s.values[hover] === null ? "—" : formatValue(s.values[hover]!) + suffix}
                </span>
              </div>
            ))}
          </Tip>
        )}
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------
 * Bars
 * ---------------------------------------------------------------------- */

/**
 * Stacked columns over time.
 *
 * The 2px gap between segments is in the surface colour, not a border: a
 * border darkens the boundary and reads as a third category at small sizes.
 */
export function StackedBars({
  labels,
  series,
  height = 200,
}: {
  labels: string[];
  series: Series[];
  height?: number;
}) {
  const [ref, width] = useWidth<HTMLDivElement>();
  const [hover, setHover] = useState<number | null>(null);

  const pad = { top: 14, right: 36, bottom: 26, left: 10 };
  const plotW = Math.max(0, width - pad.left - pad.right);
  const plotH = height - pad.top - pad.bottom;

  const n = labels.length;
  const totals = labels.map((_, i) =>
    series.reduce((sum, s) => sum + (s.values[i] ?? 0), 0),
  );
  const ticks = niceTicks(Math.max(1, ...totals), 3);
  const top = ticks[ticks.length - 1];

  const slot = n > 0 ? plotW / n : plotW;
  const barW = Math.max(4, Math.min(28, slot * 0.62));
  // Right to left: the oldest column is at the right edge.
  const cx = (i: number) => pad.left + plotW - (i + 0.5) * slot;
  const y = (v: number) => pad.top + plotH - (v / top) * plotH;

  return (
    <div className="p-4">
      <div ref={ref} className="relative">
        {width > 0 && (
          <svg width={width} height={height} role="img" onMouseLeave={() => setHover(null)}>
            {ticks.map((t) => (
              <g key={t}>
                <line
                  x1={pad.left}
                  x2={pad.left + plotW}
                  y1={y(t)}
                  y2={y(t)}
                  stroke="var(--viz-grid)"
                  strokeWidth={1}
                />
                <text
                  x={pad.left + plotW + 6}
                  y={y(t) + 4}
                  className="fill-muted"
                  style={{ fontSize: 10 }}
                >
                  {number(t)}
                </text>
              </g>
            ))}

            {labels.map((_, i) => {
              let base = 0;

              return (
                <g key={i} onMouseEnter={() => setHover(i)}>
                  <rect
                    x={cx(i) - slot / 2}
                    y={pad.top}
                    width={slot}
                    height={plotH}
                    fill={hover === i ? "var(--color-surface)" : "transparent"}
                  />
                  {series.map((s) => {
                    const v = s.values[i] ?? 0;
                    if (v <= 0) return null;

                    const h = (v / top) * plotH;
                    const yTop = pad.top + plotH - base - h;
                    base += h + 2; // the 2px surface gap

                    return (
                      <rect
                        key={s.name}
                        x={cx(i) - barW / 2}
                        y={yTop}
                        width={barW}
                        height={Math.max(1, h - 2)}
                        rx={2}
                        fill={s.color}
                      />
                    );
                  })}
                </g>
              );
            })}

            <text x={cx(0)} y={height - 8} textAnchor="middle" className="fill-muted" style={{ fontSize: 10 }}>
              {labels[0]}
            </text>
            {n > 1 && (
              <text
                x={cx(n - 1)}
                y={height - 8}
                textAnchor="middle"
                className="fill-muted"
                style={{ fontSize: 10 }}
              >
                {labels[n - 1]}
              </text>
            )}
          </svg>
        )}

        {hover !== null && (
          <Tip x={cx(hover)} width={width}>
            <div className="font-bold text-ink">{labels[hover]}</div>
            {series.map((s) => (
              <div key={s.name} className="mt-1 flex items-center gap-1.5">
                <span className="h-2.5 w-2.5 rounded-sm" style={{ background: s.color }} aria-hidden />
                <span className="text-muted">{s.name}</span>
                <span className="tabular mr-auto font-semibold text-ink">
                  {number(s.values[hover] ?? 0)}
                </span>
              </div>
            ))}
          </Tip>
        )}
      </div>
    </div>
  );
}

/**
 * Horizontal bars — for categories with words for names.
 *
 * Horizontal because the labels are Arabic phrases: rotated under a vertical
 * axis they become unreadable, and truncated they become useless. The value
 * is written at the end of every bar, so the chart is legible without the
 * axis at all.
 */
export function HBars({
  rows,
  max,
  suffix = "",
}: {
  rows: { label: string; value: number; color?: string; hint?: string }[];
  max?: number;
  suffix?: string;
}) {
  const top = Math.max(1, max ?? Math.max(...rows.map((r) => r.value), 1));

  if (rows.every((r) => r.value === 0)) {
    return <p className="px-4 py-8 text-center text-sm text-muted">ما في بيانات بعد.</p>;
  }

  return (
    <ul className="space-y-2.5 p-4">
      {rows.map((row) => (
        <li key={row.label}>
          <div className="mb-1 flex items-baseline justify-between gap-3">
            <span className="text-xs font-semibold text-ink">{row.label}</span>
            <span className="tabular text-xs font-bold text-ink">
              {number(row.value)}
              {suffix}
              {row.hint && <span className="mr-1.5 font-normal text-muted">{row.hint}</span>}
            </span>
          </div>
          <div className="h-2.5 w-full overflow-hidden rounded-full bg-line/50">
            <div
              className="h-full rounded-full transition-[width] duration-500"
              style={{
                width: `${Math.max(row.value > 0 ? 2 : 0, (row.value / top) * 100)}%`,
                background: row.color ?? "var(--viz-brand)",
              }}
            />
          </div>
        </li>
      ))}
    </ul>
  );
}

/* -------------------------------------------------------------------------
 * Donut
 * ---------------------------------------------------------------------- */

/**
 * A part-of-whole, with the headline number in the middle.
 *
 * Used only where there are two or three slices and the whole genuinely means
 * something — "of the reports we sent, how many were opened". A donut of eight
 * categories is a puzzle; a bar chart is the answer to that.
 */
export function Donut({
  slices,
  centerValue,
  centerLabel,
  size = 168,
}: {
  slices: { name: string; value: number; color: string }[];
  centerValue: string;
  centerLabel: string;
  size?: number;
}) {
  const total = slices.reduce((sum, s) => sum + s.value, 0);
  const stroke = 18;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;

  let offset = 0;

  return (
    <div className="flex flex-wrap items-center justify-center gap-6 p-4">
      <div className="relative" style={{ width: size, height: size }}>
        <svg width={size} height={size} className="-rotate-90" role="img">
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            fill="none"
            stroke="var(--color-line)"
            strokeWidth={stroke}
          />
          {total > 0 &&
            slices.map((s) => {
              const len = (s.value / total) * c;
              // A 2px gap in the surface colour, same rule as the stacks.
              const dash = `${Math.max(0, len - 2)} ${c - Math.max(0, len - 2)}`;
              const el = (
                <circle
                  key={s.name}
                  cx={size / 2}
                  cy={size / 2}
                  r={r}
                  fill="none"
                  stroke={s.color}
                  strokeWidth={stroke}
                  strokeDasharray={dash}
                  strokeDashoffset={-offset}
                />
              );
              offset += len;
              return el;
            })}
        </svg>

        <div className="absolute inset-0 grid place-items-center text-center">
          <div>
            <div className="tabular text-2xl font-extrabold text-ink">{centerValue}</div>
            <div className="text-[11px] text-muted">{centerLabel}</div>
          </div>
        </div>
      </div>

      <ul className="space-y-2">
        {slices.map((s) => (
          <li key={s.name} className="flex items-center gap-2">
            <span className="h-3 w-3 rounded-sm" style={{ background: s.color }} aria-hidden />
            <span className="text-xs text-muted">{s.name}</span>
            <span className="tabular mr-2 text-xs font-bold text-ink">{number(s.value)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

/* -------------------------------------------------------------------------
 * Table views
 * ---------------------------------------------------------------------- */

export function SeriesTable({
  labels,
  series,
  head,
}: {
  labels: string[];
  series: Series[];
  head: string;
}) {
  return (
    <Table head={[head, ...series.map((s) => s.name)]}>
      {[...labels].map((label, i) => (
        <tr key={label}>
          <td className="px-4 py-2 font-semibold text-ink">{label}</td>
          {series.map((s) => (
            <td key={s.name} className="tabular px-4 py-2 text-muted">
              {s.values[i] === null ? "—" : number(s.values[i]!)}
            </td>
          ))}
        </tr>
      ))}
    </Table>
  );
}

export function RowsTable({
  rows,
  head,
  suffix = "",
}: {
  rows: { label: string; value: number; hint?: string }[];
  head: [string, string];
  suffix?: string;
}) {
  return (
    <Table head={[head[0], head[1]]}>
      {rows.map((row) => (
        <tr key={row.label}>
          <td className="px-4 py-2 text-ink">{row.label}</td>
          <td className="tabular px-4 py-2 font-semibold text-ink">
            {number(row.value)}
            {suffix}
            {row.hint && <span className="mr-2 font-normal text-muted">{row.hint}</span>}
          </td>
        </tr>
      ))}
    </Table>
  );
}

/* -------------------------------------------------------------------------
 * Small marks — the ones that live inside other things
 * ---------------------------------------------------------------------- */

/**
 * A trend, small enough to sit inside a number tile.
 *
 * No axis and no labels: it is not there to be read off, it is there so the
 * number above it stops being a snapshot. The last point is marked because
 * "where it ended" is the only value on it anyone reads precisely.
 */
export function Spark({
  values,
  color = "var(--viz-brand)",
  width = 108,
  height = 32,
  fill = true,
}: {
  values: (number | null)[];
  color?: string;
  width?: number;
  height?: number;
  fill?: boolean;
}) {
  const real = values.filter((v): v is number => v !== null);
  if (real.length < 2) return null;

  const min = Math.min(...real);
  const max = Math.max(...real);
  const span = Math.max(1e-9, max - min);

  const n = values.length;
  // Right to left, like every other time axis in the app.
  const x = (i: number) => width - (i / (n - 1)) * width;
  const y = (v: number) => height - 3 - ((v - min) / span) * (height - 6);

  let d = "";
  let pen = false;
  values.forEach((v, i) => {
    if (v === null) {
      pen = false;
      return;
    }
    d += `${pen ? "L" : "M"} ${x(i)} ${y(v)} `;
    pen = true;
  });

  const lastIndex = values.reduce<number>((acc, v, i) => (v !== null ? i : acc), -1);
  const area =
    lastIndex >= 0 ? `${d} L ${x(lastIndex)} ${height} L ${x(n - 1)} ${height} Z` : "";

  return (
    <svg width={width} height={height} aria-hidden className="overflow-visible">
      {fill && <path d={area} fill={color} opacity={0.12} />}
      <path d={d.trim()} fill="none" stroke={color} strokeWidth={2} strokeLinejoin="round" />
      {lastIndex >= 0 && (
        <circle
          cx={x(lastIndex)}
          cy={y(values[lastIndex]!)}
          r={3}
          fill={color}
          stroke="var(--color-panel)"
          strokeWidth={1.5}
        />
      )}
    </svg>
  );
}

/**
 * A single proportion as an arc.
 *
 * Used where the number is the headline and the arc is only there to say how
 * close to full it is — an attendance rate, a share of reports opened. Never
 * for comparing two things: that is what bars are for.
 */
export function Gauge({
  value,
  max = 100,
  size = 132,
  color = "var(--viz-brand)",
  label,
  caption,
}: {
  value: number | null;
  max?: number;
  size?: number;
  color?: string;
  label: string;
  caption?: string;
}) {
  const stroke = 12;
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  // Three quarters of a turn, opened at the bottom — a full ring reads as a
  // donut, which promises parts of a whole this is not.
  const sweep = 0.75;
  const pct = value === null ? 0 : Math.max(0, Math.min(1, value / max));

  return (
    <div className="flex flex-col items-center">
      <div className="relative" style={{ width: size, height: size }}>
        <svg width={size} height={size} className="rotate-[135deg]" role="img" aria-label={label}>
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            fill="none"
            stroke="var(--color-line)"
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeDasharray={`${c * sweep} ${c}`}
          />
          <circle
            cx={size / 2}
            cy={size / 2}
            r={r}
            fill="none"
            stroke={color}
            strokeWidth={stroke}
            strokeLinecap="round"
            strokeDasharray={`${c * sweep * pct} ${c}`}
            className="transition-[stroke-dasharray] duration-700"
          />
        </svg>
        <div className="absolute inset-0 grid place-items-center text-center">
          <div>
            <div className="tabular text-2xl font-extrabold text-ink">
              {value === null ? "—" : `${Math.round(value)}${max === 100 ? "٪" : ""}`}
            </div>
            {caption && <div className="text-[11px] text-muted">{caption}</div>}
          </div>
        </div>
      </div>
      <p className="mt-1 text-xs font-semibold text-muted">{label}</p>
    </div>
  );
}

/**
 * A number, large — with an optional trend under it and a delta beside it.
 *
 * `tone` is for the ones that mean act now. A red count reads before its label
 * does, which is the whole point of putting it on the first screen.
 */
export function Kpi({
  label,
  value,
  hint,
  delta,
  tone = "plain",
  spark,
  sparkColor,
  href,
  icon,
}: {
  label: string;
  value: string | number;
  hint?: string;
  delta?: { value: number; suffix?: string; goodWhenUp?: boolean } | null;
  tone?: "plain" | "good" | "warn" | "bad" | "brand";
  spark?: (number | null)[];
  sparkColor?: string;
  href?: string;
  icon?: React.ReactNode;
}) {
  /*
   * The tone rides on a 3px rail down the reading edge and on the label chip,
   * not on the tile's background.
   *
   * Four tinted tiles side by side is a wall of colour in which nothing is
   * urgent; four white tiles of which one wears a red rail is a row with one
   * thing to do in it. The number itself always sits on white, where it has the
   * full contrast the largest text on the screen deserves.
   */
  const tones = {
    plain: { rail: "var(--color-line)", ink: "text-muted", wash: "bg-line/50" },
    good: { rail: "var(--color-good)", ink: "text-good", wash: "bg-good-soft" },
    warn: { rail: "var(--color-warn)", ink: "text-warn", wash: "bg-warn-soft" },
    bad: { rail: "var(--color-bad)", ink: "text-bad", wash: "bg-bad-soft" },
    brand: { rail: "var(--color-brand)", ink: "text-brand", wash: "bg-brand-soft" },
  } as const;

  const t = tones[tone];
  const up = delta ? delta.value > 0 : false;
  const good = delta ? (delta.goodWhenUp === false ? !up : up) : false;

  const body = (
    <div
      className={`surface sheen rail flex h-full flex-col justify-between p-4 ${href ? "raise" : ""}`}
      style={{ "--rail": t.rail } as React.CSSProperties}
    >
      <div className="flex items-start justify-between gap-2">
        <div className="text-xs font-semibold text-muted">{label}</div>
        {icon && (
          <span className={`grid size-8 shrink-0 place-items-center rounded-lg ${t.wash} ${t.ink}`}>
            {icon}
          </span>
        )}
      </div>

      <div className="mt-3 flex items-end justify-between gap-3">
        <div className="min-w-0">
          {/*
            Always ink, never the tone's own hue. #d99a1a on white is 2.2:1 —
            a warning colour that would make the largest number on the screen
            the hardest one to read. The rail and the icon chip carry the tone;
            the figure carries the contrast.
          */}
          <div className="figure-xl text-[1.9rem] leading-none font-extrabold text-ink">{value}</div>
          {(hint || delta) && (
            <div className="mt-2 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs">
              {delta && delta.value !== 0 && (
                <span
                  className={`tabular inline-flex items-center gap-0.5 rounded-md px-1.5 py-0.5 font-bold ${
                    good ? "bg-good/10 text-good" : "bg-bad/10 text-bad"
                  }`}
                >
                  <span aria-hidden>{up ? "▲" : "▼"}</span>
                  {Math.abs(delta.value)}
                  {delta.suffix ?? ""}
                </span>
              )}
              {hint && <span className="text-muted">{hint}</span>}
            </div>
          )}
        </div>

        {spark && spark.filter((v) => v !== null).length > 1 && (
          <Spark values={spark} color={sparkColor ?? "var(--viz-brand)"} width={92} height={30} />
        )}
      </div>
    </div>
  );

  return href ? (
    <a href={href} className="block h-full">
      {body}
    </a>
  ) : (
    body
  );
}
