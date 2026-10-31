<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;

/**
 * Schema upgrades on a host with no terminal.
 *
 * ---------------------------------------------------------------------------
 * WHY THIS EXISTS AT ALL
 *
 * The academy runs on shared cPanel hosting. There is no SSH, no terminal and
 * no cron that a deploy can reach — the only doors are FTP and HTTPS. So when
 * a release adds a table, there are exactly two options: ship code whose
 * migrations can never run, or open one door and guard it properly.
 *
 * A guarded door is the better of the two. Code that reads a column the
 * database does not have is not "safe because nobody can migrate"; it is a
 * dashboard answering 500 to the office, with the fix on the far side of the
 * thing that is broken.
 *
 * ---------------------------------------------------------------------------
 * HOW IT IS GUARDED
 *
 * - A key file, placed on the server by hand and nowhere in this repository.
 *   No file, no endpoint: both routes answer 404, which is what they do on
 *   every developer machine and on the server any day nobody is deploying.
 * - `role:admin` on top of it, inherited from the route group, so the key is
 *   not a password on its own — it has to arrive with a signed-in office
 *   token.
 * - Compared with `hash_equals`, so a wrong key cannot be narrowed down by
 *   timing the answer.
 * - Throttled, because nothing here is worth calling twice a second and a
 *   loop of migrations is a good way to take a shared host down.
 *
 * A file rather than a line in `.env` for two reasons. Adding the secret does
 * not mean editing the one file on the server that holds the database
 * password — a file whose truncation takes the academy offline. And removal
 * is a deletion rather than another edit, so the normal state of the server
 * is one where this endpoint does not exist: it is opened for the minutes a
 * migration takes and shut again, instead of standing open between releases
 * because nobody remembered it was there.
 *
 * ---------------------------------------------------------------------------
 * WHAT IT DELIBERATELY CANNOT DO
 *
 * It takes no input beyond the key. Not a command name, not a flag, not a
 * path — nothing a caller could bend into running something else. There is
 * one fixed operation: bring the schema forward. In particular there is no
 * `--fresh` and no `--seed`, because those two flags are the difference
 * between "upgrade the database" and "delete every child in it", and that
 * difference must not live one boolean away from a public URL. Dropping data
 * stays a job for somebody who can see what they are dropping.
 */
class MaintenanceController extends Controller
{
    /**
     * Where the key is looked for.
     *
     * Inside `storage/`, which the deploy never uploads and never deletes —
     * so a release cannot overwrite it, and cannot carry a copy of it up from
     * a laptop either. The whole `_app/` directory is behind `.htaccess` and
     * is not reachable over HTTP; `live-check.mjs` asserts that on every run.
     */
    private function keyFile(): string
    {
        return storage_path('maintenance.key');
    }

    /**
     * What is out of date, without changing anything.
     *
     * Read first, migrate second. On a host where the run cannot be watched
     * while it happens and cannot be undone afterwards, knowing in advance
     * which files are pending is most of the safety there is.
     */
    public function status(Request $request): JsonResponse
    {
        $this->authorizeKey($request);

        return response()->json([
            'data' => [
                'connection' => DB::connection()->getName(),
                'database' => DB::connection()->getDatabaseName(),
                'pending' => $this->pending(),
            ],
        ]);
    }

    /**
     * Bring the database forward.
     *
     * Artisan's own output is returned verbatim. It is the only way to see
     * what happened — there is no console to watch — and a migration that
     * half ran needs to be readable afterwards rather than guessed at.
     */
    public function migrate(Request $request): JsonResponse
    {
        $this->authorizeKey($request);

        $before = $this->pending();

        Artisan::call('migrate', ['--force' => true]);

        return response()->json([
            'data' => [
                'ran' => $before,
                'output' => trim(Artisan::output()),
                'pending' => $this->pending(),
            ],
        ]);
    }

    /**
     * The key, or this endpoint was never here.
     *
     * 404 rather than 403, and the same 404 whether the file is absent or the
     * header is wrong — so probing cannot separate "no such route" from
     * "right route, wrong secret".
     */
    private function authorizeKey(Request $request): void
    {
        $file = $this->keyFile();
        $expected = is_readable($file) ? trim((string) file_get_contents($file)) : '';
        $given = trim((string) $request->header('X-Maintenance-Key'));

        abort_if($expected === '' || ! hash_equals($expected, $given), 404);
    }

    /**
     * Migration files on disk that this database has not recorded running.
     *
     * Compared by filename against the `migrations` table rather than by
     * asking the migrator for its own list, so the answer is a plain reading
     * of the two sides and not a second code path that could disagree with
     * what `migrate` is about to do.
     *
     * @return array<int, string>
     */
    private function pending(): array
    {
        $onDisk = collect(glob(database_path('migrations').'/*.php'))
            ->map(fn (string $file) => basename($file, '.php'))
            ->values();

        try {
            $ran = collect(DB::table('migrations')->pluck('migration'));
        } catch (\Throwable) {
            // No migrations table at all means nothing has ever run here.
            $ran = collect();
        }

        return $onDisk->diff($ran)->values()->all();
    }
}
