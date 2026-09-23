<?php

namespace App\Services;

use App\Models\Goal;
use App\Models\Student;
use App\Models\TherapySession;
use App\Models\User;
use Illuminate\Support\Collection;

/**
 * The arithmetic behind everything a parent is asked to believe.
 *
 * It lives in one class because the same numbers appear on four screens — the
 * child's file, the goal curve, the parent's home screen and the periodic
 * report — and four screens computing "how is he doing" four slightly
 * different ways is how an academy ends up arguing with a family about its own
 * figures.
 *
 * Nothing here is stored. A cached summary of a child's progress is a summary
 * that is wrong the first time someone corrects yesterday's rating, and being
 * quietly wrong about this is worse than being slow.
 */
class Progress
{
    /**
     * The child's file, summarised.
     *
     * Attendance is counted over the last ninety days rather than all time:
     * a boy who missed a month in his first year and has not missed a session
     * since should not be looking at 82% two years later. The recent number is
     * the one that describes what is happening now, which is what the figure
     * is being read for.
     *
     * @return array<string, mixed>
     */
    public function studentSummary(Student $student, User $viewer): array
    {
        $since = now()->subDays(90);

        $counts = $student->sessions()
            ->where('scheduled_at', '>=', $since)
            ->selectRaw('status, count(*) as n')
            ->groupBy('status')
            ->pluck('n', 'status');

        $held = (int) ($counts['held'] ?? 0);
        $absent = (int) ($counts['absent'] ?? 0);
        $excused = (int) ($counts['excused'] ?? 0);

        // Cancellations are the academy's doing and are left out of the
        // denominator. Charging a family an attendance rate for a session the
        // academy called off is a figure that invites an argument it deserves
        // to lose.
        $expected = $held + $absent + $excused;

        $goals = Goal::where('student_id', $student->id)
            ->with(['ratings' => fn ($q) => $q->reorder('measured_at', 'desc')->limit(1)])
            ->get();

        $summary = [
            'attendance' => [
                'window_days' => 90,
                'held' => $held,
                'absent' => $absent,
                'excused' => $excused,
                'expected' => $expected,
                'rate' => $expected > 0 ? round($held / $expected * 100) : null,
            ],
            'goals' => [
                'active' => $goals->where('status', 'active')->count(),
                'achieved' => $goals->where('status', 'achieved')->count(),
                'moving' => $this->movingCount($goals),
            ],
            'last_session' => $this->lastSessionFor($student, $viewer),
            'next_session' => $student->sessions()
                ->where('status', 'scheduled')
                ->where('scheduled_at', '>=', now()->startOfDay())
                ->orderBy('scheduled_at')
                ->value('scheduled_at'),
        ];

        if ($viewer->role->isStaff()) {
            $summary['unwritten_reports'] = $student->sessions()->awaitingReport()->count();
        }

        return $summary;
    }

    /**
     * One goal's history, in the shape a curve is drawn from.
     *
     * The baseline is prepended as a point rather than left as a separate
     * number, so the line starts where the child started. Without it the first
     * session becomes the origin and every goal looks like it began wherever
     * it happened to be measured first.
     *
     * @return array<string, mixed>
     */
    public function goalCurve(Goal $goal): array
    {
        $ratings = $goal->ratings()
            ->with('session:id,scheduled_at,number')
            ->get()
            ->filter(fn ($r) => $r->session !== null);

        $points = $ratings->map(fn ($rating) => [
            'date' => $rating->session->scheduled_at->toDateString(),
            'session' => $rating->session->number,
            'level' => $rating->level->value,
            'level_label' => $rating->level->label(),
            'trials' => $rating->trials,
            'successes' => $rating->successes,
            'rate' => $rating->trials > 0
                ? round(($rating->successes ?? 0) / $rating->trials * 100)
                : null,
            'note' => $rating->note,
        ])->values();

        $levels = $points->pluck('level');

        return [
            'goal' => [
                'id' => $goal->id,
                // The screen needs a way back to the child's file, and the
                // curve is reachable directly from a link in a report.
                'student_id' => $goal->student_id,
                'title' => $goal->title,
                'criteria' => $goal->criteria,
                'baseline' => $goal->baseline,
                'target' => $goal->target,
                'status' => $goal->status,
                'started_at' => $goal->started_at?->toDateString(),
                'achieved_at' => $goal->achieved_at?->toDateString(),
            ],
            'baseline_point' => [
                'date' => $goal->started_at?->toDateString(),
                'level' => $goal->baseline,
            ],
            'points' => $points,
            'summary' => [
                'sessions' => $points->count(),
                'latest' => $levels->last(),
                'best' => $levels->max(),
                'delta' => $levels->isEmpty() ? null : $levels->last() - $goal->baseline,
                /*
                 * The average of the last three, against the average of the
                 * three before them. A single session is noise — a child who
                 * slept badly scores a 1 on a goal he has held at 3 for a
                 * month — and an arrow drawn from one session to the next
                 * would tell a parent his son had regressed.
                 */
                'trend' => $this->trend($levels),
            ],
        ];
    }

    /**
     * "متحسّن / ثابت / متراجع", or null when there is not enough to say.
     *
     * Four ratings minimum before this answers at all. Declaring a trend from
     * two points is a coin toss dressed as a finding, and the person reading
     * it is a parent who will remember what it said.
     */
    private function trend(Collection $levels): ?string
    {
        if ($levels->count() < 4) {
            return null;
        }

        $recent = $levels->slice(-3)->avg();
        $before = $levels->slice(-6, 3)->avg() ?? $levels->slice(0, -3)->avg();

        if ($before === null) {
            return null;
        }

        return match (true) {
            $recent - $before >= 0.5 => 'improving',
            $before - $recent >= 0.5 => 'declining',
            default => 'steady',
        };
    }

    /** Goals whose latest score is above the baseline they started from. */
    private function movingCount(Collection $goals): int
    {
        return $goals->filter(function (Goal $goal) {
            $latest = $goal->ratings->first()?->level?->value;

            return $latest !== null && $latest > $goal->baseline;
        })->count();
    }

    /**
     * The last thing that happened, as this viewer is allowed to see it.
     *
     * A parent gets the last *published* session; a draft is not a shy report,
     * it is one that does not exist yet. Staff get the last one that happened
     * whether it has been written up or not — for them the unwritten one is
     * the whole point of looking.
     *
     * @return array<string, mixed>|null
     */
    private function lastSessionFor(Student $student, User $viewer): ?array
    {
        $session = $student->sessions()
            ->visibleTo($viewer)
            ->where('scheduled_at', '<=', now())
            ->latest('scheduled_at')
            ->first();

        if (! $session) {
            return null;
        }

        return [
            'id' => $session->id,
            'number' => $session->number,
            'scheduled_at' => $session->scheduled_at->toDateTimeString(),
            'status' => $session->status,
            'report_status' => $session->report_status,
            'specialty' => $session->specialty?->value,
        ];
    }

    /**
     * What the office looks at first thing: sessions that happened and were
     * never written up, oldest first.
     *
     * Oldest first and not newest, deliberately. The report nobody has written
     * from eleven days ago is the one that has stopped being writable — the
     * specialist no longer remembers the session — and it is the one a family
     * has been waiting on.
     */
    public function unwrittenQueue(?User $specialist = null, int $limit = 20): Collection
    {
        return TherapySession::query()
            ->awaitingReport()
            ->when($specialist, fn ($q) => $q->where('specialist_id', $specialist->id))
            ->where('scheduled_at', '<=', now())
            ->with(['student:id,name,file_number', 'specialist:id,name'])
            ->orderBy('scheduled_at')
            ->limit($limit)
            ->get();
    }
}
