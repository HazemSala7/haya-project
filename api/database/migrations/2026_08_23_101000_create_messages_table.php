<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The conversation about one child.
 *
 * One flat thread per student rather than a mailbox per pair of people. A
 * mother does not think "I will message the occupational therapist" — she
 * thinks "I want to ask about Yousef", and everyone working on Yousef should
 * see the answer. It also means a specialist picking up a case in March can
 * read what the family has been saying since September, which a private inbox
 * would have taken with the therapist who left.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('messages', function (Blueprint $table) {
            $table->id();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->foreignId('sender_id')->constrained('users')->cascadeOnDelete();

            /*
             * Set when a parent taps "اسأل عن هذه الجلسة" on a report.
             *
             * The question then arrives attached to the day it is about,
             * instead of as a bare "شو صار امبارح؟" that the specialist has to
             * go and reconstruct.
             */
            $table->foreignId('therapy_session_id')->nullable()->constrained()->nullOnDelete();

            $table->text('body');

            // Null until someone on the other side has opened the thread.
            $table->timestamp('read_at')->nullable();

            $table->timestamps();

            $table->index(['student_id', 'created_at']);
            $table->index(['student_id', 'read_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('messages');
    }
};
