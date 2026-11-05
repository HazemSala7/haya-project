<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/**
 * Money handed over against one month's subscription.
 *
 * It carries a receipt number because the family is given one, and the number
 * on the paper has to be findable in here — that is the whole reason this
 * table is not just a column on the invoice.
 */
class Payment extends Model
{
    protected $fillable = [
        'receipt_no', 'invoice_id', 'amount', 'paid_on',
        'method', 'reference', 'note', 'received_by',
        // من أين جاء هذا الصفّ: `zaid` ومفتاحه هناك. بدونهما في
        // `$fillable` لا يستطيع المُستورِد كتابتهما، فتصير كل تشغيلةٍ
        // طبقةً جديدة من نفس الأطفال.
        'source', 'source_id',
    ];

    protected function casts(): array
    {
        return [
            'paid_on' => 'date',
            'amount' => 'decimal:2',
        ];
    }

    protected $appends = ['method_label'];

    public function invoice(): BelongsTo
    {
        return $this->belongsTo(Invoice::class);
    }

    public function receiver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'received_by');
    }

    public function getMethodLabelAttribute(): string
    {
        return match ($this->method) {
            'transfer' => 'حوالة بنكية',
            'cheque' => 'شيك',
            default => 'نقداً',
        };
    }

    /** RC-2026-0042, sequential within the year the money arrived. */
    public static function nextReceiptNo(Carbon $date): string
    {
        $prefix = 'RC-'.$date->format('Y').'-';

        $last = static::where('receipt_no', 'like', $prefix.'%')
            ->orderByDesc('receipt_no')
            ->value('receipt_no');

        $sequence = $last ? ((int) substr($last, strlen($prefix))) + 1 : 1;

        return $prefix.str_pad((string) $sequence, 4, '0', STR_PAD_LEFT);
    }
}
