<?php

use App\Exceptions\OperationRefused;
use App\Http\Middleware\EnsureUserHasRole;
use App\Http\Middleware\EnsureUserIsActive;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
        /*
         * Locally the API lives at /api/… and the default is right.
         *
         * On the shared host, Laravel's public directory is itself mounted at
         * /haya/api inside the document root, so Apache consumes the segment
         * before Laravel sees the request. The deployed front controller
         * empties this — and it must come from the real process environment,
         * because this file runs *before* .env is read.
         */
        apiPrefix: env('API_PREFIX', 'api'),
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->alias([
            'role' => EnsureUserHasRole::class,
            'active' => EnsureUserIsActive::class,
        ]);

        /*
         * There is no login page to send a guest to — the dashboard is a
         * separate static build on another path entirely.
         *
         * Laravel's default is `fn () => route('login')`, and the Authenticate
         * middleware evaluates it while *building* the AuthenticationException:
         *
         *     throw new AuthenticationException(
         *         'Unauthenticated.', $guards,
         *         $request->expectsJson() ? null : $this->redirectTo($request),
         *     );
         *
         * So on any request that does not announce `Accept: application/json`,
         * `route('login')` throws RouteNotFoundException *before* the
         * AuthenticationException exists — and the 401 renderer below never
         * runs, because there is no AuthenticationException to catch. The
         * caller gets a 500 and a log line reading "Route [login] not defined"
         * that says nothing about the real problem, which is that they simply
         * were not signed in.
         *
         * Returning null puts it back on the honest path: the exception is
         * thrown, the renderer answers 401 in JSON, every time.
         */
        $middleware->redirectGuestsTo(fn () => null);
    })
    /*
    |--------------------------------------------------------------------------
    | Errors
    |--------------------------------------------------------------------------
    |
    | Every handler below answers unconditionally. There is no `is('api/*')`
    | guard and no `expectsJson()` check, because this application serves
    | nothing but the API — the dashboard is a separate static build.
    |
    | The guard used to be there and was worse than useless. On the server,
    | Apache consumes `/haya/api` by serving that directory, so Laravel sees
    | the path as `students`, and `is('api/*')` is false for every request the
    | application will ever receive. Locally the path really is `api/students`,
    | so it looked correct right up until it was deployed — where a request
    | without an `Accept: application/json` header fell through to Laravel's
    | redirect-to-login and returned 500 instead of 401.
    |
    */
    ->withExceptions(function (Exceptions $exceptions): void {
        // No login page to redirect to — an unauthenticated call comes back as
        // JSON 401 so the frontend can clear its token.
        $exceptions->render(function (AuthenticationException $e) {
            return response()->json([
                'message' => 'انتهت الجلسة. سجّل الدخول مرة أخرى.',
            ], 401);
        });

        /*
         * The service layer refuses things it understands — publishing an
         * empty report, rewriting one a mother has already read — with a
         * message written for the specialist. 422 puts it on her screen
         * instead of a 500 nobody can act on.
         *
         * Deliberately NOT registered on RuntimeException: Symfony's
         * NotFoundHttpException extends it, and this renderer would then turn
         * every 404 into a 422 carrying an internal message.
         */
        $exceptions->render(function (OperationRefused $e) {
            return response()->json(['message' => $e->getMessage()], 422);
        });

        $exceptions->render(function (ModelNotFoundException $e) {
            return response()->json(['message' => 'العنصر المطلوب غير موجود.'], 404);
        });

        $exceptions->render(function (NotFoundHttpException $e) {
            return response()->json(['message' => 'العنصر المطلوب غير موجود.'], 404);
        });
    })->create();
