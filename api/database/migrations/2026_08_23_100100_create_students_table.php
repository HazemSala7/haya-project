<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * الطالب — the child. Everything in this system hangs off one of these rows.
 *
 * Called a student and not a patient throughout, in the schema and on every
 * screen: a family that enrolled their son in an academy did not admit him to
 * a clinic, and the word they read back is part of what they were sold.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('students', function (Blueprint $table) {
            $table->id();

            // Human-facing and what everyone says out loud: "ملف ٢٦٠١٤".
            // Never the database id.
            $table->string('file_number', 24)->unique();

            $table->string('name');
            $table->date('birth_date');
            $table->string('gender', 8);           // male|female
            $table->string('national_id', 24)->nullable();

            $table->string('diagnosis')->nullable();
            $table->text('diagnosis_notes')->nullable();

            /*
             * The red band.
             *
             * Allergies, medication, seizure history — anything a specialist
             * must know before she is alone in a room with this child. It
             * renders across the top of every screen that shows him rather
             * than inside a notes tab, because a tab is opened once on
             * enrolment day and never again, and the day it matters is a day
             * nobody was expecting.
             *
             * Separate from `notes` for exactly that reason: mixing "he likes
             * trains" into the same box as "he is epileptic" means the second
             * gets skimmed at the speed of the first.
             */
            $table->text('medical_alert')->nullable();

            $table->string('school')->nullable();
            $table->string('grade', 40)->nullable();

            $table->date('enrolled_at');

            // active | paused | graduated | withdrawn
            $table->string('status')->default('active')->index();
            $table->date('left_at')->nullable();

            $table->text('notes')->nullable();

            $table->timestamps();

            // A child's file is never destroyed. Families come back after a
            // year away, and a deleted row takes his whole history with it.
            $table->softDeletes();

            $table->index(['status', 'name']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('students');
    }
};
