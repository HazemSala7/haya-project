<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * What the specialist reached for.
 *
 * The report already says what they did (`activities`), how he responded
 * (`mood`, the goal ratings) and what the family should carry on with
 * (`home_plan`). What it never recorded is the one thing another specialist
 * needs when she covers the session next week: which cards, which board, which
 * app — «بطاقات PECS، مرآة، صور متسلسلة».
 *
 * Its own column rather than a sentence inside `activities`, because it is
 * read on its own: a parent asked to practise at home wants the name of the
 * thing, and the academy asked what it owns wants the list.
 *
 * Free text, not a catalogue. A rehabilitation academy's tools are half
 * bought and half made that morning out of card, and a dropdown of the bought
 * half would quietly stop the made half from ever being written down.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('therapy_sessions', function (Blueprint $table) {
            $table->text('tools')->nullable()->after('activities');
        });
    }

    public function down(): void
    {
        Schema::table('therapy_sessions', function (Blueprint $table) {
            $table->dropColumn('tools');
        });
    }
};
