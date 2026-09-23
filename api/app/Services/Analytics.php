<?php

namespace App\Services;

use App\Enums\PromptLevel;
use App\Enums\Role;
use App\Enums\Specialty;
use App\Models\GoalRating;
use App\Models\TherapySession;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * The figures behind the analytics screen.
 *
 * Every aggregate is computed in PHP over rows the database hands back whole,
 * rather than in SQL. That is a deliberate trade:
 *
 *  - The date functions differ between engines — `DATE_FORMAT`/`YEARWEEK` on
 *    MySQL, `strftime` on SQLite — so a grouped query written for the server
 *    silently returns something else on a developer's laptop, which is the
 *    worst possible place for a metric to disagree with itself.
 *  - The dataset is one academy: a few hundred sessions and a few thousand
 *    ratings. The whole set fits in memory with room to spare, and the query
 *    that fetches it is a single indexed range scan.
 *
 * If this ever grows past a few tens of thousands of sessions, the right fix
 * is a nightly rollup table — not engine-specific SQL scattered here.
 */
class Analytics
{
    /** @return array<string, mixed> */
    public function overview(int $weeks = 12, ?User $scopeTo = null): array
    {
        $since = now()->copy()->subWeeks($weeks)->startOfWeek();

        $sessions = TherapySession::query()
            ->where('scheduled_at', '>=', $since)
            ->where('scheduled_at', '<=', now())
            ->when($scopeTo, fn ($q) => $q->where('specialist_id', $scopeTo->id))
            ->get([
                'id', 'student_id', 'specialist_id', 'specialty', 'scheduled_at',
                'status', 'mood', 'report_status', 'published_at',
            ]);

        return [
            'window_weeks' => $weeks,
            'weekly' => $this->weekly($sessions, $weeks),
            'by_specialty' => $this->bySpecialty($sessions),
            'moods' => $this->moods($sessions),
            'turnaround' => $this->turnaround($sessions),
            'levels' => $this->levelDistribution($since, $scopeTo),
            'level_trend' => $this->levelTrend($since, $weeks, $scopeTo),
            'specialists' => $scopeTo ? [] : $this->specialists($sessions),
            'engagement' => $this->engagement($scopeTo),
        ];
    }

    /**
     * Attendance week by week.
     *
     * Every week in the window is present even when nothing happened in it —
     * a gap silently closed up makes a fortnight the academy was shut look
     * like a fortnight of perfect attendance.
     *
     * @param  Collection<int, TherapySession>  $sessions
     * @return array<int, array<string, mixed>>
     */
    private function weekly(Collection $sessions, int $weeks): array
    {
        $buckets = [];

        for ($i = $weeks; $i >= 0; $i--) {
            $start = now()->copy()->subWeeks($i)->startOfWeek();
            $buckets[$start->toDateString()] = [
                'week' => $start->toDateString(),
                'held' => 0,
                'absent' => 0,
                'excused' => 0,
                'cancelled' => 0,
            ];
        }

        foreach ($sessions as $session) {
            $key = $session->scheduled_at->copy()->startOfWeek()->toDateString();

            if (! isset($buckets[$key]) || ! isset($buckets[$key][$session->status])) {
                continue;
            }

            $buckets[$key][$session->status]++;
        }

        return array_values(array_map(function (array $row) {
            // Cancellations are the academy's doing and stay out of the
            // denominator — see Progress::studentSummary for the same rule.
            $expected = $row['held'] + $row['absent'] + $row['excused'];
            $row['expected'] = $expected;
            $row['rate'] = $expected > 0 ? round($row['held'] / $expected * 100) : null;

            return $row;
        }, $buckets));
    }

    /**
     * @param  Collection<int, TherapySession>  $sessions
     * @return array<int, array<string, mixed>>
     */
    private function bySpecialty(Collection $sessions): array
    {
        return collect(Specialty::cases())->map(function (Specialty $specialty) use ($sessions) {
            $mine = $sessions->where('specialty', $specialty);

            return [
                'specialty' => $specialty->value,
                'label' => $specialty->label(),
                'sessions' => $mine->count(),
                'held' => $mine->where('status', 'held')->count(),
                'missed' => $mine->whereIn('status', ['absent', 'excused'])->count(),
                'students' => $mine->pluck('student_id')->unique()->count(),
            ];
        })->values()->all();
    }

    /**
     * How the children arrive.
     *
     * Worth a chart because it is the one thing on this screen the academy
     * does not control: a month where "متوتّر" doubles is a question about the
     * waiting room, the timetable, or the transport — not about the therapy.
     *
     * @param  Collection<int, TherapySession>  $sessions
     * @return array<int, array<string, mixed>>
     */
    private function moods(Collection $sessions): array
    {
        $order = ['happy', 'calm', 'tired', 'agitated', 'crying', 'resistant'];

        $counts = $sessions->where('status', 'held')
            ->whereNotNull('mood')
            ->countBy('mood');

        return collect($order)
            ->map(fn (string $mood) => ['mood' => $mood, 'count' => (int) ($counts[$mood] ?? 0)])
            ->all();
    }

    /**
     * How long a family waits for the report after the session.
     *
     * The single most honest measure of whether this system is being used the
     * way it was sold. A report that lands the same evening is worth several
     * that land a fortnight later, because by then the parent has stopped
     * expecting one.
     *
     * @param  Collection<int, TherapySession>  $sessions
     * @return array<string, mixed>
     */
    private function turnaround(Collection $sessions): array
    {
        $published = $sessions->where('report_status', 'published')->filter(
            fn ($s) => $s->published_at !== null,
        );

        $buckets = ['same_day' => 0, 'next_day' => 0, 'within_3' => 0, 'within_7' => 0, 'later' => 0];
        $days = [];

        foreach ($published as $session) {
            $lag = $session->scheduled_at->startOfDay()
                ->diffInDays($session->published_at->startOfDay());

            $lag = max(0, (int) $lag);
            $days[] = $lag;

            match (true) {
                $lag === 0 => $buckets['same_day']++,
                $lag === 1 => $buckets['next_day']++,
                $lag <= 3 => $buckets['within_3']++,
                $lag <= 7 => $buckets['within_7']++,
                default => $buckets['later']++,
            };
        }

        sort($days);

        return [
            'buckets' => $buckets,
            'published' => $published->count(),
            // The median, not the mean: one report written three months late
            // drags an average somewhere no actual family experienced.
            'median_days' => $days === [] ? null : $days[intdiv(count($days), 2)],
        ];
    }

    /**
     * Where every score sat, across the whole window.
     *
     * @return array<int, array<string, mixed>>
     */
    private function levelDistribution(Carbon $since, ?User $scopeTo): array
    {
        $counts = GoalRating::query()
            ->where('measured_at', '>=', $since)
            ->when($scopeTo, fn ($q) => $q->whereHas(
                'session',
                fn ($s) => $s->where('specialist_id', $scopeTo->id),
            ))
            ->get(['level'])
            ->countBy(fn (GoalRating $r) => $r->level->value);

        return collect(PromptLevel::cases())
            ->map(fn (PromptLevel $level) => [
                'level' => $level->value,
                'label' => $level->label(),
                'count' => (int) ($counts[$level->value] ?? 0),
            ])
            ->reverse()
            ->values()
            ->all();
    }

    /**
     * The average prompt level, week by week.
     *
     * The nearest thing the academy has to a single measure of whether the
     * children as a whole are moving. It creeps rather than jumps: a rise of
     * half a step across a term is a real result, so the axis stays pinned to
     * the full 0–4 scale and refuses to flatter it.
     *
     * @return array<int, array<string, mixed>>
     */
    private function levelTrend(Carbon $since, int $weeks, ?User $scopeTo): array
    {
        $ratings = GoalRating::query()
            ->where('measured_at', '>=', $since)
            ->when($scopeTo, fn ($q) => $q->whereHas(
                'session',
                fn ($s) => $s->where('specialist_id', $scopeTo->id),
            ))
            ->get(['level', 'measured_at']);

        $buckets = [];

        for ($i = $weeks; $i >= 0; $i--) {
            $start = now()->copy()->subWeeks($i)->startOfWeek();
            $buckets[$start->toDateString()] = [];
        }

        foreach ($ratings as $rating) {
            if (! $rating->measured_at) {
                continue;
            }

            $key = $rating->measured_at->copy()->startOfWeek()->toDateString();

            if (isset($buckets[$key])) {
                $buckets[$key][] = $rating->level->value;
            }
        }

        return collect($buckets)->map(fn (array $levels, string $week) => [
            'week' => $week,
            'avg' => $levels === [] ? null : round(array_sum($levels) / count($levels), 2),
            'count' => count($levels),
        ])->values()->all();
    }

    /**
     * Who is carrying what, and who is behind.
     *
     * @param  Collection<int, TherapySession>  $sessions
     * @return array<int, array<string, mixed>>
     */
    private function specialists(Collection $sessions): array
    {
        $names = User::query()
            ->role(Role::Specialist)
            ->get(['id', 'name', 'title', 'is_active'])
            ->keyBy('id');

        return $sessions
            ->whereNotNull('specialist_id')
            ->groupBy('specialist_id')
            ->map(function (Collection $mine, $id) use ($names) {
                $person = $names[$id] ?? null;

                $held = $mine->where('status', 'held');

                return [
                    'id' => (int) $id,
                    'name' => $person?->name ?? '—',
                    'title' => $person?->title,
                    'is_active' => (bool) ($person?->is_active ?? false),
                    'sessions' => $mine->count(),
                    'held' => $held->count(),
                    'students' => $mine->pluck('student_id')->unique()->count(),
                    'unwritten' => $held->where('report_status', 'draft')->count(),
                ];
            })
            ->sortByDesc('sessions')
            ->values()
            ->all();
    }

    /**
     * Are the reports being read?
     *
     * The quietest failure this system has: everything can be green — written,
     * published, on time — while nobody opens any of it.
     *
     * @return array<string, mixed>
     */
    private function engagement(?User $scopeTo): array
    {
        $published = TherapySession::query()
            ->published()
            ->when($scopeTo, fn ($q) => $q->where('specialist_id', $scopeTo->id))
            ->withCount('reads')
            ->get(['id'])
            ->pipe(fn (Collection $rows) => [
                'total' => $rows->count(),
                'opened' => $rows->where('reads_count', '>', 0)->count(),
            ]);

        $published['unopened'] = $published['total'] - $published['opened'];
        $published['rate'] = $published['total'] > 0
            ? round($published['opened'] / $published['total'] * 100)
            : null;

        return $published;
    }
}
