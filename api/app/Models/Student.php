<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class Student extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'file_number', 'name', 'birth_date', 'gender', 'national_id',
        'diagnosis', 'diagnosis_notes', 'medical_alert',
        'school', 'grade', 'enrolled_at', 'status', 'left_at', 'notes',
    ];

    protected function casts(): array
    {
        return [
            'birth_date' => 'date',
            'enrolled_at' => 'date',
            'left_at' => 'date',
        ];
    }

    protected $appends = ['age_label'];

    /* ---------------------------------------------------------------------
     | Relations
     |------------------------------------------------------------------- */

    public function guardians(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'guardian_student')
            ->withPivot(['relation', 'is_primary'])
            ->withTimestamps();
    }

    public function enrollments(): HasMany
    {
        return $this->hasMany(Enrollment::class);
    }

    public function goals(): HasMany
    {
        return $this->hasMany(Goal::class);
    }

    public function sessions(): HasMany
    {
        return $this->hasMany(TherapySession::class);
    }

    public function progressReports(): HasMany
    {
        return $this->hasMany(ProgressReport::class);
    }

    public function messages(): HasMany
    {
        return $this->hasMany(Message::class);
    }

    /* ---------------------------------------------------------------------
     | Scopes
     |------------------------------------------------------------------- */

    /**
     * The privacy model, in one place.
     *
     * A guardian sees their own children and nothing else. Every
     * guardian-facing query in the system starts here rather than re-deriving
     * the rule — a permission that has to be remembered in twelve places is a
     * permission that will be forgotten in one, and the one it is forgotten in
     * shows a stranger another family's child.
     *
     * Staff see every child, deliberately. A specialist covering a colleague
     * who is off sick is routine, and locking her out means the office
     * reassigning rows every time someone has flu — which they will not do, so
     * they will share a login instead, and then nothing in the audit trail
     * means anything.
     */
    public function scopeVisibleTo(Builder $query, User $user): Builder
    {
        if ($user->role->isStaff()) {
            return $query;
        }

        return $query->whereHas(
            'guardians',
            fn (Builder $q) => $q->where('users.id', $user->id),
        );
    }

    public function scopeActive(Builder $query): Builder
    {
        return $query->where('status', 'active');
    }

    public function scopeSearch(Builder $query, ?string $term): Builder
    {
        if (! $term = trim((string) $term)) {
            return $query;
        }

        return $query->where(fn (Builder $q) => $q
            ->where('name', 'like', "%{$term}%")
            ->orWhere('file_number', 'like', "%{$term}%")
            ->orWhere('diagnosis', 'like', "%{$term}%"));
    }

    /* ---------------------------------------------------------------------
     | Derived
     |------------------------------------------------------------------- */

    /**
     * "٥ سنوات و٣ شهور".
     *
     * Computed rather than stored, and shown everywhere the name is. In this
     * work the months matter: the gap between four and a half and five is the
     * difference between "on track" and "referred", and a bare birth date
     * makes every specialist do that arithmetic in her head.
     */
    public function getAgeLabelAttribute(): string
    {
        if (! $this->birth_date) {
            return '—';
        }

        $months = $this->birth_date->diffInMonths(now());
        $years = intdiv($months, 12);
        $rest = $months % 12;

        $y = match (true) {
            $years === 0 => null,
            $years === 1 => 'سنة',
            $years === 2 => 'سنتين',
            $years <= 10 => "{$years} سنوات",
            default => "{$years} سنة",
        };

        $m = match (true) {
            $rest === 0 => null,
            $rest === 1 => 'شهر',
            $rest === 2 => 'شهرين',
            $rest <= 10 => "{$rest} شهور",
            default => "{$rest} شهراً",
        };

        return match (true) {
            $y && $m => "{$y} و{$m}",
            (bool) $y => $y,
            (bool) $m => $m,
            default => 'أقل من شهر',
        };
    }

    /** Whether this user is one of the family, for a per-record check. */
    public function isGuardedBy(User $user): bool
    {
        return $this->guardians()->where('users.id', $user->id)->exists();
    }

    /**
     * The guard every guardian-facing controller runs on a single record.
     *
     * `visibleTo` covers lists; this covers "she typed an id into the URL".
     */
    public function readableBy(User $user): bool
    {
        return $user->role->isStaff() || $this->isGuardedBy($user);
    }
}
