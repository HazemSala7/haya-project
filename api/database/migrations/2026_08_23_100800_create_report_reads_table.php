<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * Who opened the report, and when.
 *
 * Recorded so the specialist can see it — not so the parent can be blamed for
 * it. The academy writes a detailed report every session at real cost, and
 * without this row it never finds out that one family has not opened a single
 * one since October. That is a conversation to have, and it cannot be had by
 * a system that only measures what it sent.
 *
 * Per user rather than per family: the father reading it does not mean the
 * mother did, and in the families where that distinction matters it matters a
 * great deal.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('report_reads', function (Blueprint $table) {
            $table->id();
            $table->foreignId('therapy_session_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();

            // First open, not last. "She has seen it" is the fact worth
            // keeping; re-reads are not evidence of anything.
            $table->timestamp('read_at')->useCurrent();

            $table->unique(['therapy_session_id', 'user_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('report_reads');
    }
};
