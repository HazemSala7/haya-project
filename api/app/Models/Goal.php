<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class Goal extends Model
{
    protected $fillable = [
        'student_id', 'enrollment_id', 'title', 'description', 'criteria',
        'baseline', 'target', 'status', 'started_at', 'achieved_at', 'sort_order',
    ];

    protected function casts(): array
    {
        return [
            'baseline' => 'integer',
            'target' => 'integer',
            'sort_order' => 'integer',
            'started_at' => 'date',
            'achieved_at' => 'date',
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

    /**
     * Oldest first, by the day the child was measured — never by insert time.
     * See the `measured_at` migration for why that distinction is the whole
     * difference between a curve and a scatter of dates.
     */
    public function ratings(): HasMany
    {
        return $this->hasMany(GoalRating::class)->orderBy('measured_at');
    }

    public function scopeActive(Builder $query): Builder
    {
        return $query->where('status', 'active');
    }

    public function scopeOrdered(Builder $query): Builder
    {
        return $query->orderBy('sort_order')->orderBy('id');
    }

    /**
     * The last score anyone gave this goal, and the distance from where he
     * started.
     *
     * Both come back together because neither means anything alone: a 3 is
     * excellent from a baseline of 0 and a regression from a baseline of 4.
     *
     * @return array{latest: int|null, delta: int|null, ratings: int}
     */
    public function trend(): array
    {
        $ratings = $this->relationLoaded('ratings')
            ? $this->ratings
            : $this->ratings()->get();

        // `level` is cast to a PromptLevel, so it has to come back to an int
        // before it can be compared with the baseline — which is a plain
        // column. Subtracting the enum itself is a TypeError, not a silent
        // wrong answer, which is the one mercy in it.
        $latest = $ratings->last()?->level?->value;

        return [
            'latest' => $latest,
            'delta' => $latest === null ? null : $latest - $this->baseline,
            'ratings' => $ratings->count(),
        ];
    }
}
