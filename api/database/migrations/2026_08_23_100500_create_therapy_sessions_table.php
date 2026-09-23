<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * الجلسة — the centre of the whole system.
 *
 * One row is one appointment and the report that came out of it. They are the
 * same row and not two, because a session produces exactly one report and a
 * report belongs to exactly one session: splitting them would allow a report
 * with no session behind it and a session that quietly never got written up,
 * and the second is the failure mode this system was built to remove.
 *
 * Named `therapy_sessions` rather than `sessions` because Laravel's database
 * session driver owns that table name. A collision here would be discovered
 * the first time someone flipped SESSION_DRIVER, in production.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('therapy_sessions', function (Blueprint $table) {
            $table->id();
            $table->string('number', 24)->unique();

            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->foreignId('enrollment_id')->constrained()->cascadeOnDelete();
            $table->foreignId('specialist_id')->nullable()->constrained('users')->nullOnDelete();

            /*
             * Copied from the enrolment rather than read through it. A child
             * moved between programmes must not silently rewrite what last
             * March's sessions were about.
             */
            $table->string('specialty')->index();

            $table->dateTime('scheduled_at')->index();
            $table->unsignedSmallInteger('duration_minutes')->default(45);

            /*
             * scheduled — in the diary, hasn't happened yet
             * held      — he came and was worked with
             * absent    — didn't come, no word from the family
             * excused   — didn't come, the family told us
             * cancelled — the academy called it off
             *
             * The three ways of not happening are kept apart because they mean
             * different things to different people: `absent` is the one the
             * office chases, `excused` is the one the parent already knows
             * about, and `cancelled` is the one the academy owes them a
             * replacement for.
             */
            $table->string('status')->default('scheduled')->index();
            $table->string('absence_reason')->nullable();

            /* ---- the report ------------------------------------------- */

            // كيف وصل اليوم — calm|happy|tired|agitated|crying|resistant
            $table->string('mood')->nullable();

            // The five named boxes. A single free textarea produces "تمت
            // الجلسة بنجاح" every day for a year; five questions get five
            // answers, and the parent reading them learns something.
            $table->text('activities')->nullable();      // شو عملنا اليوم
            $table->text('progress')->nullable();        // شو تطوّر
            $table->text('difficulties')->nullable();    // شو الصعوبات
            $table->text('home_plan')->nullable();       // شو بدنا منكم بالبيت

            /*
             * Hers. Never serialised for a guardian — the exclusion lives in
             * one method, TherapySession::forGuardian().
             *
             * A specialist with nowhere private to write "الأم ما بتطبّق
             * البرنامج بالبيت" will either write it where the mother reads it,
             * or not write it at all. The second is how a case file stops being
             * worth opening, and it is the quieter and likelier of the two.
             */
            $table->text('private_notes')->nullable();

            /*
             * draft     — being written; the family cannot see it exists
             * published — sent; from here it is append-only
             *
             * Publishing is a deliberate act and not a side effect of saving,
             * because a specialist types the first half of a report between two
             * children and finishes it at five o'clock — and a parent must not
             * be reading the half.
             */
            $table->string('report_status')->default('draft')->index();
            $table->timestamp('published_at')->nullable();

            $table->timestamps();
            $table->softDeletes();

            $table->index(['student_id', 'scheduled_at']);
            $table->index(['specialist_id', 'scheduled_at']);
            $table->index(['status', 'scheduled_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('therapy_sessions');
    }
};
