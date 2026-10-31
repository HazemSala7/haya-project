"use client";

import Link from "next/link";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { useAuth } from "@/lib/auth";
import { usePagedList } from "@/lib/paged";
import { PageHead } from "@/components/shell";
import { AccountCard, FeeDialog, InvoiceDialog, IssueDialog, PayDialog } from "@/components/finance";
import {
  Badge,
  Button,
  Card,
  Confirm,
  Empty,
  Input,
  Loading,
  Modal,
  Pager,
  RowAction,
  Select,
  Stat,
  Table,
  useDebounced,
} from "@/components/ui";
import {
  INVOICE_LABELS,
  INVOICE_TONES,
  childCount,
  date,
  invoiceCount,
  money,
  monthLabel,
  number,
} from "@/lib/format";
import type { BillingSummary, Invoice } from "@/lib/types";

/**
 * The office's money screen.
 *
 * It answers one question first — «مين ما دفع؟» — which is why the outstanding
 * figure is a tile and the default filter on the list is "في متبقّي" rather
 * than the whole archive. The month's own figures are beside it because the
 * second question is always «صدر الشهر ولا لأ؟».
 *
 * The month picker drives both halves. Issuing is a button and not a clock:
 * there is no scheduler on this host, so the screen has to say plainly when a
 * month has not been raised yet — see App\Services\Billing for why that is a
 * feature and not a shortcut.
 */
/**
 * The months the picker offers: this one and the eighteen before it, newest
 * first.
 *
 * A list rather than a date control. The office bills a recent month or looks
 * back at one it already billed; it never reaches 2019, and a free-form month
 * field invites a typo that quietly reports on a month nobody has heard of.
 * The list also names each month in Arabic, which the native control will not
 * do — see monthLabel.
 */
function recentMonths(count = 19): string[] {
  const now = new Date();
  return Array.from({ length: count }, (_, i) => {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
  });
}

export default function FinancePage() {
  const { can } = useAuth();
  const isAdmin = can("admin");

  /** The month the screen is about: "2026-10". */
  const [month, setMonth] = useState(() => new Date().toISOString().slice(0, 7));
  const [months] = useState(recentMonths);
  const [summary, setSummary] = useState<BillingSummary | null>(null);
  const [loadingSummary, setLoadingSummary] = useState(true);

  const [q, setQ] = useState("");
  const [status, setStatus] = useState("");
  const [outstanding, setOutstanding] = useState(true);
  /** Null = every month; otherwise the month above. */
  const [thisMonthOnly, setThisMonthOnly] = useState(false);

  const [issuing, setIssuing] = useState(false);
  const [paying, setPaying] = useState<Invoice | null>(null);
  const [editing, setEditing] = useState<Invoice | null>(null);
  const [removing, setRemoving] = useState<Invoice | null>(null);
  const [pricing, setPricing] = useState<{ id: number; name: string } | null>(null);
  const [account, setAccount] = useState<{ id: number; name: string } | null>(null);

  const period = `${month}-01`;
  const search = useDebounced(q);

  const list = usePagedList<Invoice, Record<string, never>>(
    "/billing/invoices",
    {
      q: search || undefined,
      status: status || undefined,
      outstanding: outstanding ? 1 : undefined,
      period: thisMonthOnly ? period : undefined,
    },
    // A specialist who types the URL gets the refusal below — not two 403s in
    // the log and a flash of an empty table on the way to it.
    { enabled: isAdmin },
  );

  const loadSummary = useCallback(async () => {
    if (!isAdmin) return;

    setLoadingSummary(true);

    try {
      const res = await api<{ data: BillingSummary }>("/billing/summary", {
        query: { period },
      });
      setSummary(res.data);
    } catch {
      setSummary(null);
    } finally {
      setLoadingSummary(false);
    }
  }, [period, isAdmin]);

  useEffect(() => {
    loadSummary();
  }, [loadSummary]);

  // `list.reload` is the stable identity from usePagedList; depending on the
  // whole list object would rebuild this on every render.
  const reload = list.reload;

  const refresh = useCallback(async () => {
    await loadSummary();
    reload();
  }, [loadSummary, reload]);

  if (!isAdmin) {
    return (
      <Empty
        boxed
        title="هذه الشاشة للإدارة"
        hint="حسابات الأهل المالية تشوفها الإدارة فقط — الأخصائية ما تشوف مين دفع ومين لأ."
      />
    );
  }

  return (
    <>
      <PageHead
        title="المالية"
        subtitle="اشتراك شهري لكل طفل، بتصدره الإدارة ويستحق أول الشهر."
        action={
          <div className="flex flex-wrap items-center gap-2">
            <Select
              value={month}
              onChange={(e) => setMonth(e.target.value)}
              className="w-44"
              aria-label="الشهر"
            >
              {months.map((m) => (
                <option key={m} value={m}>
                  {monthLabel(m)}
                </option>
              ))}
            </Select>
            <Button onClick={() => setIssuing(true)} disabled={!summary}>
              إصدار الشهر
            </Button>
          </div>
        }
      />

      {/* ---- where the academy stands ---- */}
      {loadingSummary ? (
        <Loading boxed rows={2} />
      ) : !summary ? null : (
        <>
          <div className="mb-4 grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
            <Stat
              label="متبقّي على الأهل"
              value={money(summary.outstanding_total, { zero: "0 ₪" })}
              hint={`${invoiceCount(summary.outstanding_count)} فيها متبقّي`}
              tone={summary.outstanding_total > 0 ? "bad" : "good"}
            />
            <Stat
              label={`فواتير ${summary.period_label}`}
              value={number(summary.issued)}
              hint={money(summary.issued_total, { zero: "ما صدر شي" })}
              tone={summary.issued > 0 ? "plain" : "warn"}
            />
            <Stat
              label="بانتظار الإصدار"
              value={number(summary.pending)}
              hint={
                summary.pending > 0
                  ? money(summary.pending_total)
                  : "كل الأطفال المحدَّد اشتراكهم انفوترو"
              }
              tone={summary.pending > 0 ? "warn" : "good"}
            />
            <Stat
              label="بلا اشتراك محدَّد"
              value={number(summary.unpriced)}
              hint={summary.unpriced > 0 ? "هدول بينتخطّو بالإصدار" : "كل الأطفال معهم اشتراك"}
              tone={summary.unpriced > 0 ? "warn" : "good"}
            />
          </div>

          {/*
            The unpriced children, by name.

            A count on a tile is a number nobody can act on. These are the
            children the monthly run will skip — so each one is a row with a
            button, and the list disappears the moment it is empty.
          */}
          {summary.unpriced_students.length > 0 && (
            <Card
              title="أطفال بلا اشتراك محدَّد"
              hint="هدول ما بينفوترو لما تصدر الشهر — حدّد اشتراكهم قبل الإصدار"
              className="mb-4"
              accent="var(--color-warn)"
            >
              <ul className="divide-y divide-line-soft">
                {summary.unpriced_students.map((student) => (
                  <li
                    key={student.id}
                    className="flex flex-wrap items-center justify-between gap-2 px-4 py-2.5"
                  >
                    <Link
                      href={`/students/view?id=${student.id}`}
                      className="text-sm font-semibold text-ink hover:text-brand"
                    >
                      {student.name}
                    </Link>
                    <RowAction tone="brand" onClick={() => setPricing(student)}>
                      حدّد الاشتراك
                    </RowAction>
                  </li>
                ))}
              </ul>
            </Card>
          )}

          {summary.pending > 0 && (
            <div className="mb-4 flex flex-wrap items-center justify-between gap-3 rounded-xl border border-brand/25 bg-brand-soft/60 px-4 py-3">
              <p className="text-sm font-semibold text-ink">
                اشتراك <b>{summary.period_label}</b> لسه ما صدر لـ{" "}
                <b>{childCount(summary.pending)}</b> — {money(summary.pending_total)}.
              </p>
              <Button onClick={() => setIssuing(true)}>أصدره الآن</Button>
            </div>
          )}
        </>
      )}

      {/* ---- the invoices ---- */}
      <Card className="mb-4">
        <div className="grid gap-3 p-4 sm:grid-cols-2 lg:grid-cols-4">
          <Input
            value={q}
            onChange={(e) => setQ(e.target.value)}
            placeholder="ابحث باسم الطفل أو رقم الفاتورة…"
          />

          <Select value={status} onChange={(e) => setStatus(e.target.value)}>
            <option value="">كل الحالات</option>
            {Object.entries(INVOICE_LABELS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </Select>

          <label className="flex items-center gap-2 text-sm font-semibold text-ink">
            <input
              type="checkbox"
              checked={outstanding}
              onChange={(e) => setOutstanding(e.target.checked)}
              className="h-4 w-4 accent-[var(--color-brand)]"
            />
            اللي عليه متبقّي بس
          </label>

          <label className="flex items-center gap-2 text-sm font-semibold text-ink">
            <input
              type="checkbox"
              checked={thisMonthOnly}
              onChange={(e) => setThisMonthOnly(e.target.checked)}
              className="h-4 w-4 accent-[var(--color-brand)]"
            />
            {summary ? summary.period_label : "هذا الشهر"} فقط
          </label>
        </div>
      </Card>

      <Card>
        {list.loading ? (
          <Loading />
        ) : list.rows.length === 0 ? (
          <Empty
            title="ما في فواتير بهذه الفلاتر"
            hint={
              outstanding
                ? "يمكن ما في متبقّي على حدا — شيل فلتر «اللي عليه متبقّي بس» لتشوف الكل."
                : "أصدر الشهر عشان تطلع فواتيره."
            }
          />
        ) : (
          <Table
            head={["الطفل", "الشهر", "الاستحقاق", "المطلوب", "المدفوع", "المتبقي", "الحالة", ""]}
          >
            {list.rows.map((row) => (
              <tr key={row.id}>
                <td className="px-4 py-2.5">
                  <Link
                    href={`/students/view?id=${row.student_id}`}
                    className="font-semibold text-ink hover:text-brand"
                  >
                    {row.student?.name ?? "—"}
                  </Link>
                  <div className="tabular text-xs text-muted">{row.number}</div>
                </td>
                <td className="px-4 py-2.5 text-muted">{row.period_label}</td>
                <td className="px-4 py-2.5 text-xs text-muted">{date(row.due_on)}</td>
                <td className="px-4 py-2.5 font-semibold text-ink">
                  {money(row.total, { zero: "0 ₪" })}
                  {Number(row.discount) > 0 && (
                    <div className="text-[11px] font-normal text-muted">
                      بعد خصم {money(row.discount)}
                    </div>
                  )}
                </td>
                <td className="px-4 py-2.5 text-muted">{money(row.paid, { zero: "—" })}</td>
                <td
                  className={`px-4 py-2.5 font-bold ${row.due > 0 ? "text-bad" : "text-muted"}`}
                >
                  {money(row.due, { zero: "—" })}
                </td>
                <td className="px-4 py-2.5">
                  <Badge className={INVOICE_TONES[row.status]}>
                    {row.status_label ?? INVOICE_LABELS[row.status]}
                  </Badge>
                </td>
                <td className="px-4 py-2.5 text-left">
                  <div className="flex flex-wrap justify-end gap-x-2 gap-y-1">
                    <RowAction tone="brand" onClick={() => setPaying(row)}>
                      {row.due > 0 ? "قبض" : "الإيصالات"}
                    </RowAction>
                    <RowAction onClick={() => setAccount({ id: row.student_id, name: row.student?.name ?? "" })}>
                      الحساب
                    </RowAction>
                    <RowAction onClick={() => setEditing(row)}>تعديل</RowAction>
                    <RowAction tone="danger" onClick={() => setRemoving(row)}>
                      حذف
                    </RowAction>
                  </div>
                </td>
              </tr>
            ))}
          </Table>
        )}

        <Pager meta={list.meta} onPage={list.setPage} unit="فاتورة" />
      </Card>

      <IssueDialog
        summary={issuing ? summary : null}
        onClose={() => setIssuing(false)}
        onDone={refresh}
      />

      <PayDialog invoice={paying} onClose={() => setPaying(null)} onDone={refresh} />

      <InvoiceDialog invoice={editing} onClose={() => setEditing(null)} onDone={refresh} />

      <FeeDialog student={pricing} onClose={() => setPricing(null)} onDone={refresh} />

      {/*
        One family's whole account, without leaving the list.

        The office is usually on this screen with a mother on the phone asking
        about three months at once, and sending them to the child's file and
        back loses the filter they were working down.
      */}
      {account && (
        <AccountModal
          id={account.id}
          name={account.name}
          onClose={() => {
            setAccount(null);
            refresh();
          }}
        />
      )}

      <Confirm
        open={removing !== null}
        onClose={() => setRemoving(null)}
        onConfirm={async () => {
          await api(`/billing/invoices/${removing!.id}`, { method: "DELETE" });
          await refresh();
        }}
        title="حذف الفاتورة"
        body={
          <>
            حذف فاتورة <b>{removing?.period_label}</b> عن <b>{removing?.student?.name}</b> بقيمة{" "}
            <b>{money(removing?.total, { zero: "0 ₪" })}</b>. إذا عليها دفعات مقبوضة النظام رح
            يرفض — شيل الدفعات أولاً من «الإيصالات».
          </>
        }
      />
    </>
  );
}

/**
 * The account card, in a dialog, for when the list is the place to stay.
 *
 * Built on the app's own `Modal` rather than a hand-rolled overlay so it
 * closes on Escape and locks the page behind it like every other dialog here —
 * a screen with four dialogs where one of them behaves differently is the one
 * that traps somebody.
 */
function AccountModal({
  id,
  name,
  onClose,
}: {
  id: number;
  name: string;
  onClose: () => void;
}) {
  return (
    <Modal open onClose={onClose} title={name} wide>
      <AccountCard studentId={id} canTakeMoney />
    </Modal>
  );
}
