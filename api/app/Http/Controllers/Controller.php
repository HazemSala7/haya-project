<?php

namespace App\Http\Controllers;

use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

abstract class Controller
{
    /**
     * One response shape for the whole API: `{ data, meta }`.
     *
     * Laravel serialises a paginator with its counts spread across the top
     * level, so a paginated endpoint and a plain one answer with two different
     * envelopes and every caller has to know which is which. The links block
     * goes with it: those are page numbers the caller already has, wrapped in
     * absolute URLs that break the moment the app is mounted somewhere else.
     *
     * @param  array<string, mixed>  $meta
     */
    protected function paginated(LengthAwarePaginator $page, array $meta = []): JsonResponse
    {
        return response()->json([
            'data' => $page->items(),
            'meta' => [
                'total' => $page->total(),
                'per_page' => $page->perPage(),
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'from' => $page->firstItem(),
                'to' => $page->lastItem(),
                ...$meta,
            ],
        ]);
    }

    /** Capped so a caller cannot ask for the whole table in one request. */
    protected function perPage(Request $request, int $default = 25): int
    {
        return min(max((int) $request->query('per_page', $default), 1), 100);
    }
}
