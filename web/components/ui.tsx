"use client";

import Link from "next/link";
import { Suspense, useEffect, useRef, useState } from "react";
import { useSearchParams } from "next/navigation";
import type { PageMeta } from "@/lib/api";
import { fetchAttachment } from "@/lib/api";
import { LEVEL_LABELS, levelColor, levelInk } from "@/lib/format";

/*
 * The export is mounted at /haya on the server and at the root locally, so a
 * bare "/mark.png" 404s in one of the two. Next rewrites `basePath` into its
 * own links but not into a plain <img src>.
 */
const BASE_PATH = process.env.NEXT_PUBLIC_BASE_PATH ?? "";

/* -------------------------------------------------------------------------
 * Surfaces
 * ---------------------------------------------------------------------- */

/**
 * Every panel in the app.
 *
 * The elevation, the hairline highlight along the top edge and the tinted
 * header wash all live in globals.css as `.surface` and `.sheen`, so the whole
 * app changes depth together rather than forty components drifting apart.
 *
 * `accent` paints a 3px rail down the reading edge — used to colour a panel by
 * what it holds (a programme's hue, a status) without tinting the whole
 * background out from under the text sitting on it.
 */
export function Card({
  title,
  hint,
  action,
  icon,
  accent,
  children,
  className = "",
}: {
  title?: string;
  hint?: string;
  action?: React.ReactNode;
  icon?: React.ReactNode;
  accent?: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`surface sheen overflow-hidden ${accent ? "rail" : ""} ${className}`}
      style={accent ? ({ "--rail": accent } as React.CSSProperties) : undefined}
    >
      {(title || action) && (
        <header className="flex items-center justify-between gap-3 border-b border-line-soft bg-gradient-to-l from-surface via-panel to-panel px-4 py-3">
          <div className="flex min-w-0 items-center gap-2.5">
            {icon && (
              <span className="grid size-8 shrink-0 place-items-center rounded-lg bg-brand-soft text-brand ring-1 ring-brand/10">
                {icon}
              </span>
            )}
            <div className="min-w-0">
              {title && <h2 className="truncate text-sm font-bold text-ink">{title}</h2>}
              {hint && <p className="mt-0.5 text-xs text-muted">{hint}</p>}
            </div>
          </div>
          {action}
        </header>
      )}
      {children}
    </section>
  );
}

/**
 * A number on a tile.
 *
 * The tone rides on the rail and the label, never on a filled background: a
 * grid of four tinted boxes is a wall of colour where nothing stands out, and
 * the point of a tone here is that one of the four is worth looking at.
 */
export function Stat({
  label,
  value,
  hint,
  tone = "plain",
  href,
}: {
  label: string;
  value: string | number;
  hint?: string;
  tone?: "plain" | "good" | "warn" | "bad" | "brand";
  href?: string;
}) {
  const rails = {
    plain: "var(--color-line)",
    good: "var(--color-good)",
    warn: "var(--color-warn)",
    bad: "var(--color-bad)",
    brand: "var(--color-brand)",
  } as const;

  const body = (
    <div
      className={`surface sheen rail h-full p-4 ${href ? "raise cursor-pointer" : ""}`}
      style={{ "--rail": rails[tone] } as React.CSSProperties}
    >
      <div className="text-xs font-semibold text-muted">{label}</div>
      {/* `leading-tight`, not `leading-none`: a Stat often holds a phrase —
          "٠ — رفض / ما استجاب" — and a wrapped phrase set solid collides. */}
      <div className="figure-xl mt-1.5 text-[1.6rem] leading-tight font-extrabold text-ink">
        {value}
      </div>
      {hint && <div className="mt-1.5 text-xs text-muted">{hint}</div>}
    </div>
  );

  return href ? (
    <Link href={href} className="block h-full">
      {body}
    </Link>
  ) : (
    body
  );
}

/**
 * A status chip.
 *
 * The hairline is `ring-current/25` — the chip's own text colour at a quarter
 * strength — so every badge gets an outline in its own hue without each of the
 * fifteen tone maps in lib/format.ts having to name one.
 */
export function Badge({
  children,
  className = "bg-line/50 text-ink-soft",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ring-1 ring-current/25 ring-inset ${className}`}
    >
      {children}
    </span>
  );
}

/* -------------------------------------------------------------------------
 * The red band
 * ---------------------------------------------------------------------- */

/**
 * Allergies, medication, seizure history.
 *
 * Rendered across the top of every screen that shows this child — not inside a
 * notes tab, because a tab is opened once on enrolment day and the day it
 * matters is a day nobody was expecting. It is deliberately the loudest thing
 * on any screen it appears on.
 *
 * Draws nothing when there is no alert, so it never becomes furniture people
 * learn to skip past.
 */
export function MedicalAlert({ text }: { text?: string | null }) {
  if (!text) return null;

  return (
    <div
      role="alert"
      className="mb-4 flex items-start gap-3 rounded-xl border-2 border-alert/35 bg-alert-soft px-4 py-3"
    >
      <span aria-hidden className="mt-0.5 text-lg leading-none">
        ⚠️
      </span>
      <div>
        <div className="text-xs font-extrabold tracking-wide text-alert">تنبيه طبي</div>
        <p className="mt-0.5 text-sm font-semibold text-ink">{text}</p>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------
 * The prompt scale
 * ---------------------------------------------------------------------- */

/**
 * One score, as a filled chip.
 *
 * The colour comes from the validated ordinal ramp and the number is always
 * written on it — the ramp carries the ordering at a glance, the digit carries
 * the value for anyone who cannot separate two teals, and the label spells it
 * out for anyone reading it for the first time.
 */
export function LevelChip({
  level,
  showLabel = false,
  size = "md",
}: {
  level: number;
  showLabel?: boolean;
  size?: "sm" | "md";
}) {
  const box = size === "sm" ? "h-6 w-6 text-[11px]" : "h-7 w-7 text-xs";

  return (
    <span className="inline-flex items-center gap-2">
      <span
        className={`tabular inline-grid ${box} place-items-center rounded-lg font-extrabold shadow-soft ring-1 ring-black/5`}
        style={{ background: levelColor(level), color: levelInk(level) }}
        aria-hidden
      >
        {level}
      </span>
      <span className={showLabel ? "text-xs font-semibold text-ink" : "sr-only"}>
        {LEVEL_LABELS[level]}
      </span>
    </span>
  );
}

/** The whole scale, as a key. Shown wherever a chip appears without its label. */
export function LevelKey() {
  return (
    <ul className="flex flex-wrap items-center gap-x-4 gap-y-2">
      {[4, 3, 2, 1, 0].map((level) => (
        <li key={level} className="flex items-center gap-1.5">
          <span
            className="h-3 w-3 rounded-sm"
            style={{ background: levelColor(level) }}
            aria-hidden
          />
          <span className="text-[11px] text-muted">
            <span className="tabular font-semibold text-ink">{level}</span> {LEVEL_LABELS[level]}
          </span>
        </li>
      ))}
    </ul>
  );
}

/* -------------------------------------------------------------------------
 * Controls
 * ---------------------------------------------------------------------- */

export function Button({
  children,
  variant = "primary",
  className = "",
  ...props
}: React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: "primary" | "ghost" | "danger" | "quiet";
}) {
  /*
   * The primary button is a gradient between the wordmark teal and the darker
   * teal underneath it, not a flat fill — a two-stop vertical gradient is what
   * makes a button read as a physical thing to press rather than a coloured
   * rectangle. It presses in by a pixel on `:active`, which is the cheapest
   * honest feedback there is.
   */
  const variants = {
    primary:
      "bg-gradient-to-b from-brand to-brand-deep text-white shadow-soft hover:shadow-glow hover:brightness-105",
    ghost:
      "border border-line bg-panel text-ink shadow-soft hover:border-brand/35 hover:bg-brand-soft/50 hover:text-brand",
    danger: "border border-bad/30 bg-bad-soft text-bad hover:bg-bad/10 hover:border-bad/50",
    quiet: "text-muted hover:bg-line/40 hover:text-ink",
  } as const;

  return (
    <button
      {...props}
      className={`inline-flex items-center justify-center gap-2 rounded-lg px-3.5 py-2 text-sm font-semibold transition-all duration-200 active:translate-y-px disabled:cursor-not-allowed disabled:opacity-50 disabled:shadow-none ${variants[variant]} ${className}`}
    >
      {children}
    </button>
  );
}

export function Field({
  label,
  error,
  hint,
  children,
}: {
  label: string;
  error?: string;
  hint?: string;
  children: React.ReactNode;
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs font-semibold text-muted">{label}</span>
      {children}
      {error ? (
        <span className="mt-1 block text-xs font-medium text-bad">{error}</span>
      ) : hint ? (
        <span className="mt-1 block text-xs text-muted">{hint}</span>
      ) : null}
    </label>
  );
}

const inputClass =
  "w-full rounded-lg border border-line bg-panel px-3 py-2 text-sm text-ink shadow-[inset_0_1px_2px_rgb(27_106_102_/_0.04)] outline-none transition placeholder:text-muted/70 hover:border-brand/30 focus:border-brand focus:ring-4 focus:ring-brand/12";

/**
 * Fields fill their container unless the caller asks for a width.
 *
 * The `w-full` has to be *removed* rather than merely overridden: two width
 * utilities in one class list are resolved by the order they appear in the
 * stylesheet, not the order they were written in the attribute — so a
 * `className="w-40"` on a control that already carries `w-full` silently loses,
 * and the period picker on the analytics screen stretched the width of the
 * page. Dropping the default is the only fix that actually holds.
 */
function fieldClass(className?: string): string {
  const own = className ?? "";
  const setsWidth = /(^|\s)(w-|min-w-|max-w-)/.test(own);

  return `${setsWidth ? inputClass.replace("w-full ", "") : inputClass} ${own}`;
}

export function Input(props: React.InputHTMLAttributes<HTMLInputElement>) {
  return <input {...props} className={fieldClass(props.className)} />;
}

export function Select(props: React.SelectHTMLAttributes<HTMLSelectElement>) {
  return <select {...props} className={fieldClass(props.className)} />;
}

export function Textarea(props: React.TextareaHTMLAttributes<HTMLTextAreaElement>) {
  return <textarea {...props} className={fieldClass(props.className)} />;
}

/* -------------------------------------------------------------------------
 * Tables and states
 * ---------------------------------------------------------------------- */

/**
 * Every list in the app.
 *
 * Rows light up under the cursor in the brand's own tint — a whole-row
 * highlight is what keeps the eye on one child's line while it travels across
 * to the far column, and these tables are wide.
 *
 * The heading sits on the page's own off-white rather than on the panel, so
 * the band of column names separates from the rows without a heavy rule under
 * it.
 */
export function Table({ head, children }: { head: string[]; children: React.ReactNode }) {
  return (
    <div className="overflow-x-auto">
      <table className="w-full text-right text-sm">
        <thead>
          <tr className="border-b border-line bg-surface text-xs text-muted">
            {head.map((h) => (
              <th key={h} className="px-4 py-3 font-bold whitespace-nowrap">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-line-soft [&>tr]:transition-colors [&>tr:hover]:bg-brand-soft/45">
          {children}
        </tbody>
      </table>
    </div>
  );
}

/**
 * The empty state carries the next action, not just a shrug. A list that says
 * "no results" and nothing else leaves the user to work out what to do.
 *
 * The mark is set very faint behind it: an empty panel with nothing in it at
 * all reads as broken, and this is the one place the academy's own tree can
 * fill a hole without competing with anything.
 */
export function Empty({
  title,
  hint,
  action,
  boxed = false,
}: {
  title: string;
  hint?: string;
  action?: React.ReactNode;
  /**
   * For the four screens where an empty state IS the whole page — a record
   * that does not exist, or one that belongs to somebody else's child. Inside
   * a panel it needs no border of its own; alone on the page it reads as a
   * page that failed to load unless it is given one.
   */
  boxed?: boolean;
}) {
  return (
    <div className={`relative px-4 py-14 text-center ${boxed ? "surface sheen" : ""}`}>
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={`${BASE_PATH}/mark.png`}
        alt=""
        aria-hidden
        className="pointer-events-none absolute inset-0 m-auto w-28 opacity-[0.07] select-none"
      />
      <div className="relative">
        <p className="text-sm font-bold text-ink">{title}</p>
        {hint && <p className="mx-auto mt-1.5 max-w-sm text-xs leading-relaxed text-muted">{hint}</p>}
        {action && <div className="mt-4 flex justify-center">{action}</div>}
      </div>
    </div>
  );
}

/**
 * The shape of what is coming, not the word "loading".
 *
 * A skeleton holds the layout still while the request is in flight, so the page
 * does not jump when the data lands — and it tells the reader how much is
 * coming, which a spinner never does. The label is still there for a screen
 * reader.
 */
export function Loading({
  label = "عم نحمّل…",
  rows = 3,
  boxed = false,
}: {
  label?: string;
  rows?: number;
  /** Same reason as `Empty`'s: on its own on a page it needs a panel. */
  boxed?: boolean;
}) {
  return (
    <div className={`p-4 ${boxed ? "surface sheen" : ""}`} role="status" aria-live="polite">
      <span className="sr-only">{label}</span>
      <div className="skeleton h-3 w-32" />
      <div className="mt-4 space-y-2.5">
        {Array.from({ length: rows }, (_, i) => (
          <div key={i} className="flex items-center gap-3">
            <div className="skeleton size-9 shrink-0 rounded-full" />
            <div className="skeleton h-3 flex-1" style={{ maxWidth: `${88 - i * 11}%` }} />
          </div>
        ))}
      </div>
    </div>
  );
}

export function ErrorNote({ message }: { message: string }) {
  return (
    <div className="flex items-start gap-2 rounded-lg border border-bad/25 bg-bad-soft px-3 py-2 text-sm font-medium text-bad">
      <span aria-hidden className="mt-px leading-none">
        ⚠
      </span>
      <span>{message}</span>
    </div>
  );
}

export function Note({ children }: { children: React.ReactNode }) {
  return (
    <div className="flex items-start gap-2 rounded-lg border border-good/25 bg-good-soft px-3 py-2 text-sm font-medium text-good">
      <span aria-hidden className="mt-px leading-none">
        ✓
      </span>
      <span>{children}</span>
    </div>
  );
}

/* -------------------------------------------------------------------------
 * Attachments
 * ---------------------------------------------------------------------- */

/**
 * Fetches a session attachment with the bearer token and hands back a blob
 * URL, revoking it on unmount.
 *
 * The whole dance exists because the file is behind an auth check and a
 * browser sets no headers on an `<img src>` — see fetchAttachment in lib/api.
 */
export function useAttachment(id: number): { src: string | null; failed: boolean } {
  const [src, setSrc] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const current = useRef<string | null>(null);

  useEffect(() => {
    let cancelled = false;

    fetchAttachment(id)
      .then((url) => {
        if (cancelled) {
          URL.revokeObjectURL(url);
          return;
        }
        current.current = url;
        setSrc(url);
      })
      .catch(() => {
        if (!cancelled) setFailed(true);
      });

    return () => {
      cancelled = true;
      if (current.current) {
        URL.revokeObjectURL(current.current);
        current.current = null;
      }
    };
  }, [id]);

  return { src, failed };
}

export function AttachmentTile({
  id,
  kind,
  caption,
}: {
  id: number;
  kind: "image" | "video";
  caption?: string | null;
}) {
  const { src, failed } = useAttachment(id);

  return (
    <figure className="overflow-hidden rounded-xl border border-line bg-surface">
      <div className="grid aspect-video place-items-center bg-line/30">
        {failed ? (
          <span className="text-xs text-muted">تعذّر تحميل المرفق</span>
        ) : !src ? (
          <span className="text-xs text-muted">عم نحمّل…</span>
        ) : kind === "video" ? (
          <video src={src} controls className="h-full w-full object-contain" />
        ) : (
          // eslint-disable-next-line @next/next/no-img-element
          <img src={src} alt={caption ?? "صورة من الجلسة"} className="h-full w-full object-cover" />
        )}
      </div>
      {caption && (
        <figcaption className="px-3 py-2 text-xs text-muted">{caption}</figcaption>
      )}
    </figure>
  );
}

/* -------------------------------------------------------------------------
 * Paging
 * ---------------------------------------------------------------------- */

/**
 * The page numbers worth drawing: the ends, the current page and its
 * neighbours, and a gap for everything skipped.
 *
 * Seven slots stay the same width whatever the total, so the row never reflows
 * as the user walks through it.
 */
function pageWindow(current: number, last: number): (number | "gap")[] {
  if (last <= 7) return Array.from({ length: last }, (_, i) => i + 1);

  const start = Math.max(2, Math.min(current - 1, last - 3));
  const end = Math.min(last - 1, Math.max(current + 1, 4));

  const slots: (number | "gap")[] = [1];

  if (start > 2) slots.push("gap");
  for (let page = start; page <= end; page++) slots.push(page);
  if (end < last - 1) slots.push("gap");
  slots.push(last);

  return slots;
}

/**
 * Paging for a list.
 *
 * Draws nothing when everything already fits on one page. The range — "٢٦–٥٠
 * من ٤٨٠" — is the part that matters most: it is what tells someone the list
 * they are looking at is a window and not the whole of it.
 */
export function Pager({
  meta,
  onPage,
  unit = "سجل",
}: {
  meta: PageMeta | null;
  onPage: (page: number) => void;
  unit?: string;
}) {
  if (!meta || meta.last_page <= 1) return null;

  const { current_page: current, last_page: last, from, to, total } = meta;

  return (
    <nav
      className="flex flex-wrap items-center justify-between gap-3 border-t border-line px-4 py-3"
      aria-label="تنقّل بين الصفحات"
    >
      <p className="text-xs text-muted">
        <span className="tabular font-semibold text-ink">
          {from ?? 0}–{to ?? 0}
        </span>{" "}
        من أصل <span className="tabular font-semibold text-ink">{total}</span> {unit}
      </p>

      <div className="flex items-center gap-1">
        <PageButton disabled={current <= 1} onClick={() => onPage(current - 1)}>
          السابق
        </PageButton>

        {pageWindow(current, last).map((slot, index) =>
          slot === "gap" ? (
            <span key={`gap-${index}`} className="px-1 text-xs text-muted">
              …
            </span>
          ) : (
            <PageButton key={slot} active={slot === current} onClick={() => onPage(slot)}>
              <span className="tabular">{slot}</span>
            </PageButton>
          ),
        )}

        <PageButton disabled={current >= last} onClick={() => onPage(current + 1)}>
          التالي
        </PageButton>
      </div>
    </nav>
  );
}

function PageButton({
  children,
  active = false,
  disabled = false,
  onClick,
}: {
  children: React.ReactNode;
  active?: boolean;
  disabled?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      aria-current={active ? "page" : undefined}
      className={`min-w-8 rounded-lg border px-2.5 py-1.5 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-40 ${
        active
          ? "border-brand bg-brand text-white"
          : "border-line bg-panel text-muted hover:text-ink disabled:hover:text-muted"
      }`}
    >
      {children}
    </button>
  );
}

/* -------------------------------------------------------------------------
 * Dialog
 * ---------------------------------------------------------------------- */

export function Modal({
  open,
  onClose,
  title,
  children,
  wide = false,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: React.ReactNode;
  wide?: boolean;
}) {
  // Escape closes it, because a dialog that traps someone mid-task is worse
  // than no dialog at all.
  useEffect(() => {
    if (!open) return;

    const onKey = (event: KeyboardEvent) => {
      if (event.key === "Escape") onClose();
    };

    document.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";

    return () => {
      document.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-ink/45 p-4 pt-16 backdrop-blur-sm">
      <div
        role="dialog"
        aria-modal="true"
        className={`pop sheen w-full rounded-2xl border border-line bg-panel shadow-float ${wide ? "max-w-3xl" : "max-w-lg"}`}
      >
        <header className="flex items-center justify-between gap-3 rounded-t-2xl border-b border-line-soft bg-gradient-to-l from-surface via-panel to-panel px-4 py-3">
          <h2 className="text-sm font-bold text-ink">{title}</h2>
          <button
            onClick={onClose}
            className="grid size-7 place-items-center rounded-lg text-lg leading-none text-muted transition hover:bg-line/50 hover:text-ink"
            aria-label="إغلاق"
          >
            ×
          </button>
        </header>
        <div className="p-4">{children}</div>
      </div>
    </div>
  );
}

/* -------------------------------------------------------------------------
 * Destructive actions
 * ---------------------------------------------------------------------- */

/**
 * One confirmation dialog for everything that removes something.
 *
 * It names the thing being removed in the sentence rather than saying "are you
 * sure?", because "are you sure?" is a question people answer yes to without
 * reading. It also shows the server's refusal in place when there is one — the
 * API says no to plenty of deletions on purpose (a goal with measurements, a
 * specialist whose name is on published reports), and those messages are the
 * explanation the user needs, not an error to hide.
 */
export function Confirm({
  open,
  onClose,
  onConfirm,
  title,
  body,
  confirmLabel = "احذف",
  tone = "danger",
}: {
  open: boolean;
  onClose: () => void;
  onConfirm: () => Promise<void>;
  title: string;
  body: React.ReactNode;
  confirmLabel?: string;
  tone?: "danger" | "primary";
}) {
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (open) setError(null);
  }, [open]);

  async function go() {
    setBusy(true);
    setError(null);

    try {
      await onConfirm();
      onClose();
    } catch (e) {
      setError((e as { message?: string }).message ?? "تعذّر إتمام العملية.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open={open} onClose={onClose} title={title}>
      <div className="space-y-3">
        <div className="text-sm text-ink">{body}</div>
        {error && <ErrorNote message={error} />}
        <div className="flex gap-2 pt-1">
          <Button variant={tone} className="flex-1" disabled={busy} onClick={go}>
            {busy ? "لحظة…" : confirmLabel}
          </Button>
          <Button variant="ghost" onClick={onClose} disabled={busy}>
            إلغاء
          </Button>
        </div>
      </div>
    </Modal>
  );
}

/** The small text buttons that sit at the end of a table row. */
export function RowAction({
  children,
  tone = "plain",
  onClick,
}: {
  children: React.ReactNode;
  tone?: "plain" | "brand" | "danger";
  onClick: () => void;
}) {
  const tones = {
    plain: "text-muted hover:bg-line/60 hover:text-ink",
    brand: "text-brand hover:bg-brand-soft",
    danger: "text-bad hover:bg-bad-soft",
  } as const;

  return (
    <button
      type="button"
      onClick={onClick}
      className={`rounded-md px-2 py-1 text-xs font-semibold transition ${tones[tone]}`}
    >
      {children}
    </button>
  );
}

/* -------------------------------------------------------------------------
 * Record screens
 * ---------------------------------------------------------------------- */

function ResolveId({ children }: { children: (id: number) => React.ReactNode }) {
  const params = useSearchParams();
  const raw = params.get("id");
  const id = Number(raw);

  if (!raw || !Number.isFinite(id) || id <= 0) {
    return <Empty title="لا يوجد سجل محدّد" hint="افتح السجل من قائمته." />;
  }

  return <>{children(id)}</>;
}

/**
 * Reads `?id=` for record screens.
 *
 * The Suspense boundary is not optional: `useSearchParams` suspends during
 * prerender, and a static export fails the build without one. It is also why
 * this project has no `[id]` routes at all — see next.config.ts.
 */
export function WithId({ children }: { children: (id: number) => React.ReactNode }) {
  return (
    <Suspense fallback={<Loading />}>
      <ResolveId>{children}</ResolveId>
    </Suspense>
  );
}

/** Debounced text, so a search box does not fire a request per keystroke. */
export function useDebounced<T>(value: T, delay = 300): T {
  const [debounced, setDebounced] = useState(value);

  useEffect(() => {
    const timer = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(timer);
  }, [value, delay]);

  return debounced;
}
