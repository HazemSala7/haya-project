<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * `role:admin,specialist` on a route.
 *
 * Deliberately a middleware rather than a check inside each controller: a
 * permission that has to be remembered in twelve places is a permission that
 * will be forgotten in one — and here the one it is forgotten in shows a
 * stranger a disabled child's file.
 */
class EnsureUserHasRole
{
    public function handle(Request $request, Closure $next, string ...$roles): Response
    {
        $user = $request->user();

        if (! $user || ! in_array($user->role->value, $roles, true)) {
            return response()->json([
                'message' => 'لا تملك صلاحية للوصول إلى هذه الصفحة.',
            ], 403);
        }

        return $next($request);
    }
}
