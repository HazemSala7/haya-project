<?php

use App\Http\Controllers\Api\AnalyticsController;
use App\Http\Controllers\Api\AttachmentController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\EnrollmentController;
use App\Http\Controllers\Api\GoalController;
use App\Http\Controllers\Api\MessageController;
use App\Http\Controllers\Api\NavCountsController;
use App\Http\Controllers\Api\ProgressReportController;
use App\Http\Controllers\Api\SessionController;
use App\Http\Controllers\Api\StaffController;
use App\Http\Controllers\Api\StudentController;
use Illuminate\Support\Facades\Route;

Route::post('auth/login', [AuthController::class, 'login']);

Route::middleware(['auth:sanctum', 'active'])->group(function () {
    Route::get('auth/me', [AuthController::class, 'me']);
    Route::post('auth/logout', [AuthController::class, 'logout']);
    Route::post('auth/password', [AuthController::class, 'changePassword']);

    // Three different screens behind one path — see DashboardController.
    Route::get('dashboard', DashboardController::class);

    // The numbers beside the menu items. Every role has its own set.
    Route::get('nav-counts', NavCountsController::class);

    /*
    |--------------------------------------------------------------------------
    | Everyone who is signed in
    |--------------------------------------------------------------------------
    |
    | Reading a child's file, their sessions, their goals, the thread about
    | them. A guardian reaches all of these — and sees only their own children
    | in every one of them, because the scope is on the query and not on the
    | route. See Student::visibleTo and TherapySession::visibleTo.
    |
    */

    Route::get('students', [StudentController::class, 'index']);
    Route::get('students/{student}', [StudentController::class, 'show'])->whereNumber('student');

    Route::get('sessions', [SessionController::class, 'index']);
    Route::get('sessions/{session}', [SessionController::class, 'show'])->whereNumber('session');

    Route::get('goals', [GoalController::class, 'index']);
    Route::get('goals/{goal}', [GoalController::class, 'show'])->whereNumber('goal');

    Route::get('progress-reports', [ProgressReportController::class, 'index']);
    Route::get('progress-reports/figures', [ProgressReportController::class, 'figures']);
    Route::get('progress-reports/{report}', [ProgressReportController::class, 'show'])->whereNumber('report');

    Route::get('students/{student}/messages', [MessageController::class, 'index'])->whereNumber('student');
    Route::post('students/{student}/messages', [MessageController::class, 'store'])->whereNumber('student');
    Route::get('messages/unread', [MessageController::class, 'unread']);

    // Streamed after the same visibility check the session itself gets.
    Route::get('attachments/{attachment}', [AttachmentController::class, 'show'])->whereNumber('attachment');

    /*
    |--------------------------------------------------------------------------
    | The therapy rooms
    |--------------------------------------------------------------------------
    |
    | Writing on a child's file. A guardian reads; she does not write — the one
    | thing a family may add is a message, which is above.
    |
    | Within this group the second gate is per-record, not per-route:
    | User::mayWriteOn allows the assigned specialist and the admin, so two
    | specialists cannot write on each other's sessions even though both are
    | standing at the same door.
    |
    */

    Route::middleware('role:admin,specialist')->group(function () {
        // Scoped inside the controller: her caseload, or the whole building.
        Route::get('analytics', AnalyticsController::class);

        Route::post('sessions', [SessionController::class, 'store']);
        Route::put('sessions/{session}', [SessionController::class, 'update'])->whereNumber('session');
        Route::delete('sessions/{session}', [SessionController::class, 'destroy'])->whereNumber('session');

        Route::post('sessions/{session}/attendance', [SessionController::class, 'attendance'])->whereNumber('session');
        Route::post('sessions/{session}/ratings', [SessionController::class, 'rate'])->whereNumber('session');
        Route::post('sessions/{session}/publish', [SessionController::class, 'publish'])->whereNumber('session');
        Route::post('sessions/{session}/addendum', [SessionController::class, 'addendum'])->whereNumber('session');

        Route::post('sessions/{session}/attachments', [AttachmentController::class, 'store'])->whereNumber('session');
        Route::delete('attachments/{attachment}', [AttachmentController::class, 'destroy'])->whereNumber('attachment');

        Route::post('goals', [GoalController::class, 'store']);
        Route::put('goals/{goal}', [GoalController::class, 'update'])->whereNumber('goal');
        Route::delete('goals/{goal}', [GoalController::class, 'destroy'])->whereNumber('goal');

        Route::get('enrollments', [EnrollmentController::class, 'index']);
        Route::put('enrollments/{enrollment}', [EnrollmentController::class, 'update'])->whereNumber('enrollment');

        Route::post('progress-reports', [ProgressReportController::class, 'store']);
        Route::put('progress-reports/{report}', [ProgressReportController::class, 'update'])->whereNumber('report');
        Route::post('progress-reports/{report}/publish', [ProgressReportController::class, 'publish'])->whereNumber('report');
        Route::delete('progress-reports/{report}', [ProgressReportController::class, 'destroy'])->whereNumber('report');
    });

    /*
    |--------------------------------------------------------------------------
    | The office
    |--------------------------------------------------------------------------
    |
    | Who is enrolled, who they belong to, who works here. A specialist writes
    | the therapy; she does not decide which children are in the building or
    | which family holds a login to which file.
    |
    */

    Route::middleware('role:admin')->group(function () {
        Route::post('students', [StudentController::class, 'store']);
        Route::put('students/{student}', [StudentController::class, 'update'])->whereNumber('student');
        Route::delete('students/{student}', [StudentController::class, 'destroy'])->whereNumber('student');
        Route::post('students/{student}/restore', [StudentController::class, 'restore'])->whereNumber('student');

        Route::post('students/{student}/guardians', [StudentController::class, 'attachGuardian'])->whereNumber('student');
        Route::delete('students/{student}/guardians/{user}', [StudentController::class, 'detachGuardian'])
            ->whereNumber(['student', 'user']);

        Route::post('enrollments', [EnrollmentController::class, 'store']);
        Route::delete('enrollments/{enrollment}', [EnrollmentController::class, 'destroy'])->whereNumber('enrollment');

        Route::get('staff', [StaffController::class, 'index']);
        Route::post('staff', [StaffController::class, 'store']);
        Route::put('staff/{user}', [StaffController::class, 'update'])->whereNumber('user');
        Route::delete('staff/{user}', [StaffController::class, 'destroy'])->whereNumber('user');
        Route::post('staff/{user}/password', [StaffController::class, 'resetPassword'])->whereNumber('user');
        Route::get('staff/{user}/children', [StaffController::class, 'children'])->whereNumber('user');

        Route::get('settings', [StaffController::class, 'settings']);
        Route::put('settings', [StaffController::class, 'updateSettings']);
    });
});
