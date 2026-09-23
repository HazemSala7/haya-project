<?php

namespace App\Services;

use App\Exceptions\OperationRefused;
use App\Models\Goal;
use App\Models\GoalRating;
use App\Models\ReportAddendum;
use App\Models\TherapySession;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Everything that happens to a session report between being typed and being
 * read by a family.
 *
 * Four rules live here and nowhere else:
 *
 *  1. A report is only sent on purpose. Saving is not sending.
 *  2. A report with nothing to act on is not sent at all.
 *  3. Once sent, the text is frozen. A correction is a new dated line.
 *  4. A goal is only scored by the session that scored it, and only against
 *     goals that belong to the child in front of her.
 *
 * They are here rather than in the controller because all four are about the
 * report's integrity, and integrity rules spread across four endpoints are
 * integrity rules that hold on three of them.
 */
class ReportDesk
{
    /**
     * Write the report. Draft only.
     *
     * @param  array<string, mixed>  $data
     */
    public function draft(TherapySession $session, array $data): TherapySession
    {
        $this->refuseIfPublished($session);

        $session->fill(array_intersect_key($data, array_flip([
            'mood', 'activities', 'progress', 'difficulties', 'home_plan', 'private_notes',
        ])));

        $session->save();

        return $session->fresh();
    }

    /**
     * Send it to the family.
     *
     * The completeness check is not bureaucracy. A report that says only "تمت
     * الجلسة" trains a parent to stop opening them, and once they have stopped
     * the academy has lost the thing it was doing all this for. `activities`
     * says what happened; `home_plan` is the only part the family can act on.
     */
    public function publish(TherapySession $session, User $by): TherapySession
    {
        if ($session->isPublished()) {
            throw new OperationRefused('هذا التقرير مُرسل من قبل. التصحيح يكون بإضافة سطر عليه.');
        }

        if ($session->isMissed()) {
            throw new OperationRefused('الجلسة ما تمت — الغياب بوصل ولي الأمر لحاله بدون تقرير.');
        }

        if ($session->status !== 'held') {
            throw new OperationRefused('علّم الجلسة «تمت» قبل ما تبعت التقرير.');
        }

        if (blank($session->activities)) {
            throw new OperationRefused('اكتب شو عملتوا اليوم قبل الإرسال.');
        }

        if (blank($session->home_plan)) {
            throw new OperationRefused('اكتب شو بدكم من الأهل بالبيت — هاد الجزء الوحيد اللي بقدروا يشتغلوا عليه.');
        }

        return DB::transaction(function () use ($session, $by) {
            $session->forceFill([
                'report_status' => 'published',
                'published_at' => now(),
                // The name at the bottom of what the family reads. Stamped at
                // publish time so a later reassignment of the diary cannot
                // change who signed this one.
                'specialist_id' => $session->specialist_id ?? $by->id,
            ])->save();

            return $session->fresh();
        });
    }

    /**
     * التصحيح — a dated line under a report that has already been read.
     *
     * The published paragraphs are not touched. A mother who remembers reading
     * something different must be able to be right, and an academy that can
     * silently rewrite last night's report cannot prove it did not.
     */
    public function addendum(TherapySession $session, User $by, string $body): ReportAddendum
    {
        if (! $session->isPublished()) {
            throw new OperationRefused('التقرير لسه مسوّدة — عدّله مباشرة بدل ما تضيف تصحيح.');
        }

        return $session->addenda()->create([
            'author_id' => $by->id,
            'body' => $body,
        ]);
    }

    /**
     * Score the goals worked on in this session.
     *
     * Replaces the whole set rather than merging: the form shows every active
     * goal and the specialist submits the ones she worked on, so a goal
     * dropped from the list means "we did not touch it today" — which merging
     * would silently record as last week's score all over again.
     *
     * @param  array<int, array{goal_id: int, level: int, trials?: int|null, successes?: int|null, note?: string|null}>  $rows
     */
    public function rate(TherapySession $session, array $rows): TherapySession
    {
        $this->refuseIfPublished($session);

        // Goals belonging to this child, keyed for a membership test. Passing
        // another child's goal id must not quietly write a row that then shows
        // up on his curve.
        $own = Goal::where('student_id', $session->student_id)
            ->pluck('id')
            ->flip();

        return DB::transaction(function () use ($session, $rows, $own) {
            $session->ratings()->delete();

            foreach ($rows as $row) {
                if (! $own->has($row['goal_id'])) {
                    throw new OperationRefused('هذا الهدف مش لهذا الطالب.');
                }

                $trials = $row['trials'] ?? null;
                $successes = $row['successes'] ?? null;

                // 9 successes out of 5 attempts is a typo, and stored it
                // becomes a hit rate above 100% on the parent's screen.
                if ($trials !== null && $successes !== null && $successes > $trials) {
                    throw new OperationRefused('عدد المحاولات الناجحة أكبر من عدد المحاولات.');
                }

                GoalRating::create([
                    'therapy_session_id' => $session->id,
                    'goal_id' => $row['goal_id'],
                    // The day the child was measured, copied off the session.
                    // Every curve is ordered by this and not by insert time —
                    // a report written on Wednesday about Monday belongs on
                    // Monday. See the `measured_at` migration.
                    'measured_at' => $session->scheduled_at,
                    'level' => $row['level'],
                    'trials' => $trials,
                    'successes' => $successes,
                    'note' => $row['note'] ?? null,
                ]);
            }

            return $session->fresh(['ratings.goal']);
        });
    }

    /**
     * The family opened it.
     *
     * First open only — `insertOrIgnore` rather than an update, because "she
     * has seen it" is the fact worth keeping and a re-read is not evidence of
     * anything. Staff opening a report is not a read receipt at all; the
     * caller filters that.
     */
    public function markRead(TherapySession $session, User $user): void
    {
        DB::table('report_reads')->insertOrIgnore([
            'therapy_session_id' => $session->id,
            'user_id' => $user->id,
            'read_at' => now(),
        ]);
    }

    private function refuseIfPublished(TherapySession $session): void
    {
        if ($session->isPublished()) {
            throw new OperationRefused('التقرير مُرسل ومقروء — ما بينعدّل. ضيف تصحيح عليه.');
        }
    }
}
