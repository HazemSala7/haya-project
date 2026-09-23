<?php

namespace App\Models;

use App\Enums\Specialty;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

/**
 * الجلسة — the appointment and the report that came out of it.
 */
class TherapySession extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'number', 'student_id', 'enrollment_id', 'specialist_id', 'specialty',
        'scheduled_at', 'duration_minutes', 'status', 'absence_reason',
        'mood', 'activities', 'progress', 'difficulties', 'home_plan',
        'private_notes', 'report_status', 'published_at',
    ];

    /**
     * Hidden by default — the single most important line in this file.
     *
     * The rule is "a guardian never reads what the specialist wrote for
     * herself", and it is implemented in the fail-safe direction: the column
     * is off for everyone, and staff controllers switch it on with
     * `makeVisible`. Written the other way round — visible by default, hidden
     * for guardians — every new endpoint would leak it until someone
     * remembered, and the person who finds out is the mother reading that the
     * academy thinks she is not trying.
     */
    protected $hidden = ['private_notes'];

    protected function casts(): array
    {
        return [
            'scheduled_at' => 'datetime',
            'published_at' => 'datetime',
            'specialty' => Specialty::class,
        ];
    }

    /* ---------------------------------------------------------------------
     | Relations
     |------------------------------------------------------------------- */

    public function student(): BelongsTo
    {
        return $this->belongsTo(Student::class);
    }

    public function enrollment(): BelongsTo
    {
        return $this->belongsTo(Enrollment::class);
    }

    public function specialist(): BelongsTo
    {
        return $this->belongsTo(User::class, 'specialist_id');
    }

    public function ratings(): HasMany
    {
        return $this->hasMany(GoalRating::class);
    }

    public function attachments(): HasMany
    {
        return $this->hasMany(SessionAttachment::class);
    }

    public function addenda(): HasMany
    {
        return $this->hasMany(ReportAddendum::class)->oldest();
    }

    public function reads(): HasMany
    {
        return $this->hasMany(ReportRead::class);
    }

    /* ---------------------------------------------------------------------
     | Scopes
     |------------------------------------------------------------------- */

    /**
     * What a family is allowed to see: their own children, and only the
     * reports that were actually sent.
     *
     * A draft is not a shy report — it is a report that does not exist yet.
     * The session it belongs to is hidden entirely rather than shown empty,
     * because "الجلسة تمت، التقرير قيد الكتابة" invites a parent to refresh
     * for three days, and the absence itself is a promise the academy has not
     * yet decided to keep.
     */
    public function scopeVisibleTo(Builder $query, User $user): Builder
    {
        if ($user->role->isStaff()) {
            return $query;
        }

        return $query
            ->whereHas('student.guardians', fn (Builder $q) => $q->where('users.id', $user->id))
            ->where(fn (Builder $q) => $q
                ->where('report_status', 'published')
                // Absences and cancellations carry no report and are shown to
                // the family regardless — see the note on `status` below.
                ->orWhereIn('status', ['absent', 'excused', 'cancelled']));
    }

    public function scopePublished(Builder $query): Builder
    {
        return $query->where('report_status', 'published');
    }

    public function scopeDraft(Builder $query): Builder
    {
        return $query->where('report_status', 'draft');
    }

    /** Sessions that have happened and still have nothing written on them. */
    public function scopeAwaitingReport(Builder $query): Builder
    {
        return $query->where('status', 'held')->where('report_status', 'draft');
    }

    public function scopeBetween(Builder $query, ?string $from, ?string $to): Builder
    {
        return $query
            ->when($from, fn (Builder $q) => $q->whereDate('scheduled_at', '>=', $from))
            ->when($to, fn (Builder $q) => $q->whereDate('scheduled_at', '<=', $to));
    }

    /* ---------------------------------------------------------------------
     | State
     |------------------------------------------------------------------- */

    public function isPublished(): bool
    {
        return $this->report_status === 'published';
    }

    /** The child did not come. Three ways, all of which the family sees. */
    public function isMissed(): bool
    {
        return in_array($this->status, ['absent', 'excused', 'cancelled'], true);
    }

    /**
     * Enough written down to be worth a parent's time.
     *
     * `activities` and `home_plan` are the two that must be there. The first
     * is what the session was; the second is the only part the family can act
     * on, and a report with nothing to act on is read once and then never
     * again.
     */
    public function isReportComplete(): bool
    {
        return filled($this->activities) && filled($this->home_plan);
    }

    /** Read receipts, for the specialist: who opened it and when. */
    public function readBy(User $user): bool
    {
        return $this->reads()->where('user_id', $user->id)->exists();
    }
}
