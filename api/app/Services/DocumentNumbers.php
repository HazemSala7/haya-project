<?php

namespace App\Services;

use App\Models\Student;
use App\Models\TherapySession;
use Illuminate\Support\Facades\DB;

/**
 * The numbers people say out loud: ملف ٢٦-٠١٤، جلسة JS-260823-007.
 *
 * A file number is per year and a session number is per day, because that is
 * the unit each is spoken in — "الملف اللي فتحناه هاي السنة" and "جلسة
 * الصبح". The database id is never shown: it leaks how many children the
 * academy has ever taken, and it cannot be reset or carried across a move.
 *
 * Both counts are taken with a locking read inside a transaction, so two
 * people registering a child in the same second cannot claim the same file.
 * The unique index on the column is the second line of defence, not the first.
 */
class DocumentNumbers
{
    /**
     * الملف — one sequence per year: 26-014.
     *
     * Deliberately short. It is written by hand on a paper folder, read down a
     * phone line, and typed into the search box by someone holding a child's
     * hand with the other arm.
     */
    public function studentFile(): string
    {
        $stem = now()->format('y').'-';

        return DB::transaction(function () use ($stem) {
            $last = Student::withTrashed()
                ->where('file_number', 'like', $stem.'%')
                ->lockForUpdate()
                ->orderByDesc('file_number')
                ->value('file_number');

            $sequence = $last ? ((int) substr($last, strlen($stem))) + 1 : 1;

            return $stem.str_pad((string) $sequence, 3, '0', STR_PAD_LEFT);
        });
    }

    /** الجلسة — per day, like every other document in the building. */
    public function session(): string
    {
        $stem = 'JS-'.now()->format('ymd').'-';

        return DB::transaction(function () use ($stem) {
            $last = TherapySession::withTrashed()
                ->where('number', 'like', $stem.'%')
                ->lockForUpdate()
                ->orderByDesc('number')
                ->value('number');

            $sequence = $last ? ((int) substr($last, strlen($stem))) + 1 : 1;

            return $stem.str_pad((string) $sequence, 3, '0', STR_PAD_LEFT);
        });
    }
}
