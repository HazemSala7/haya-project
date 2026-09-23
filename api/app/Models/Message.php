<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Message extends Model
{
    protected $fillable = [
        'student_id', 'sender_id', 'therapy_session_id', 'body', 'read_at',
    ];

    protected function casts(): array
    {
        return ['read_at' => 'datetime'];
    }

    public function student(): BelongsTo
    {
        return $this->belongsTo(Student::class);
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_id');
    }

    public function session(): BelongsTo
    {
        return $this->belongsTo(TherapySession::class, 'therapy_session_id');
    }

    public function scopeUnread(Builder $query): Builder
    {
        return $query->whereNull('read_at');
    }

    /**
     * Messages this person did not write.
     *
     * "Unread" is only meaningful from the other side of the conversation, and
     * a thread is shared by the whole family and the whole care team — so it
     * is defined by who sent it, not by a per-recipient row.
     */
    public function scopeNotFrom(Builder $query, User $user): Builder
    {
        return $query->where('sender_id', '!=', $user->id);
    }
}
