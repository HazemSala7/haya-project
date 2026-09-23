<?php

namespace App\Models;

use App\Enums\Role;
use App\Enums\Specialty;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;

class User extends Authenticatable
{
    use HasApiTokens, HasFactory, Notifiable;

    protected $fillable = [
        'name', 'email', 'password', 'role', 'phone',
        'specialty', 'title', 'is_active',
    ];

    protected $hidden = ['password', 'remember_token'];

    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
            'role' => Role::class,
            'specialty' => Specialty::class,
            'is_active' => 'boolean',
            'last_seen_at' => 'datetime',
        ];
    }

    /* ---------------------------------------------------------------------
     | Relations
     |
     | A user is on one side or the other of the academy, never both, so these
     | come in two sets and only one set is ever populated for a given row.
     |------------------------------------------------------------------- */

    /** Guardians: the children this person is allowed to read. */
    public function children(): BelongsToMany
    {
        return $this->belongsToMany(Student::class, 'guardian_student')
            ->withPivot(['relation', 'is_primary'])
            ->withTimestamps();
    }

    /** Specialists: the programmes assigned to her. */
    public function enrollments(): HasMany
    {
        return $this->hasMany(Enrollment::class, 'specialist_id');
    }

    /** Specialists: every session she is down to run. */
    public function sessions(): HasMany
    {
        return $this->hasMany(TherapySession::class, 'specialist_id');
    }

    /* ---------------------------------------------------------------------
     | Scopes
     |------------------------------------------------------------------- */

    public function scopeActive(Builder $query): Builder
    {
        return $query->where('is_active', true);
    }

    public function scopeRole(Builder $query, Role $role): Builder
    {
        return $query->where('role', $role->value);
    }

    public function scopeSearch(Builder $query, ?string $term): Builder
    {
        if (! $term = trim((string) $term)) {
            return $query;
        }

        return $query->where(fn (Builder $q) => $q
            ->where('name', 'like', "%{$term}%")
            ->orWhere('email', 'like', "%{$term}%")
            ->orWhere('phone', 'like', "%{$term}%"));
    }

    /* ---------------------------------------------------------------------
     | Role questions
     |------------------------------------------------------------------- */

    /**
     * Not called `is()`: Eloquent already owns that name for comparing two
     * models, and overriding it with a different meaning breaks the framework
     * rather than this class.
     */
    public function hasRole(Role ...$roles): bool
    {
        return in_array($this->role, $roles, true);
    }

    public function isAdmin(): bool
    {
        return $this->role === Role::Admin;
    }

    public function isGuardian(): bool
    {
        return $this->role === Role::Guardian;
    }

    /**
     * May this person write the report on this session?
     *
     * The assigned specialist or the admin — and nobody else, including
     * another specialist in the same programme. A report carries a name at the
     * bottom, and it has to be the name of the woman who was in the room.
     *
     * An unassigned session is writable by any specialist, because that is
     * exactly the case where somebody stepped in and the diary had not caught
     * up with it yet.
     */
    public function mayWriteOn(TherapySession $session): bool
    {
        if ($this->isAdmin()) {
            return true;
        }

        if ($this->role !== Role::Specialist) {
            return false;
        }

        return $session->specialist_id === null || $session->specialist_id === $this->id;
    }
}
