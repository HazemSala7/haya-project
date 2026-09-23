<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * A photo or a short video of the child doing the thing.
 *
 * Worth more to a parent than any paragraph on the screen above it. "بدأ يمسك
 * القلم لحاله" is a claim; twelve seconds of him holding the pencil is the
 * thing itself, and it is what makes a mother open tomorrow's report too.
 *
 * Files live on the private disk and are served by a route that checks the
 * viewer against the child's guardians — never by a public URL. A photograph
 * of a disabled child sitting on a guessable path is a leak waiting to be
 * indexed, and no amount of a long filename fixes that.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::create('session_attachments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('therapy_session_id')->constrained()->cascadeOnDelete();
            $table->foreignId('uploaded_by')->nullable()->constrained('users')->nullOnDelete();

            $table->string('path');
            $table->string('original_name');
            $table->string('mime', 128);
            $table->unsignedInteger('size');

            // "أول مرة يمسك المقص لحاله" — the line under the photo. Without
            // it a parent gets a wall of images and has to guess which moment
            // was the one worth filming.
            $table->string('caption')->nullable();

            $table->timestamps();

            $table->index('therapy_session_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('session_attachments');
    }
};
