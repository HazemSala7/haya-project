<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The office, the specialists and the parents share one table.
 *
 * They share it because they share exactly one thing — a login. Giving
 * guardians their own table would mean a second authentication path, a second
 * password reset, and a second place where "is this account switched off?"
 * can be answered differently from the first.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->string('role')->default('specialist')->after('password')->index();
            $table->string('phone', 32)->nullable()->after('role');

            /*
             * Only ever set on a specialist: which of the four programmes she
             * is qualified for. Null on an admin and on a guardian — a nullable
             * column rather than a join table, because it is one fact about one
             * person and reading it happens on every screen she appears on.
             */
            $table->string('specialty')->nullable()->after('phone');

            // "أخصائية نطق ولغة" — printed under her name on every report a
            // parent reads, so it is hers to write rather than derived from
            // the specialty. Two speech therapists do not hold the same
            // qualification.
            $table->string('title')->nullable()->after('specialty');

            $table->boolean('is_active')->default(true)->after('title');

            /*
             * Shown to the office as "آخر دخول". An account nobody has opened
             * in three months is either someone who left or a password nobody
             * remembers — and for a guardian account it is the early warning
             * that the family stopped reading, which is the failure this whole
             * system is built to prevent.
             */
            $table->timestamp('last_seen_at')->nullable()->after('is_active');
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn([
                'role', 'phone', 'specialty', 'title', 'is_active', 'last_seen_at',
            ]);
        });
    }
};
