<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * A specialist who has left keeps her token until it expires, and it opens
 * every child's file in the building. Checking the flag on every request is
 * what makes "switch her off" immediate rather than eventual — and it revokes
 * the tokens so it stays that way.
 *
 * The last-seen stamp rides along here because this is the one place every
 * authenticated request passes through. It is written at most once a quarter
 * of an hour: a column update on every poll of the dashboard would turn a
 * read-heavy API into a write-heavy one for a number nobody reads to the
 * minute.
 */
class EnsureUserIsActive
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = $request->user();

        if ($user && ! $user->is_active) {
            $user->tokens()->delete();

            return response()->json(['message' => 'تم إيقاف هذا الحساب. راجع الإدارة.'], 403);
        }

        if ($user && (! $user->last_seen_at || $user->last_seen_at->diffInMinutes(now()) >= 15)) {
            $user->forceFill(['last_seen_at' => now()])->saveQuietly();
        }

        return $next($request);
    }
}
