<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * التقرير الدوري — the quarter, not the day.
 */
class ProgressReport extends Model
{
    protected $fillable = [
        'student_id', 'enrollment_id', 'author_id',
        'period_start', 'period_end',
        'summary', 'achieved', 'recommendations', 'home_program',
        'status', 'published_at',
    ];

    protected function casts(): array
    {
        return [
            'period_start' => 'date',
            'period_end' => 'date',
            'published_at' => 'datetime',
        ];
    }

    public function student(): BelongsTo
    {
        return $this->belongsTo(Student::class);
    }

    public function enrollment(): BelongsTo
    {
        return $this->belongsTo(Enrollment::class);
    }

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }

    /** Same rule as a session report: the family sees what was sent. */
    public function scopeVisibleTo(Builder $query, User $user): Builder
    {
        if ($user->role->isStaff()) {
            return $query;
        }

        return $query
            ->where('status', 'published')
            ->whereHas('student.guardians', fn (Builder $q) => $q->where('users.id', $user->id));
    }

    public function isPublished(): bool
    {
        return $this->status === 'published';
    }
}
