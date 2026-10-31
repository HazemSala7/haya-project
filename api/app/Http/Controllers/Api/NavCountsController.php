<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Http\Controllers\Controller;
use App\Models\Invoice;
use App\Models\Message;
use App\Models\ProgressReport;
use App\Models\Student;
use App\Models\TherapySession;
use App\Models\User;
use Illuminate\Database\QueryException;
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
            'finance' => $this->finance(),
            'staff' => ['total' => User::active()->count(), 'attention' => 0],
        ];
    }

    /**
     * Overdue invoices, not outstanding ones.
     *
     * Every family owes the current month for most of the month, so a badge
     * counting what is outstanding would be permanently red and would teach
     * the office to stop reading badges — including the ones that matter. Past
     * its due date is the number somebody has to act on, and it is zero when
     * the academy is up to date.
     *
     * Overdue is a stored column that nothing else ages — there is no cron on
     * this host — so it is swept here, on the one read that happens on every
     * screen. See Invoice::sweepOverdue.
     *
     * ---------------------------------------------------------------------
     * Why the catch.
     *
     * This is the sidebar. It loads on every page the office opens, and it is
     * the only count here that touches a table added after the academy went
     * live. Between uploading a release over FTP and calling the migration
     * endpoint there is a window — minutes, but real — where `invoices` does
     * not exist yet; a bare query there would take the entire dashboard down,
     * including the screen the migration is run from. A missing badge during
     * that window is the correct failure. Anything worse than a missing table
     * still surfaces, loudly, on /finance itself.
     *
     * @return array<string, int>
     */
    private function finance(): array
    {
        try {
            Invoice::sweepOverdue();

            return ['total' => 0, 'attention' => Invoice::where('status', 'overdue')->count()];
        } catch (QueryException) {
            return ['total' => 0, 'attention' => 0];
        }
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
