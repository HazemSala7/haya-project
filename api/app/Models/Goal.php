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
     * `progress` is the same distance as a percentage of the distance the goal
     * set out to cover: from a baseline of 1 to a target of 4, a latest of 3
     * is two thirds of the way. It is what the academy reports to a family and
     * what a specialist is asked about in a review, and deriving it here means
     * the screen, the printed report and the app cannot each round it their
     * own way.
     *
     * Clamped to 0–100 on purpose. A child scoring below where he started is
     * at 0% of the goal, not at a negative percentage — and one who passed the
     * target has finished it, not exceeded it by a number nobody can act on.
     *
     * @return array{latest: int|null, delta: int|null, ratings: int, progress: int|null}
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

        // A goal whose target equals its baseline has no distance to cover, so
        // there is no fraction of it to be at — null rather than a division
        // by zero dressed up as 0% or 100%.
        return [
            'latest' => $latest,
            'delta' => $latest === null ? null : $latest - $this->baseline,
            'ratings' => $ratings->count(),
            'progress' => static::progressFrom($latest, $this->baseline, $this->target),
        ];
    }

    /**
     * How far along the goal is, as a percentage of the distance it set out to
     * cover.
     *
     * A static so the curve screen computes it from the same line as the list
     * does — see App\Services\Progress::goalCurve. Two call sites rounding a
     * percentage their own way is how the file says 67% and the printed report
     * says 66%.
     */
    public static function progressFrom(?int $latest, int $baseline, int $target): ?int
    {
        // A goal whose target equals its baseline has no distance to cover, so
        // there is no fraction of it to be at — null rather than a division by
        // zero dressed up as 0% or 100%.
        $span = $target - $baseline;

        if ($latest === null || $span <= 0) {
            return null;
        }

        return (int) round(max(0, min(1, ($latest - $baseline) / $span)) * 100);
    }
}
