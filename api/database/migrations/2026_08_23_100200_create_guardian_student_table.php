<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Which family reads which child's file.
 *
 * Many-to-many in both directions, and both directions are real: a mother and
 * a father each want their own login rather than sharing one — they do not
 * live in the same house in every case — and a family with two children in the
 * academy wants one login that opens both.
 *
 * This table is also the entire privacy model. Every guardian-facing query is
 * scoped through it in one place (`Student::visibleTo`), so "can this parent
 * see this child?" has exactly one answer and it is not re-derived per screen.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('guardian_student', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();

            // father | mother | grandparent | sibling | guardian
            $table->string('relation', 32)->default('guardian');

            /*
             * Who the academy phones first.
             *
             * On the link and not on the user, because a father can be the
             * first contact for one of his children and the mother for
             * another — and in a separated family that distinction is the
             * whole reason the field exists.
             */
            $table->boolean('is_primary')->default(false);

            $table->timestamps();

            $table->unique(['user_id', 'student_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('guardian_student');
    }
};
