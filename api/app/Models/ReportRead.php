<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ReportRead extends Model
{
    protected $fillable = ['therapy_session_id', 'user_id', 'read_at'];

    // The row is the fact; there is nothing to update on it afterwards.
    public $timestamps = false;

    protected function casts(): array
    {
        return ['read_at' => 'datetime'];
    }

    public function session(): BelongsTo
    {
        return $this->belongsTo(TherapySession::class, 'therapy_session_id');
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }
}
