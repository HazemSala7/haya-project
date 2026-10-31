"use client";

/**
 * The academy's money, as screens.
 *
 * One module rather than a dialog per page, because the same four actions are
 * reached from two places: the office works down the billing screen, and the
 * same office opens a child's file and takes the money the mother is standing
 * there holding. Writing them twice is how the two drift until a payment taken
 * from the file behaves differently from one taken from the list.
 *
 * What is NOT here is anything a specialist can see. The whole module is
 * behind the office wall — see routes/api.php — and the one endpoint a family
 * reaches is their own child's account, read-only. `AccountCard` takes
 * `canTakeMoney` rather than reading the role itself, so the caller is forced
 * to say out loud which of the two screens it is.
 */

import { useCallback, useEffect, useState } from "react";
import { ApiError, api } from "@/lib/api";
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
  RowAction,
  Select,
  Textarea,
} from "@/components/ui";
import {
  INVOICE_LABELS,
  INVOICE_TONES,
  METHOD_LABELS,
  childCount,
  date,
  invoiceCount,
  money,
  number,
  plural,
} from "@/lib/format";
import type { BillingSummary, Invoice, IssueResult, StudentAccount } from "@/lib/types";

/** The academy's own calendar day, for a receipt dated today. */
export function todayISO(): string {
  return new Date().toLocaleDateString("en-CA");
}

/* -------------------------------------------------------------------------
 * The agreed fee
 * ---------------------------------------------------------------------- */

/**
 * What this family pays a month.
 *
 * A standing arrangement, not money — so it says plainly that changing it does
 * nothing to a month already issued. The office that expects this field to fix
 * October's invoice will otherwise set it, look at October, and conclude the
 * system is broken.
 *
 * Clearing it is offered as plainly as setting it: a child who has left, or
 * one the academy is carrying for free, has to be removable from the monthly
 * run without anybody inventing a fee of zero.
 */
export function FeeDialog({
  student,
  onClose,
  onDone,
}: {
  student: { id: number; name: string; monthly_fee?: string | null } | null;
  onClose: () => void;
  onDone: () => void | Promise<void>;
}) {
  const [fee, setFee] = useState("");
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!student) return;
    setError(null);
    // The stored decimal is "400.00"; a form field showing that invites
    // somebody to retype it. Number() drops the zeros, and `?? ""` keeps an
    // unpriced child's box genuinely empty rather than showing a 0.
    setFee(student.monthly_fee ? String(Number(student.monthly_fee)) : "");
  }, [student]);

  if (!student) return null;

  async function save(value: string | null) {
    setBusy(true);
    setError(null);

    try {
      await api(`/students/${student!.id}/fee`, {
        method: "PUT",
        body: { monthly_fee: value === null || value.trim() === "" ? null : Number(value) },
      });
      await onDone();
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title={`اشتراك ${student.name}`}>
      <form
        className="space-y-3"
        onSubmit={(event) => {
          event.preventDefault();
          save(fee);
        }}
      >
        {error && <ErrorNote message={error.for("monthly_fee") ?? error.message} />}

        <Field
          label="الاشتراك الشهري"
          hint="اللي اتفقتوا عليه مع الأهل. بينحسب أول ما تصدر الشهر."
        >
          <Input
            type="number"
            min="0"
            step="any"
            autoFocus
            value={fee}
            onChange={(e) => setFee(e.target.value)}
            placeholder="400"
          />
        </Field>

        <p className="rounded-lg bg-surface px-3 py-2 text-xs leading-relaxed text-muted">
          التعديل بيسري على الشهور اللي بعد. الفاتورة اللي صدرت قبل هلق ما بتتغيّر —
          تعديلها من الفاتورة نفسها، عشان فاتورة الأهل دفعوا عليها ما تتبدّل من تحتهم.
        </p>

        <div className="flex flex-wrap gap-2 pt-1">
          <Button type="submit" disabled={busy} className="flex-1">
            {busy ? "عم نحفظ…" : "احفظ"}
          </Button>
          {student.monthly_fee && (
            <Button type="button" variant="danger" disabled={busy} onClick={() => save(null)}>
              شيل الاشتراك
            </Button>
          )}
          <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/* -------------------------------------------------------------------------
 * Issuing the month
 * ---------------------------------------------------------------------- */

/**
 * The one button in the system that creates a debt against every family in the
 * building — so it says what it is about to do before it does it, and what it
 * did afterwards.
 *
 * The result stays on screen until it is dismissed. `skipped` is the whole
 * value of this dialog: the children who were not charged, by name, which is
 * the only moment anybody will notice that a fee was never agreed.
 */
export function IssueDialog({
  summary,
  onClose,
  onDone,
}: {
  summary: BillingSummary | null;
  onClose: () => void;
  onDone: () => void | Promise<void>;
}) {
  const [dueDay, setDueDay] = useState("");
  const [result, setResult] = useState<IssueResult | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  /*
   * Reset when the dialog opens — on `open`, never on `summary`.
   *
   * Issuing refreshes the screen underneath, which hands this component a new
   * summary object; keyed on that, the effect fired the moment the month was
   * issued and threw away the result it had just put on screen. The office
   * pressed the button and was shown «ما في شي للإصدار» — which was true, and
   * looked exactly like nothing having happened, with the list of who was
   * skipped gone before anybody could read it.
   */
  const open = summary !== null;

  useEffect(() => {
    if (open) {
      setResult(null);
      setError(null);
      setDueDay("");
    }
  }, [open]);

  if (!summary) return null;

  async function issue() {
    setBusy(true);
    setError(null);

    try {
      const res = await api<{ data: IssueResult }>("/billing/issue", {
        method: "POST",
        body: {
          period: summary!.period,
          due_day: dueDay === "" ? null : Number(dueDay),
        },
      });

      setResult(res.data);
      await onDone();
    } catch (e) {
      setError((e as ApiError).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title={`إصدار اشتراك ${summary.period_label}`}>
      {result ? (
        <div className="space-y-3">
          {result.created > 0 ? (
            <Note>
              صدرت <b>{invoiceCount(result.created)}</b> بإجمالي <b>{money(result.total)}</b>.
            </Note>
          ) : (
            <div className="rounded-lg border border-line bg-surface px-3 py-2 text-sm text-ink">
              ما صدرت ولا فاتورة جديدة — كل الأطفال المحدَّد اشتراكهم عندهم فاتورة لهذا
              الشهر.
            </div>
          )}

          {result.skipped.length > 0 && (
            <div>
              <p className="mb-1.5 text-xs font-bold text-muted">
                ما انفوترو ({number(result.skipped.length)})
              </p>
              <ul className="max-h-60 divide-y divide-line-soft overflow-y-auto rounded-lg border border-line">
                {result.skipped.map((row) => (
                  <li
                    key={`${row.student}-${row.why}`}
                    className="flex flex-wrap items-center justify-between gap-2 px-3 py-2"
                  >
                    <span className="text-sm font-semibold text-ink">{row.student}</span>
                    <span className="text-xs text-muted">{row.why}</span>
                  </li>
                ))}
              </ul>
            </div>
          )}

          <Button className="w-full" onClick={onClose}>
            تمّ
          </Button>
        </div>
      ) : (
        <div className="space-y-3">
          {error && <ErrorNote message={error} />}

          <dl className="divide-y divide-line rounded-lg border border-line bg-surface text-sm">
            <Line label="الشهر" value={summary.period_label} />
            <Line label="عدد الأطفال" value={childCount(summary.pending)} />
            <Line label="الإجمالي" value={money(summary.pending_total, { zero: "0 ₪" })} strong />
            {summary.issued > 0 && (
              <Line label="صادر من قبل لهذا الشهر" value={invoiceCount(summary.issued)} />
            )}
          </dl>

          {summary.unpriced > 0 && (
            <div className="rounded-lg border border-warn/30 bg-warn-soft px-3 py-2 text-xs leading-relaxed text-warn">
              في <b>{childCount(summary.unpriced)}</b> بلا اشتراك محدَّد — هدول رح ينتخطّو،
              وأسماءهم بتطلعلك بعد الإصدار. بتقدر تحدّد اشتراكهم أولاً من الشاشة اللي ورا.
            </div>
          )}

          <Field
            label="يوم الاستحقاق"
            hint="فاضي = أول الشهر. حطّ ١٠ إذا الأكاديمية بتمهل الأهل لعاشر الشهر."
          >
            <Input
              type="number"
              min="1"
              max="28"
              value={dueDay}
              onChange={(e) => setDueDay(e.target.value)}
              placeholder="1"
            />
          </Field>

          <p className="rounded-lg bg-surface px-3 py-2 text-xs leading-relaxed text-muted">
            الزر آمن تضغطه مرتين: الطفل اللي عنده فاتورة لهذا الشهر بينتخطّى، وما حدا
            بينفوتر مرتين.
          </p>

          <div className="flex gap-2 pt-1">
            <Button
              className="flex-1"
              disabled={busy || summary.pending === 0}
              onClick={issue}
            >
              {busy
                ? "عم نصدر…"
                : summary.pending === 0
                  ? "ما في شي للإصدار"
                  : `أصدر ${invoiceCount(summary.pending)}`}
            </Button>
            <Button variant="ghost" onClick={onClose} disabled={busy}>
              إلغاء
            </Button>
          </div>
        </div>
      )}
    </Modal>
  );
}

/* -------------------------------------------------------------------------
 * Taking money
 * ---------------------------------------------------------------------- */

/**
 * A payment against one month, and every payment already on it.
 *
 * The two live in the same dialog on purpose. The office is usually here
 * because a mother paid part of the month in cash last week and the rest
 * today, and the question "شو دفعت قبل؟" has to be answerable without closing
 * anything.
 *
 * The amount starts at what is left rather than empty: the overwhelmingly
 * common payment is the whole of what is owed, and a form that makes you
 * retype a figure the screen is already showing is a form that gets it wrong
 * sometimes.
 */
export function PayDialog({
  invoice,
  onClose,
  onDone,
}: {
  invoice: Invoice | null;
  onClose: () => void;
  onDone: () => void | Promise<void>;
}) {
  const [row, setRow] = useState<Invoice | null>(null);
  const [loading, setLoading] = useState(true);
  const [form, setForm] = useState({
    amount: "",
    paid_on: todayISO(),
    method: "cash",
    reference: "",
    note: "",
  });
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);
  const [removing, setRemoving] = useState<number | null>(null);

  const id = invoice?.id;

  /*
   * Re-read the invoice rather than trusting the row that was clicked: the
   * list was fetched before the office walked over to the filing cabinet, and
   * the payments it carries are what this dialog is about.
   */
  const load = useCallback(async () => {
    if (!id) return;

    setLoading(true);

    try {
      const res = await api<{ data: Invoice }>(`/billing/invoices/${id}`);
      setRow(res.data);
      setForm((f) => ({ ...f, amount: res.data.due > 0 ? String(res.data.due) : "" }));
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setLoading(false);
    }
  }, [id]);

  useEffect(() => {
    if (!id) return;
    setError(null);
    setRemoving(null);
    setForm({ amount: "", paid_on: todayISO(), method: "cash", reference: "", note: "" });
    load();
  }, [id, load]);

  if (!invoice) return null;

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api(`/billing/invoices/${invoice!.id}/pay`, {
        method: "POST",
        body: {
          amount: Number(form.amount),
          paid_on: form.paid_on,
          method: form.method,
          reference: form.reference || null,
          note: form.note || null,
        },
      });

      await onDone();
      await load();
      setForm((f) => ({ ...f, reference: "", note: "" }));
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  async function removePayment(paymentId: number) {
    setBusy(true);
    setError(null);

    try {
      await api(`/billing/payments/${paymentId}`, { method: "DELETE" });
      setRemoving(null);
      await onDone();
      await load();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  const current = row ?? invoice;
  const settled = current.due <= 0;

  return (
    <Modal
      open
      onClose={onClose}
      wide
      title={`قبض — ${current.student?.name ?? ""} · ${current.period_label}`}
    >
      {loading ? (
        <Loading rows={3} />
      ) : (
        <div className="space-y-4">
          <dl className="grid grid-cols-2 gap-px overflow-hidden rounded-lg border border-line bg-line text-sm sm:grid-cols-4">
            <Tile label="الفاتورة" value={current.number} mono />
            <Tile label="الإجمالي" value={money(current.total, { zero: "0 ₪" })} />
            <Tile label="المدفوع" value={money(current.paid, { zero: "0 ₪" })} />
            <Tile
              label="المتبقي"
              value={money(current.due, { zero: "0 ₪" })}
              tone={current.due > 0 ? "bad" : "good"}
            />
          </dl>

          {error && <ErrorNote message={error.message} />}

          {/* ---- what has already been paid ---- */}
          {(current.payments?.length ?? 0) > 0 && (
            <div>
              <p className="mb-1.5 text-xs font-bold text-muted">الدفعات المسجّلة</p>
              <ul className="divide-y divide-line-soft rounded-lg border border-line">
                {current.payments!.map((payment) => (
                  <li key={payment.id} className="flex flex-wrap items-center gap-2 px-3 py-2">
                    <span className="min-w-0 flex-1">
                      <span className="block text-sm font-bold text-ink">
                        {money(payment.amount)}
                        <span className="mr-2 text-xs font-normal text-muted">
                          {payment.method_label ?? METHOD_LABELS[payment.method]}
                          {payment.reference && ` · ${payment.reference}`}
                        </span>
                      </span>
                      <span className="block text-xs text-muted">
                        {date(payment.paid_on)} · إيصال{" "}
                        <span className="tabular">{payment.receipt_no}</span>
                        {payment.receiver && ` · ${payment.receiver.name}`}
                      </span>
                    </span>

                    {/*
                      Two taps, inline — not a second dialog on top of this
                      one. Deleting a receipt is rare and reversible only by
                      writing it again, so it asks; but a stacked modal over a
                      modal is how somebody loses the form they were filling.
                    */}
                    {removing === payment.id ? (
                      <span className="flex items-center gap-1">
                        <RowAction tone="danger" onClick={() => removePayment(payment.id)}>
                          {busy ? "لحظة…" : "أكّد الحذف"}
                        </RowAction>
                        <RowAction onClick={() => setRemoving(null)}>تراجع</RowAction>
                      </span>
                    ) : (
                      <RowAction tone="danger" onClick={() => setRemoving(payment.id)}>
                        حذف
                      </RowAction>
                    )}
                  </li>
                ))}
              </ul>
              <p className="mt-1.5 text-xs text-muted">
                حذف الدفعة بيرجّع الفاتورة لحالتها قبلها — استعملها إذا انسجّلت بالغلط، مش
                عشان تصحّح مبلغ.
              </p>
            </div>
          )}

          {/* ---- the new one ---- */}
          {settled ? (
            <Note>هذه الفاتورة مسدّدة بالكامل.</Note>
          ) : (
            <form onSubmit={submit} className="space-y-3 border-t border-line pt-3">
              <div className="grid gap-3 sm:grid-cols-2">
                <Field label="المبلغ *" error={error?.for("amount")}>
                  {/*
                    `step="any"` on every money field here, and it is not a
                    detail: a number input validates against min + n×step, so
                    with a minimum of 0.01 and a step of half a shekel the
                    browser refused 150 — "the two nearest valid values are
                    149.51 and 150.01" — and refused it in English, in a
                    tooltip, on the one action this screen exists for. Money
                    does not come in steps.
                  */}
                  <Input
                    type="number"
                    min="0.01"
                    step="any"
                    required
                    autoFocus
                    value={form.amount}
                    onChange={(e) => set("amount", e.target.value)}
                  />
                </Field>

                <Field label="تاريخ القبض *" error={error?.for("paid_on")}>
                  <Input
                    type="date"
                    required
                    max={todayISO()}
                    value={form.paid_on}
                    onChange={(e) => set("paid_on", e.target.value)}
                  />
                </Field>

                <Field label="الطريقة *">
                  <Select value={form.method} onChange={(e) => set("method", e.target.value)}>
                    {Object.entries(METHOD_LABELS).map(([key, label]) => (
                      <option key={key} value={key}>
                        {label}
                      </option>
                    ))}
                  </Select>
                </Field>

                <Field
                  label={form.method === "cheque" ? "رقم الشيك" : "رقم الحوالة / المرجع"}
                  error={error?.for("reference")}
                >
                  <Input
                    value={form.reference}
                    onChange={(e) => set("reference", e.target.value)}
                    placeholder={form.method === "cash" ? "اختياري" : ""}
                  />
                </Field>
              </div>

              <Field label="ملاحظة">
                <Input value={form.note} onChange={(e) => set("note", e.target.value)} />
              </Field>

              <div className="flex gap-2">
                <Button type="submit" className="flex-1" disabled={busy}>
                  {busy ? "عم نسجّل…" : "سجّل الدفعة"}
                </Button>
                <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
                  إغلاق
                </Button>
              </div>
            </form>
          )}

          {settled && (
            <Button variant="ghost" className="w-full" onClick={onClose}>
              إغلاق
            </Button>
          )}
        </div>
      )}
    </Modal>
  );
}

/* -------------------------------------------------------------------------
 * Changing a charge
 * ---------------------------------------------------------------------- */

/**
 * The figure on one month, and the discount off it.
 *
 * A discount belongs here rather than on the child: it is a decision about one
 * month — a week missed for an operation, a second sibling, a family the
 * academy is carrying — and writing it into the standing fee would quietly
 * discount every month after it too.
 */
export function InvoiceDialog({
  invoice,
  onClose,
  onDone,
}: {
  invoice: Invoice | null;
  onClose: () => void;
  onDone: () => void | Promise<void>;
}) {
  const [form, setForm] = useState({ amount: "", discount: "", due_on: "", note: "" });
  const [error, setError] = useState<ApiError | null>(null);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!invoice) return;
    setError(null);
    setForm({
      amount: String(Number(invoice.amount)),
      discount: Number(invoice.discount) ? String(Number(invoice.discount)) : "",
      due_on: invoice.due_on?.slice(0, 10) ?? "",
      note: invoice.note ?? "",
    });
  }, [invoice]);

  if (!invoice) return null;

  const set = (key: keyof typeof form, value: string) =>
    setForm((f) => ({ ...f, [key]: value }));

  const total = Math.max(0, (Number(form.amount) || 0) - (Number(form.discount) || 0));

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setError(null);

    try {
      await api(`/billing/invoices/${invoice!.id}`, {
        method: "PUT",
        body: {
          amount: Number(form.amount),
          discount: form.discount === "" ? 0 : Number(form.discount),
          due_on: form.due_on,
          note: form.note || null,
        },
      });

      await onDone();
      onClose();
    } catch (e) {
      setError(e as ApiError);
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal open onClose={onClose} title={`فاتورة ${invoice.period_label}`}>
      <form onSubmit={submit} className="space-y-3">
        {error && !Object.keys(error.errors).length && <ErrorNote message={error.message} />}

        <p className="text-xs text-muted">
          {invoice.student?.name} · فاتورة <span className="tabular">{invoice.number}</span>
        </p>

        <div className="grid gap-3 sm:grid-cols-2">
          <Field label="المبلغ *" error={error?.for("amount")}>
            <Input
              type="number"
              min="0"
              step="any"
              required
              value={form.amount}
              onChange={(e) => set("amount", e.target.value)}
            />
          </Field>

          <Field label="خصم" error={error?.for("discount")} hint="لهذا الشهر فقط">
            <Input
              type="number"
              min="0"
              step="any"
              value={form.discount}
              onChange={(e) => set("discount", e.target.value)}
              placeholder="0"
            />
          </Field>

          <Field label="تاريخ الاستحقاق *" error={error?.for("due_on")}>
            <Input
              type="date"
              required
              value={form.due_on}
              onChange={(e) => set("due_on", e.target.value)}
            />
          </Field>

          <Field label="المطلوب بعد الخصم">
            {/* Read-only on purpose: it is arithmetic, and a field somebody
                can type into is a field that will disagree with the other
                two. */}
            <Input readOnly value={money(total, { zero: "0 ₪" })} className="bg-surface" />
          </Field>
        </div>

        <Field label="ملاحظة" error={error?.for("note")}>
          <Textarea
            rows={2}
            value={form.note}
            onChange={(e) => set("note", e.target.value)}
            placeholder="خصم أخ ثاني · غياب أسبوع بعد العملية…"
          />
        </Field>

        {Number(invoice.paid) > 0 && (
          <p className="rounded-lg bg-surface px-3 py-2 text-xs leading-relaxed text-muted">
            على هذه الفاتورة <b>{money(invoice.paid)}</b> مقبوضة. المطلوب بعد الخصم ما بيقدر
            ينزل تحت هذا المبلغ — النظام رح يرفض ويطلب تشيل الدفعات أولاً.
          </p>
        )}

        <div className="flex gap-2 pt-1">
          <Button type="submit" className="flex-1" disabled={busy}>
            {busy ? "عم نحفظ…" : "احفظ"}
          </Button>
          <Button type="button" variant="ghost" onClick={onClose} disabled={busy}>
            إلغاء
          </Button>
        </div>
      </form>
    </Modal>
  );
}

/* -------------------------------------------------------------------------
 * One family's account
 * ---------------------------------------------------------------------- */

/**
 * Every month this child has been charged, and what is left.
 *
 * The same component for the office and for the family — the parent's own
 * screen is this one with `canTakeMoney` off. One list, so a mother and the
 * office are never looking at two different stories about the same months.
 *
 * It is deliberately not a chart. A family asking «شو علينا؟» wants a figure
 * and a list of months, and a figure they can read off a line is a figure they
 * can argue about.
 */
export function AccountCard({
  studentId,
  canTakeMoney,
  reloadKey = 0,
}: {
  studentId: number;
  canTakeMoney: boolean;
  /** Bump to re-read after something outside this card changed the fee. */
  reloadKey?: number;
}) {
  const [account, setAccount] = useState<StudentAccount | null>(null);
  const [loading, setLoading] = useState(true);
  const [failed, setFailed] = useState(false);
  const [paying, setPaying] = useState<Invoice | null>(null);
  const [editing, setEditing] = useState<Invoice | null>(null);
  const [removing, setRemoving] = useState<Invoice | null>(null);
  const [pricing, setPricing] = useState(false);

  const load = useCallback(async () => {
    try {
      const res = await api<{ data: StudentAccount }>(`/billing/students/${studentId}`);
      setAccount(res.data);
      setFailed(false);
    } catch {
      // A specialist gets a 404 here by design, and so does a parent who
      // changed the id. Either way the card simply is not shown.
      setFailed(true);
    } finally {
      setLoading(false);
    }
  }, [studentId]);

  useEffect(() => {
    load();
  }, [load, reloadKey]);

  if (loading) {
    return (
      <Card title="الحساب">
        <Loading rows={2} />
      </Card>
    );
  }

  if (failed || !account) return null;

  const { balance, invoices } = account;

  return (
    <>
      <Card
        title="الحساب"
        hint={
          canTakeMoney
            ? "الاشتراك الشهري وكل شهر انفوتر"
            : "اشتراك الأكاديمية الشهري وشو انسدّد منه"
        }
        action={
          canTakeMoney && (
            <Button variant="ghost" onClick={() => setPricing(true)}>
              {account.student.monthly_fee ? "تعديل الاشتراك" : "+ حدّد الاشتراك"}
            </Button>
          )
        }
      >
        <dl className="grid grid-cols-2 gap-px bg-line text-sm sm:grid-cols-4">
          <Tile
            label="الاشتراك الشهري"
            value={money(account.student.monthly_fee)}
            hint={!account.student.monthly_fee && canTakeMoney ? "ما تحدّد بعد" : undefined}
          />
          <Tile label="إجمالي المستحق" value={money(balance.billed, { zero: "0 ₪" })} />
          <Tile label="المسدّد" value={money(balance.paid, { zero: "0 ₪" })} tone="good" />
          <Tile
            label="المتبقي"
            value={money(balance.due, { zero: "0 ₪" })}
            tone={balance.due > 0 ? "bad" : "good"}
            /* The adjective agrees with the count, so it is part of each
               form rather than a word stuck on the end: «شهرين متأخر» is
               the kind of thing that makes software read as translated. */
            hint={
              balance.overdue > 0
                ? plural(
                    balance.overdue,
                    "شهر متأخر",
                    "شهرين متأخرين",
                    "شهور متأخرة",
                    "شهر متأخر",
                  )
                : undefined
            }
          />
        </dl>

        {invoices.length === 0 ? (
          <Empty
            title="ما في فواتير بعد"
            hint={
              canTakeMoney
                ? account.student.monthly_fee
                  ? "أول فاتورة بتصدر من شاشة المالية — «إصدار الشهر»."
                  : "حدّد الاشتراك الشهري أولاً، بعدها أصدر الشهر من شاشة المالية."
                : "لسه ما صدر أي اشتراك على هذا الملف."
            }
          />
        ) : (
          <ul className="divide-y divide-line-soft">
            {invoices.map((row) => (
              <li key={row.id} className="flex flex-wrap items-center gap-3 px-4 py-3">
                <div className="min-w-0 flex-1">
                  <p className="text-sm font-bold text-ink">{row.period_label}</p>
                  <p className="mt-0.5 text-xs text-muted">
                    استحقاق {date(row.due_on)} · <span className="tabular">{row.number}</span>
                    {row.note && ` · ${row.note}`}
                  </p>
                </div>

                <div className="text-left">
                  <p className="text-sm font-bold text-ink">
                    {money(row.total, { zero: "0 ₪" })}
                  </p>
                  {row.due > 0 ? (
                    <p className="text-xs font-semibold text-bad">
                      متبقي {money(row.due)}
                    </p>
                  ) : (
                    <p className="text-xs text-muted">مسدّدة</p>
                  )}
                </div>

                <Badge className={INVOICE_TONES[row.status]}>
                  {row.status_label ?? INVOICE_LABELS[row.status]}
                </Badge>

                {canTakeMoney && (
                  <span className="flex gap-1">
                    {row.due > 0 && (
                      <RowAction tone="brand" onClick={() => setPaying(row)}>
                        قبض
                      </RowAction>
                    )}
                    {row.due <= 0 && Number(row.paid) > 0 && (
                      <RowAction onClick={() => setPaying(row)}>الإيصالات</RowAction>
                    )}
                    <RowAction onClick={() => setEditing(row)}>تعديل</RowAction>
                    <RowAction tone="danger" onClick={() => setRemoving(row)}>
                      حذف
                    </RowAction>
                  </span>
                )}
              </li>
            ))}
          </ul>
        )}

        {!canTakeMoney && balance.due > 0 && (
          <p className="border-t border-line px-4 py-3 text-xs leading-relaxed text-muted">
            لأي سؤال عن الحساب أو ترتيب الدفع، تواصلوا مع إدارة الأكاديمية.
          </p>
        )}
      </Card>

      <FeeDialog
        student={pricing ? account.student : null}
        onClose={() => setPricing(false)}
        onDone={load}
      />

      <PayDialog invoice={paying} onClose={() => setPaying(null)} onDone={load} />

      <InvoiceDialog invoice={editing} onClose={() => setEditing(null)} onDone={load} />

      <Confirm
        open={removing !== null}
        onClose={() => setRemoving(null)}
        onConfirm={async () => {
          await api(`/billing/invoices/${removing!.id}`, { method: "DELETE" });
          await load();
        }}
        title="حذف الفاتورة"
        body={
          <>
            حذف فاتورة <b>{removing?.period_label}</b> بقيمة{" "}
            <b>{money(removing?.total, { zero: "0 ₪" })}</b>. إذا عليها دفعات مقبوضة النظام
            رح يرفض — شيل الدفعات أولاً، عشان إيصال انعطى للأهل ما ينمسح من تحتهم.
          </>
        }
      />
    </>
  );
}

/* -------------------------------------------------------------------------
 * Pieces
 * ---------------------------------------------------------------------- */

/** One figure in a strip of them. */
export function Tile({
  label,
  value,
  hint,
  tone = "plain",
  mono = false,
}: {
  label: string;
  value: string;
  hint?: string;
  tone?: "plain" | "good" | "bad";
  mono?: boolean;
}) {
  const tones = { plain: "text-ink", good: "text-good", bad: "text-bad" } as const;

  return (
    <div className="bg-panel px-4 py-2.5">
      <dt className="text-xs font-semibold text-muted">{label}</dt>
      <dd className={`mt-0.5 font-bold ${mono ? "tabular text-sm" : "text-base"} ${tones[tone]}`}>
        {value}
      </dd>
      {hint && <p className="text-[11px] text-muted">{hint}</p>}
    </div>
  );
}

/** One label and one figure, in a stack of them inside a dialog. */

function Line({
  label,
  value,
  strong = false,
}: {
  label: string;
  value: string;
  strong?: boolean;
}) {
  return (
    <div className="flex items-center justify-between gap-3 px-3 py-2">
      <dt className="text-xs text-muted">{label}</dt>
      <dd className={`text-sm ${strong ? "font-extrabold text-ink" : "font-semibold text-ink"}`}>
        {value}
      </dd>
    </div>
  );
}
