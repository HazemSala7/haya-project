<?php

namespace App\Models;

use App\Enums\Specialty;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Enrollment extends Model
{
    protected $fillable = [
        'student_id', 'specialty', 'specialist_id',
        'sessions_per_week', 'session_minutes',
        'started_at', 'ended_at', 'status', 'plan_summary',
    ];

    protected function casts(): array
    {
        return [
            'specialty' => Specialty::class,
            'started_at' => 'date',
            'ended_at' => 'date',
        ];
    }

    protected $appends = ['specialty_label'];

    public function student(): BelongsTo
    {
        return $this->belongsTo(Student::class);
    }

    public function specialist(): BelongsTo
    {
        return $this->belongsTo(User::class, 'specialist_id');
    }

    public function goals(): HasMany
    {
        return $this->hasMany(Goal::class);
    }

    public function sessions(): HasMany
    {
        return $this->hasMany(TherapySession::class);
    }

    public function scopeActive(Builder $query): Builder
    {
        return $query->where('status', 'active');
    }

    /** The queue the office empties: live programmes with nobody on them. */
    public function scopeUnassigned(Builder $query): Builder
    {
        return $query->active()->whereNull('specialist_id');
    }

    public function getSpecialtyLabelAttribute(): string
    {
        return $this->specialty?->fullLabel() ?? '—';
    }
}
