<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Models\Invoice;
use App\Models\Payment;
use App\Models\Student;
use App\Services\Billing;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;

/**
 * The academy's money.
 *
 * A monthly subscription per child, issued by the administration and due on
 * the first. The specialists never see any of this — a therapist deciding
 * whether a family has paid is a therapist with a reason to treat two children
 * differently, so the whole module is behind `role:admin` and the parent sees
 * only their own child's account.
 */
class BillingController extends Controller
{
    /** The month's charges, newest first. */
    public function index(Request $request): JsonResponse
    {
        Invoice::sweepOverdue();

        $invoices = Invoice::query()
            ->with('student:id,name,file_number')
            ->when(
                $request->filled('student_id'),
                fn ($query) => $query->where('student_id', $request->integer('student_id'))
            )
            ->when(
                $request->filled('period'),
                fn ($query) => $query->whereDate('period', $request->string('period')->toString())
            )
            ->when(
                $request->filled('status'),
                fn ($query) => $query->where('status', $request->string('status')->toString())
            )
            ->when($request->boolean('outstanding'), fn ($query) => $query->outstanding())
            ->when($request->filled('q'), function ($query) use ($request) {
                $term = $request->string('q')->toString();
                $query->where(fn ($q) => $q
                    ->where('number', 'like', "%{$term}%")
                    ->orWhereHas('student', fn ($s) => $s->where('name', 'like', "%{$term}%")));
            })
            ->orderByDesc('period')
            ->orderBy('id')
            ->paginate($this->perPage($request));

        /*
         * Through the shared helper, like every other list here.
         *
         * Returning the paginator itself puts its counts at the top level
         * instead of under `meta`, and the dashboard's list hook reads
         * `meta.current_page` — so the screen threw while unpacking a
         * perfectly good response and showed «ما في فواتير» over a month that
         * had just been issued.
         */
        return $this->paginated($invoices);
    }

    /**
     * What the administration needs before pressing the button.
     *
     * Whether this month has been issued, how many children are priced, and
     * what it will come to. A screen that offers «إصدار الشهر» without saying
     * how many it will charge is asking for a click nobody can check.
     */
    public function summary(Request $request): JsonResponse
    {
        // «متأخرة» arrives by the calendar, and there is no scheduler here to
        // notice — see Invoice::sweepOverdue.
        Invoice::sweepOverdue();

        $month = $request->filled('period')
            ? Carbon::parse($request->string('period')->toString())->startOfMonth()
            : Carbon::today()->startOfMonth();

        $active = Student::where('status', 'active')->orderBy('name')->get(['id', 'name', 'monthly_fee']);
        $priced = $active->filter(fn ($student) => $student->monthly_fee > 0);

        $issued = Invoice::whereDate('period', $month)->get();

        /*
         * Who the button would actually charge — not "the priced children
         * minus the invoices already there".
         *
         * That subtraction was wrong in both directions: a child priced after
         * the month was issued made the figure too small, and a child whose
         * fee was cleared afterwards made it negative. Asking which priced
         * children have no row for this month is the question the button
         * answers, so it is the question asked here.
         *
         * A deleted invoice counts as not billed, because `issueMonth` brings
         * it back rather than skipping it — so this figure and that button
         * agree on who is owed a charge.
         */
        $billed = $issued->pluck('student_id');
        $pending = $priced->whereNotIn('id', $billed->all());

        $outstanding = Invoice::outstanding()->get();

        return response()->json([
            'data' => [
                'period' => $month->toDateString(),
                'period_label' => Invoice::monthName((int) $month->format('n')).' '.$month->format('Y'),
                'issued' => $issued->count(),
                'issued_total' => round((float) $issued->sum('total'), 2),
                // What pressing the button would do, as it stands today.
                'pending' => $pending->count(),
                'pending_total' => round((float) $pending->sum('monthly_fee'), 2),
                'unpriced' => $active->count() - $priced->count(),
                /*
                 * Named, not counted.
                 *
                 * "٣ أطفال بلا اشتراك" is a number nobody can act on; these
                 * are the children the monthly run will skip, so the screen
                 * can put a «حدّد الاشتراك» beside each one and the office can
                 * clear the list before pressing the button.
                 */
                'unpriced_students' => $active
                    ->filter(fn ($student) => ! ($student->monthly_fee > 0))
                    ->map(fn ($student) => ['id' => $student->id, 'name' => $student->name])
                    ->values(),
                'outstanding_total' => round((float) $outstanding->sum('total') - (float) $outstanding->sum('paid'), 2),
                'outstanding_count' => $outstanding->count(),
            ],
        ]);
    }

    /**
     * What this family pays a month.
     *
     * Its own endpoint rather than a field on the student form, for two
     * reasons. The office prices children from the billing screen, where the
     * only thing in hand is a name and an id — and a PUT to /students would
     * have to send the whole file back to pass its validation, so a fee
     * change would fail on an unrelated required field and could overwrite a
     * diagnosis somebody edited in the meantime.
     *
     * `present` and not `required`: clearing the fee is a real instruction —
     * it takes the child out of the monthly run — and `required` would reject
     * the null that says so.
     */
    public function fee(Request $request, Student $student): JsonResponse
    {
        $data = $request->validate([
            'monthly_fee' => ['present', 'nullable', 'numeric', 'min:0', 'max:100000'],
        ]);

        // Zero and null mean the same thing to the monthly run, so they are
        // stored the same way rather than left as two states that read alike
        // on screen and sort differently in a list.
        $fee = $data['monthly_fee'];

        $student->update([
            'monthly_fee' => $fee === null || (float) $fee <= 0 ? null : round((float) $fee, 2),
        ]);

        return response()->json([
            'data' => $student->fresh()->only(['id', 'name', 'file_number', 'monthly_fee']),
        ]);
    }

    /**
     * Raise the subscription for a month.
     *
     * Safe to press twice: a child already charged for that month is skipped
     * and named — see App\Services\Billing.
     */
    public function issue(Request $request): JsonResponse
    {
        $data = $request->validate([
            'period' => ['required', 'date'],
            // The academy may give the family until the tenth.
            'due_day' => ['nullable', 'integer', 'min:1', 'max:28'],
        ]);

        $result = Billing::issueMonth(
            Carbon::parse($data['period']),
            $request->user(),
            $data['due_day'] ?? null,
        );

        return response()->json(['data' => $result], 201);
    }

    public function show(Invoice $invoice): JsonResponse
    {
        $invoice->load(['student:id,name,file_number', 'payments.receiver:id,name']);

        return response()->json(['data' => $invoice]);
    }

    /** Change the figure, or forgive part of it. */
    public function update(Request $request, Invoice $invoice): JsonResponse
    {
        $data = $request->validate([
            'amount' => ['required', 'numeric', 'min:0', 'max:100000'],
            'discount' => ['nullable', 'numeric', 'min:0', 'max:100000'],
            'due_on' => ['required', 'date'],
            'note' => ['nullable', 'string', 'max:255'],
        ]);

        $total = round((float) $data['amount'] - (float) ($data['discount'] ?? 0), 2);

        if ($total < round((float) $invoice->paid, 2) - 0.001) {
            return response()->json([
                'message' => 'الإجمالي الجديد أقل مما سُدّد على الفاتورة. ألغِ الدفعات أولاً.',
            ], 422);
        }

        $invoice->fill([
            'amount' => $data['amount'],
            'discount' => $data['discount'] ?? 0,
            'due_on' => $data['due_on'],
            'note' => $data['note'] ?? null,
        ])->save();

        $invoice->recalculate();

        return response()->json(['data' => $invoice->fresh()->load('payments')]);
    }

    public function destroy(Invoice $invoice): JsonResponse
    {
        if ($invoice->payments()->exists()) {
            return response()->json([
                'message' => 'على هذه الفاتورة دفعات مسجّلة. احذف الدفعات أولاً.',
            ], 422);
        }

        $invoice->delete();

        return response()->json(['message' => 'حُذفت الفاتورة.']);
    }

    /* ---------------------------------------------------------------- money in */

    public function pay(Request $request, Invoice $invoice): JsonResponse
    {
        $data = $request->validate([
            'amount' => ['required', 'numeric', 'min:0.01', 'max:100000'],
            /*
             * Money that has not arrived yet is not a receipt.
             *
             * Against the academy's own calendar day, not the server's. The
             * application runs in UTC, so between midnight and two in the
             * morning in Palestine `today` is still yesterday — and a receipt
             * written at half past midnight would be refused for being dated
             * in the future.
             */
            'paid_on' => ['required', 'date', 'before_or_equal:'.Carbon::now('Asia/Hebron')->toDateString()],
            'method' => ['required', 'in:cash,transfer,cheque'],
            'reference' => ['nullable', 'string', 'max:100'],
            'note' => ['nullable', 'string', 'max:255'],
        ]);

        if (round((float) $data['amount'], 2) > $invoice->due + 0.001) {
            return response()->json([
                'message' => 'المبلغ أكبر من المتبقي على الفاتورة ('.number_format($invoice->due, 2).').',
                'errors' => ['amount' => ['أكبر من المتبقي.']],
            ], 422);
        }

        $payment = Billing::receive($invoice, $data, $request->user());

        return response()->json([
            'data' => $payment->load('receiver:id,name'),
            'invoice' => $invoice->fresh(),
        ], 201);
    }

    public function removePayment(Payment $payment): JsonResponse
    {
        $invoice = $payment->invoice;

        $payment->delete();
        $invoice?->recalculate();

        return response()->json(['message' => 'حُذفت الدفعة.', 'invoice' => $invoice?->fresh()]);
    }

    /* -------------------------------------------------------- one family's account */

    /**
     * A child's account: every month, and what is left.
     *
     * Reachable by the parent for their own child — the one part of this
     * module they see — and by the office. `readableBy` is the same gate every
     * other student endpoint uses, and it answers 404 rather than 403 so that
     * changing the id in the URL cannot be used to find out which children
     * exist.
     *
     * The specialist check is on top of it, not instead of it: `readableBy`
     * passes any member of staff, so without this line the one route in this
     * module that is not behind `role:admin` would hand a therapist every
     * family's balance — which is precisely what the rest of the module is
     * arranged to prevent.
     */
    public function student(Request $request, Student $student): JsonResponse
    {
        $user = $request->user();

        abort_if($user->role === Role::Specialist, 404, 'العنصر المطلوب غير موجود.');
        abort_unless($student->readableBy($user), 404, 'العنصر المطلوب غير موجود.');

        Invoice::sweepOverdue();

        return response()->json([
            'data' => [
                'student' => $student->only(['id', 'name', 'file_number', 'monthly_fee']),
                'balance' => Billing::balanceFor($student->id),
                'invoices' => Invoice::where('student_id', $student->id)
                    ->with('payments')
                    ->orderByDesc('period')
                    ->get(),
            ],
        ]);
    }
}
