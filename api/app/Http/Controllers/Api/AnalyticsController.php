<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\Analytics;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * The analytics screen.
 *
 * A specialist sees her own caseload; the office sees the building. Same
 * figures, same code — the scope is one argument, so the two screens can never
 * drift into computing "attendance" two different ways.
 */
class AnalyticsController extends Controller
{
    public function __invoke(Request $request, Analytics $analytics): JsonResponse
    {
        $weeks = min(max((int) $request->query('weeks', 12), 4), 52);

        $user = $request->user();

        return response()->json([
            'data' => $analytics->overview(
                $weeks,
                $user->isAdmin() ? null : $user,
            ),
        ]);
    }
}
