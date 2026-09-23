<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * التقرير الدوري — the arc, where the daily reports are the frames.
 *
 * A parent reading twenty-four session reports knows what happened on
 * twenty-four days and still cannot answer "is this working?". That question
 * is asked at the school, at the doctor, and by the grandmother — and it needs
 * a document, written by the specialist, that says where the child started,
 * where he is, and what the next quarter is for.
 *
 * It is the one thing families take outside the academy, so it is the one
 * thing that gets printed.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('progress_reports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();

            // Nullable: a joint report covering everything the child does here
            // is written by the admin across all four programmes.
            $table->foreignId('enrollment_id')->nullable()->constrained()->nullOnDelete();

            $table->foreignId('author_id')->nullable()->constrained('users')->nullOnDelete();

            $table->date('period_start');
            $table->date('period_end');

            $table->text('summary');                        // أين هو الآن
            $table->text('achieved')->nullable();           // ما أُنجز في الفترة
            $table->text('recommendations')->nullable();    // التوصيات
            $table->text('home_program')->nullable();       // البرنامج المنزلي

            // Same two states as a session report, for the same reason.
            $table->string('status')->default('draft')->index();
            $table->timestamp('published_at')->nullable();

            $table->timestamps();

            $table->index(['student_id', 'period_end']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('progress_reports');
    }
};
