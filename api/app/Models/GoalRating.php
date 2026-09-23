<?php

namespace App\Models;

use App\Enums\PromptLevel;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class GoalRating extends Model
{
    protected $fillable = [
        'therapy_session_id', 'goal_id', 'measured_at', 'level', 'trials', 'successes', 'note',
    ];

    protected function casts(): array
    {
        return [
            'level' => PromptLevel::class,
            'measured_at' => 'datetime',
            'trials' => 'integer',
            'successes' => 'integer',
        ];
    }

    protected $appends = ['level_label'];

    public function session(): BelongsTo
    {
        return $this->belongsTo(TherapySession::class, 'therapy_session_id');
    }

    public function goal(): BelongsTo
    {
        return $this->belongsTo(Goal::class);
    }

    public function getLevelLabelAttribute(): string
    {
        return $this->level?->label() ?? '—';
    }
}
