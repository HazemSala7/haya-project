<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * The day the child was actually measured — not the day someone typed it in.
 *
 * Every curve in this system is ordered by this column. It was `created_at`
 * first, and that is wrong twice over:
 *
 *  - A specialist writes Monday's report on Wednesday afternoon, after she has
 *    already written Tuesday's. By insert time Monday is the newest rating, so
 *    "where he is now" reports Monday's score and the curve draws the week in
 *    the wrong order.
 *  - Ratings saved in the same second — a whole session's goals, or a seeded
 *    demo — tie, and the tie-break is whatever the database feels like. "The
 *    latest rating" then means nothing at all.
 *
 * Copied from the session rather than joined through it, for the same reason
 * the sessions copy their specialty off the enrolment: it is the chronology of
 * the child's therapy, and it must not shift because a row somewhere else was
 * edited.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('goal_ratings', function (Blueprint $table) {
            $table->dateTime('measured_at')->nullable()->after('goal_id')->index();
        });

        // Backfill from the session each rating belongs to.
        DB::statement(
            'UPDATE goal_ratings SET measured_at = ('
            .'SELECT scheduled_at FROM therapy_sessions WHERE therapy_sessions.id = goal_ratings.therapy_session_id'
            .')',
        );
    }

    public function down(): void
    {
        Schema::table('goal_ratings', function (Blueprint $table) {
            $table->dropColumn('measured_at');
        });
    }
};
