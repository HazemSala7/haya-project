<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Models\Enrollment;
use App\Models\Message;
use App\Models\Student;
use App\Models\TherapySession;
use App\Models\User;
use App\Services\Progress;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The first screen — three of them, because three different jobs open it.
 *
 * A specialist wants today's diary and what she still owes. The office wants
 * what is falling through. A parent wants their child. Serving one screen to
 * all three would mean two of them scrolling past the part that is not theirs
 * every morning, which is how a first screen stops being read.
 */
class DashboardController extends Controller
{
    public function __construct(private Progress $progress) {}

    public function __invoke(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json(['data' => match ($user->role) {
            Role::Guardian => $this->forGuardian($user),
            Role::Specialist => $this->forSpecialist($user),
            Role::Admin => $this->forAdmin($user),
        }]);
    }

    /* ------------------------------------------------------------------ */

    /**
     * @return array<string, mixed>
     */
    private function forGuardian(User $user): array
    {
        $children = $user->children()->with([
            'enrollments' => fn ($q) => $q->active()->with('specialist:id,name,title'),
        ])->get();

        return [
            'kind' => 'guardian',
            'children' => $children->map(fn (Student $child) => [
                'id' => $child->id,
                'name' => $child->name,
                'file_number' => $child->file_number,
                'age_label' => $child->age_label,
                'status' => $child->status,
                'programmes' => $child->enrollments->map(fn ($e) => [
                    'id' => $e->id,
                    'specialty' => $e->specialty->value,
                    'specialty_label' => $e->specialty->fullLabel(),
                    'specialist' => $e->specialist?->name,
                ]),
                'summary' => $this->progress->studentSummary($child, $user),
                /*
                 * Unread reports, per child.
                 *
                 * This is the number the whole app is arranged around. A
                 * parent opens it to see whether there is something new about
                 * their son, and every other figure on the screen is context
                 * for that one.
                 */
                'unread_reports' => TherapySession::where('student_id', $child->id)
                    ->published()
                    ->whereDoesntHave('reads', fn ($q) => $q->where('user_id', $user->id))
                    ->count(),
            ]),
            'unread_messages' => Message::unread()
                ->notFrom($user)
                ->whereIn('student_id', $children->pluck('id'))
                ->count(),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function forSpecialist(User $user): array
    {
        $today = TherapySession::where('specialist_id', $user->id)
            ->whereDate('scheduled_at', today())
            ->with('student:id,name,file_number,medical_alert')
            ->orderBy('scheduled_at')
            ->get();

        return [
            'kind' => 'specialist',
            'today' => $today,
            'stats' => [
                'today_total' => $today->count(),
                'today_held' => $today->where('status', 'held')->count(),
                'students' => Enrollment::active()->where('specialist_id', $user->id)
                    ->distinct()->count('student_id'),
                /*
                 * What she still owes, and the oldest of it.
                 *
                 * Both, not just the count: eleven unwritten reports is a bad
                 * afternoon, but one from nine days ago is a different problem
                 * — she no longer remembers that session, and the family has
                 * been waiting on it since.
                 */
                'unwritten' => TherapySession::awaitingReport()
                    ->where('specialist_id', $user->id)
                    ->where('scheduled_at', '<=', now())
                    ->count(),
                'oldest_unwritten' => TherapySession::awaitingReport()
                    ->where('specialist_id', $user->id)
                    ->where('scheduled_at', '<=', now())
                    ->min('scheduled_at'),
                'unread_messages' => Message::unread()->notFrom($user)
                    ->whereHas('student.enrollments', fn ($q) => $q->active()->where('specialist_id', $user->id))
                    ->count(),
            ],
            'queue' => $this->progress->unwrittenQueue($user, 10),
        ];
    }

    /**
     * @return array<string, mixed>
     */
    private function forAdmin(User $user): array
    {
        $weekAgo = now()->subDays(7);

        $attendance = TherapySession::where('scheduled_at', '>=', $weekAgo)
            ->where('scheduled_at', '<=', now())
            ->selectRaw('status, count(*) as n')
            ->groupBy('status')
            ->pluck('n', 'status');

        $held = (int) ($attendance['held'] ?? 0);
        $absent = (int) ($attendance['absent'] ?? 0);
        $excused = (int) ($attendance['excused'] ?? 0);
        $expected = $held + $absent + $excused;

        return [
            'kind' => 'admin',
            'stats' => [
                'students' => Student::active()->count(),
                'specialists' => User::active()->role(Role::Specialist)->count(),
                'guardians' => User::active()->role(Role::Guardian)->count(),
                'sessions_today' => TherapySession::whereDate('scheduled_at', today())->count(),

                // The three failures the office exists to catch.
                'unwritten' => TherapySession::awaitingReport()
                    ->where('scheduled_at', '<=', now())->count(),
                'unassigned' => Enrollment::unassigned()->count(),
                'unanswered' => Message::unread()
                    ->whereHas('sender', fn ($q) => $q->where('role', Role::Guardian->value))
                    ->count(),

                'attendance_rate' => $expected > 0 ? round($held / $expected * 100) : null,
                'absent_week' => $absent,
            ],
            'queue' => $this->progress->unwrittenQueue(null, 12),

            /*
             * Families who have not opened anything in three weeks.
             *
             * The quietest failure in the building: the reports are written,
             * they are published, every number on this screen looks healthy,
             * and nobody is reading them. It is only visible if something goes
             * looking for it.
             */
            'silent_families' => User::active()
                ->role(Role::Guardian)
                ->where(fn ($q) => $q
                    ->whereNull('last_seen_at')
                    ->orWhere('last_seen_at', '<', now()->subDays(21)))
                ->whereHas('children', fn ($q) => $q->where('status', 'active'))
                ->with('children:id,name')
                ->limit(10)
                ->get(['id', 'name', 'phone', 'last_seen_at']),
        ];
    }
}
