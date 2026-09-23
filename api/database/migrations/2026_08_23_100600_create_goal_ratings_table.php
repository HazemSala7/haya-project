<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What the child scored on one goal in one session.
 *
 * This is the smallest and most important table in the system. Everything a
 * parent is asked to believe about their child's progress is drawn from this
 * column, which is why it is a number on a fixed scale and not a sentence.
 *
 * See App\Enums\PromptLevel for what 0..4 mean and why the boundaries are
 * spelled out — two specialists rating the same child on a scale they each
 * interpret differently makes every curve drawn from it fiction.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('goal_ratings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('therapy_session_id')->constrained()->cascadeOnDelete();
            $table->foreignId('goal_id')->constrained()->cascadeOnDelete();

            // 4 مستقل · 3 تلميح لفظي · 2 مساعدة جزئية · 1 مساعدة كاملة · 0 رفض
            $table->unsignedTinyInteger('level');

            /*
             * Optional, and only where the goal is countable — "٧ من ١٠
             * محاولات". The prompt level says how much help he needed; the
             * trials say how often it worked. A goal can sit at "verbal prompt"
             * for a month while the hit rate climbs from 3/10 to 9/10, and
             * without these two columns that month looks like a flat line.
             */
            $table->unsignedSmallInteger('trials')->nullable();
            $table->unsignedSmallInteger('successes')->nullable();

            $table->string('note')->nullable();

            $table->timestamps();

            // One score per goal per session — a second one is a correction of
            // the first, not another data point.
            $table->unique(['therapy_session_id', 'goal_id']);
            $table->index(['goal_id', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('goal_ratings');
    }
};
