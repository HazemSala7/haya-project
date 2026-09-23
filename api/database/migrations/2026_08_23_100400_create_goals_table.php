<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * الهدف العلاجي — one specific thing this child cannot yet do on his own.
 *
 * Goals are written narrow on purpose: "ينطق /س/ في بداية الكلمة", not
 * "تحسين النطق". A wide goal can never be scored, never be finished, and never
 * be shown to a parent as anything but a shrug — and a plan made of wide goals
 * is a plan that runs for three years without anyone able to say whether it
 * worked.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('goals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();
            $table->foreignId('enrollment_id')->constrained()->cascadeOnDelete();

            $table->string('title');
            $table->text('description')->nullable();

            /*
             * "٨ من ١٠ محاولات في ٣ جلسات متتالية".
             *
             * Written down when the goal is opened, before anyone knows whether
             * it will be met — so "achieved" is a line that was crossed and not
             * a specialist's mood on the day she closed it.
             */
            $table->string('criteria')->nullable();

            /*
             * Where he was on day one, on the same 0..4 prompt scale the
             * sessions score against.
             *
             * Without it the first rating IS the baseline, and a parent opening
             * the curve sees it start wherever the first session happened to
             * land — with no distance travelled to show for the months since.
             */
            $table->unsignedTinyInteger('baseline')->default(0);
            $table->unsignedTinyInteger('target')->default(4);

            // active | achieved | paused | dropped
            $table->string('status')->default('active')->index();

            $table->date('started_at');
            $table->date('achieved_at')->nullable();

            // The order the specialist works them in, which is not the order
            // she happened to type them in.
            $table->unsignedSmallInteger('sort_order')->default(0);

            $table->timestamps();

            $table->index(['student_id', 'status']);
            $table->index(['enrollment_id', 'status']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('goals');
    }
};
