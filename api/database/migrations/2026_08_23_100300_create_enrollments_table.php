<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * الالتحاق ببرنامج — this child, in this programme, with this specialist.
 *
 * The row exists because a child is very often in more than one programme at
 * once: speech twice a week with one therapist and occupational once a week
 * with another, each with her own goals and her own reports. Hanging the
 * specialty off the student instead would force that child to be two students,
 * and then his medical alert lives in two places and one of them is stale.
 *
 * It is also what the goals, the sessions and the periodic reports all point
 * at — so "how is he doing in speech?" is a question with a row to ask it of.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('enrollments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();

            $table->string('specialty')->index();

            /*
             * Nullable, and deliberately.
             *
             * A therapist leaves in March and her fourteen children must not
             * become unreachable rows. They become unassigned rows — which is
             * a queue the office can see and empty, rather than a silent
             * orphaning nobody notices until a parent calls.
             */
            $table->foreignId('specialist_id')->nullable()->constrained('users')->nullOnDelete();

            $table->unsignedTinyInteger('sessions_per_week')->default(2);
            $table->unsignedSmallInteger('session_minutes')->default(45);

            $table->date('started_at');
            $table->date('ended_at')->nullable();

            // active | paused | ended
            $table->string('status')->default('active')->index();

            // ملخّص الخطة العلاجية — the paragraph that says where this
            // programme is heading. The goals below it say how it will be known.
            $table->text('plan_summary')->nullable();

            $table->timestamps();

            /*
             * Indexed, not unique.
             *
             * "One live programme of a kind per child" is a real rule and it is
             * enforced in EnrollmentController — but it cannot be a unique key
             * here, because a child who did speech in 2024, stopped, and came
             * back in 2026 legitimately has two ended rows plus a live one, and
             * a unique index on (student, specialty, status) would reject the
             * second ending.
             */
            $table->index(['student_id', 'specialty', 'status']);
            $table->index(['specialist_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('enrollments');
    }
};
