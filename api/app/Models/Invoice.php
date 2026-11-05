<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;
use Illuminate\Support\Carbon;

/**
 * One month's subscription, charged to one child.
 *
 * `paid`, `total` and `status` are derived from the payments and kept in
 * columns so that listing a hundred families stays one query. This model is
 * the only place that writes them — see `recalculate()`.
 */
class Invoice extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'number', 'student_id', 'period', 'due_on',
        'amount', 'discount', 'total', 'paid', 'status', 'note', 'created_by',
        // من أين جاء هذا الصفّ: `zaid` ومفتاحه هناك. بدونهما في
        // `$fillable` لا يستطيع المُستورِد كتابتهما، فتصير كل تشغيلةٍ
        // طبقةً جديدة من نفس الأطفال.
        'source', 'source_id',
    ];

    protected function casts(): array
    {
        return [
            'period' => 'date',
            'due_on' => 'date',
            'amount' => 'decimal:2',
            'discount' => 'decimal:2',
            'total' => 'decimal:2',
            'paid' => 'decimal:2',
        ];
    }

    protected $appends = ['due', 'period_label', 'status_label'];

    public function student(): BelongsTo
    {
        return $this->belongsTo(Student::class);
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class);
    }

    /** What is still owed. Never negative — overpayment reads as nothing due. */
    public function getDueAttribute(): float
    {
        return max(0, round((float) $this->total - (float) $this->paid, 2));
    }

    /** «تشرين الأول 2026» — the month this charge is for. */
    public function getPeriodLabelAttribute(): string
    {
        return self::monthName((int) $this->period->format('n')).' '.$this->period->format('Y');
    }

    public function getStatusLabelAttribute(): string
    {
        return match ($this->status) {
            'paid' => 'مسدّدة',
            'partial' => 'مسدّدة جزئياً',
            'overdue' => 'متأخرة',
            default => 'غير مسدّدة',
        };
    }

    /**
     * Recompute the stored totals from the payments.
     *
     * Called after anything touches a payment or the discount. Status is
     * derived here and nowhere else, so «متأخرة» cannot mean one thing on the
     * list and another on the child's file.
     */
    public function recalculate(bool $save = true): static
    {
        $paid = round((float) $this->payments()->sum('amount'), 2);
        $total = round(max(0, (float) $this->amount - (float) $this->discount), 2);

        $this->total = $total;
        $this->paid = $paid;

        $this->status = match (true) {
            // Tolerance covers the rounding drift of split payments.
            $total > 0 && $paid >= $total - 0.001 => 'paid',
            $paid > 0 => 'partial',
            /*
             * Late is a whole day late.
             *
             * `isPast()` was wrong by a day in both directions: `due_on` is a
             * date cast, so it is midnight, and an invoice due today read as
             * overdue from one minute past midnight — every invoice issued on
             * the first of the month was born «متأخرة». Comparing calendar
             * days, in the academy's own timezone rather than the server's
             * UTC, is the thing the office means by late.
             */
            $this->due_on && $this->due_on->toDateString() < Carbon::now('Asia/Hebron')->toDateString() => 'overdue',
            default => 'unpaid',
        };

        if ($save) {
            $this->saveQuietly();
        }

        return $this;
    }

    /** Anything still owed, whichever unpaid state it is in. */
    public function scopeOutstanding(Builder $query): Builder
    {
        return $query->whereIn('status', ['unpaid', 'partial', 'overdue']);
    }

    /**
     * Age the invoices nobody has touched.
     *
     * `status` is derived and stored, and «متأخرة» is the one state that
     * arrives by the calendar rather than by somebody doing something. With no
     * scheduler on this host — the same constraint that makes issuing a button
     * — an invoice would sit at «ما تسدّدت» forever and the overdue count the
     * office works from would be permanently zero.
     *
     * So the money screens sweep on the way in. It is one indexed UPDATE that
     * touches only rows that are already wrong, and it applies exactly the
     * rule `recalculate()` applies: nothing paid, and the due date is behind
     * us. A partly paid invoice stays «مسدّدة جزئياً» there and here — two
     * rules for one column is how a list and a file end up disagreeing.
     *
     * Against the academy's calendar day, not the server's: the app runs in
     * UTC, and an invoice due today must not be called late for the two hours
     * either side of midnight in Palestine.
     */
    public static function sweepOverdue(): int
    {
        return static::query()
            ->where('status', 'unpaid')
            ->whereDate('due_on', '<', Carbon::now('Asia/Hebron')->toDateString())
            ->update(['status' => 'overdue']);
    }

    /**
     * Sequential within the year: INV-2026-0042.
     *
     * Counted off the highest existing number rather than a sequence table —
     * one academy, a few hundred a year, and nothing to contend on.
     */
    public static function nextNumber(Carbon $date): string
    {
        $prefix = 'INV-'.$date->format('Y').'-';

        $last = static::withTrashed()
            ->where('number', 'like', $prefix.'%')
            ->orderByDesc('number')
            ->value('number');

        $sequence = $last ? ((int) substr($last, strlen($prefix))) + 1 : 1;

        return $prefix.str_pad((string) $sequence, 4, '0', STR_PAD_LEFT);
    }

    /** Arabic month names, as the Levant writes them. */
    public static function monthName(int $month): string
    {
        return [
            1 => 'كانون الثاني', 2 => 'شباط', 3 => 'آذار', 4 => 'نيسان',
            5 => 'أيار', 6 => 'حزيران', 7 => 'تموز', 8 => 'آب',
            9 => 'أيلول', 10 => 'تشرين الأول', 11 => 'تشرين الثاني', 12 => 'كانون الأول',
        ][$month] ?? (string) $month;
    }
}
