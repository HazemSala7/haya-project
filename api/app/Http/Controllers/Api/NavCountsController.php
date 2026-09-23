<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Models\Message;
use App\Models\ProgressReport;
use App\Models\Student;
use App\Models\TherapySession;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The numbers that sit beside the menu items.
 *
 * Deliberately its own endpoint rather than a corner of the dashboard: the
 * sidebar is on every screen, and it re-reads these after every navigation so
 * a count never contradicts the page the user just acted on. That means it has
 * to be cheap — eight `count(*)` queries against indexed columns and nothing
 * loaded into memory.
 *
 * Every number is split into two kinds, because they are read differently:
 *
 *   `attention` — something is waiting for a person. Drawn filled and coloured.
 *   `total`     — simply how many there are. Drawn quiet, or not at all.
 *
 * A menu covered in badges teaches people to ignore badges, so an `attention`
 * count of zero is returned as zero and the sidebar draws nothing for it.
 */
class NavCountsController extends Controller
{
    public function __invoke(Request $request): JsonResponse
    {
        $user = $request->user();

        return response()->json([
            'data' => match ($user->role) {
                Role::Admin => $this->forAdmin(),
                Role::Specialist => $this->forSpecialist($user),
                Role::Guardian => $this->forGuardian($user),
            },
        ]);
    }

    /** @return array<string, mixed> */
    private function forAdmin(): array
    {
        return [
            'sessions' => [
                'total' => TherapySession::whereDate('scheduled_at', today())->count(),
                'attention' => TherapySession::awaitingReport()
                    ->where('scheduled_at', '<=', now())
                    ->count(),
            ],
            'students' => ['total' => Student::active()->count(), 'attention' => 0],
            'reports' => [
                'total' => ProgressReport::count(),
                'attention' => ProgressReport::where('status', 'draft')->count(),
            ],
            'messages' => [
                'total' => 0,
                // Only what a family sent. The office chasing its own staff's
                // replies is not the number that matters here.
                'attention' => Message::unread()
                    ->whereHas('sender', fn ($q) => $q->where('role', Role::Guardian->value))
                    ->count(),
            ],
            'staff' => ['total' => User::active()->count(), 'attention' => 0],
        ];
    }

    /** @return array<string, mixed> */
    private function forSpecialist(User $user): array
    {
        return [
            'sessions' => [
                'total' => TherapySession::where('specialist_id', $user->id)
                    ->whereDate('scheduled_at', today())
                    ->count(),
                'attention' => TherapySession::awaitingReport()
                    ->where('specialist_id', $user->id)
                    ->where('scheduled_at', '<=', now())
                    ->count(),
            ],
            'students' => [
                'total' => Student::active()
                    ->whereHas('enrollments', fn ($q) => $q->active()->where('specialist_id', $user->id))
                    ->count(),
                'attention' => 0,
            ],
            'reports' => [
                'total' => ProgressReport::where('author_id', $user->id)->count(),
                'attention' => ProgressReport::where('author_id', $user->id)
                    ->where('status', 'draft')
                    ->count(),
            ],
            'messages' => [
                'total' => 0,
                'attention' => Message::unread()->notFrom($user)
                    ->whereHas('student.enrollments', fn ($q) => $q->active()->where('specialist_id', $user->id))
                    ->count(),
            ],
        ];
    }

    /**
     * A parent's badges answer one question: is there anything new about my
     * child? So both of hers are `attention` — a count of reports she has
     * already read is a number she has no use for.
     *
     * @return array<string, mixed>
     */
    private function forGuardian(User $user): array
    {
        $children = $user->children()->pluck('students.id');

        return [
            'reports' => [
                'total' => ProgressReport::whereIn('student_id', $children)
                    ->where('status', 'published')
                    ->count(),
                'attention' => 0,
            ],
            'messages' => [
                'total' => 0,
                'attention' => Message::unread()->notFrom($user)
                    ->whereIn('student_id', $children)
                    ->count(),
            ],
            'home' => [
                'total' => 0,
                // Session reports she has not opened — the whole reason the
                // app is on her phone.
                'attention' => TherapySession::published()
                    ->whereIn('student_id', $children)
                    ->whereDoesntHave('reads', fn ($q) => $q->where('user_id', $user->id))
                    ->count(),
            ],
        ];
    }
}
