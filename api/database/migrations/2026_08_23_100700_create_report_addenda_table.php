<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * التصحيح — what gets written when a published report was wrong.
 *
 * A published report is append-only. The specialist does not edit the
 * paragraph the mother read last night; she adds a dated line underneath it
 * saying what she got wrong. Both stay on the screen.
 *
 * The alternative — letting her fix the text in place — means a parent who
 * remembers reading something different has no way to be right, and the
 * academy has no way to prove it did not quietly change its story. That is a
 * bad position to be in with a family who is worried about their child, and it
 * costs one table to never be in it.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('report_addenda', function (Blueprint $table) {
            $table->id();
            $table->foreignId('therapy_session_id')->constrained()->cascadeOnDelete();
            $table->foreignId('author_id')->nullable()->constrained('users')->nullOnDelete();

            $table->text('body');

            $table->timestamps();

            $table->index(['therapy_session_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('report_addenda');
    }
};
