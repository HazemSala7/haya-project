<?php

namespace App\Services;

use App\Models\Invoice;
use App\Models\Payment;
use App\Models\Student;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Issuing the month, and taking money against it.
 *
 * The academy charges a monthly subscription that falls due on the first.
 * Everything here exists to make that one sentence safe to act on.
 *
 * ---------------------------------------------------------------------------
 * ISSUING IS A BUTTON, NOT A CLOCK.
 *
 * There is no scheduler on this host and no queue worker — the same constraint
 * the cheque reminder lives under. A monthly charge that depended on cron
 * would be a charge that silently never happened, and nobody notices a bill
 * that was not raised until the family has had three free months.
 *
 * So the administration issues the month, and the screen tells them when it
 * has not been issued yet. Pressing it twice is safe: a child already charged
 * for that month is skipped and named, and the database refuses a second row
 * anyway through the unique index on (student_id, period). Two guards, because
 * this is the one action here that creates a debt against a family.
 *
 * ---------------------------------------------------------------------------
 * A CHILD WITH NO AGREED FEE IS NOT A CHILD WHO OWES ZERO.
 *
 * `monthly_fee` is null until the administration sets it. Such a child is
 * skipped and reported rather than billed nothing: an invoice for zero reads
 * as "settled" on every screen, and a family that was never priced would
 * disappear from the one list that would have caught it.
 */
final class Billing
{
    /**
     * Raise the subscription for one month across every active child.
     *
     * @param  Carbon  $month  any day inside it; the first is used
     * @return array{period: string, created: int, total: float, skipped: list<array{student: string, why: string}>}
     */
    public static function issueMonth(Carbon $month, ?User $by, ?int $dueDay = null): array
    {
        $period = $month->copy()->startOfMonth();

        // The academy may give the family until the tenth. Clamped to the
        // month so a due day of 31 does not roll February into March.
        $due = $dueDay
            ? $period->copy()->setDay(min($dueDay, $period->daysInMonth))
            : $period->copy();

        $students = Student::query()
            ->where('status', 'active')
            ->orderBy('name')
            ->get();

        $created = 0;
        $total = 0.0;
        $skipped = [];

        DB::transaction(function () use ($students, $period, $due, $by, &$created, &$total, &$skipped) {
            foreach ($students as $student) {
                $fee = $student->monthly_fee === null ? null : round((float) $student->monthly_fee, 2);

                if ($fee === null || $fee <= 0) {
                    $skipped[] = ['student' => $student->name, 'why' => 'بلا اشتراك محدَّد'];

                    continue;
                }

                $existing = Invoice::withTrashed()
                    ->where('student_id', $student->id)
                    ->whereDate('period', $period)
                    ->first();

                if ($existing && ! $existing->trashed()) {
                    $skipped[] = ['student' => $student->name, 'why' => 'مفوتر مسبقاً — '.$existing->number];

                    continue;
                }

                /*
                 * A month the office deleted, and is now issuing again.
                 *
                 * Money is archived rather than destroyed, so the row is still
                 * there — and the unique index on (student_id, period) is
                 * still holding its month, which means a fresh insert would
                 * fail. Skipping it instead would be worse than failing: the
                 * screen would say «مفوتر مسبقاً» and name an invoice the
                 * office cannot see anywhere, and that month could never be
                 * charged again.
                 *
                 * So it comes back, repriced at today's fee. An invoice with
                 * payments on it cannot have been deleted in the first place
                 * — see BillingController::destroy — so there is nothing
                 * received to reconcile here.
                 */
                if ($existing) {
                    $existing->restore();

                    $existing->fill([
                        'due_on' => $due->toDateString(),
                        'amount' => $fee,
                        'discount' => 0,
                        'created_by' => $by?->id,
                    ])->save();

                    $existing->recalculate();

                    $created++;
                    $total = round($total + $fee, 2);

                    continue;
                }

                $invoice = Invoice::create([
                    'number' => Invoice::nextNumber($period),
                    'student_id' => $student->id,
                    'period' => $period->toDateString(),
                    'due_on' => $due->toDateString(),
                    'amount' => $fee,
                    'discount' => 0,
                    'created_by' => $by?->id,
                ]);

                $invoice->recalculate();

                $created++;
                $total = round($total + $fee, 2);
            }
        });

        return [
            'period' => $period->toDateString(),
            'created' => $created,
            'total' => $total,
            'skipped' => $skipped,
        ];
    }

    /** Take money against one invoice. */
    public static function receive(Invoice $invoice, array $data, ?User $by): Payment
    {
        $paidOn = Carbon::parse($data['paid_on']);

        $payment = Payment::create([
            'receipt_no' => Payment::nextReceiptNo($paidOn),
            'invoice_id' => $invoice->id,
            'amount' => round((float) $data['amount'], 2),
            'paid_on' => $paidOn->toDateString(),
            'method' => $data['method'] ?? 'cash',
            'reference' => $data['reference'] ?? null,
            'note' => $data['note'] ?? null,
            'received_by' => $by?->id,
        ]);

        $invoice->recalculate();

        return $payment;
    }

    /**
     * What one family owes, across every month.
     *
     * @return array{billed: float, paid: float, due: float, months: int, overdue: int}
     */
    public static function balanceFor(int $studentId): array
    {
        $invoices = Invoice::where('student_id', $studentId)->get();

        $billed = round((float) $invoices->sum('total'), 2);
        $paid = round((float) $invoices->sum('paid'), 2);

        return [
            'billed' => $billed,
            'paid' => $paid,
            'due' => round($billed - $paid, 2),
            'months' => $invoices->count(),
            'overdue' => $invoices->where('status', 'overdue')->count(),
        ];
    }
}
