<?php

use App\Http\Controllers\Api\AnalyticsController;
use App\Http\Controllers\Api\AttachmentController;
use App\Http\Controllers\Api\AuthController;
use App\Http\Controllers\Api\BillingController;
use App\Http\Controllers\Api\DashboardController;
use App\Http\Controllers\Api\EnrollmentController;
use App\Http\Controllers\Api\GoalController;
use App\Http\Controllers\Api\MaintenanceController;
use App\Http\Controllers\Api\MessageController;
use App\Http\Controllers\Api\NavCountsController;
use App\Http\Controllers\Api\ProgressReportController;
use App\Http\Controllers\Api\SessionController;
use App\Http\Controllers\Api\StaffController;
use App\Http\Controllers\Api\StudentController;
use App\Http\Controllers\Api\SyncController;
use Illuminate\Support\Facades\Route;

Route::post('auth/login', [AuthController::class, 'login']);

/*
|--------------------------------------------------------------------------
| المزامنة من النظام القديم
|--------------------------------------------------------------------------
|
| يدفع `tools/zaid-sync/haya_sync.php` من استضافة qadrs.com إلى هنا. خارج
| `auth:sanctum` لأن الطارق مهمّة cron لا شخص — وحسابُ مستخدمٍ لمهمّةٍ مجدولة
| هو حسابٌ يستطيع تسجيل الدخول من متصفّح بلا سبب.
|
| الحارس توكنٌ واحد مخزَّن مُلبَّداً، وبلا توكنٍ مضبوط يردّ الباب ٤٠٤ كأنه غير
| موجود. والخنق لأن جولةً كاملة عشرات الطلبات المشروعة، لا آلاف.
*/
Route::middleware('throttle:120,1')->post('sync/zaid', [SyncController::class, 'receive']);

Route::middleware(['auth:sanctum', 'active'])->group(function () {
    Route::get('auth/me', [AuthController::class, 'me']);
    Route::post('auth/logout', [AuthController::class, 'logout']);
    Route::post('auth/password', [AuthController::class, 'changePassword']);

    /*
     * Closing your own account, from inside the app.
     *
     * Required by both stores of any app that holds accounts, and the preview
     * is not decoration: what deletion means differs between a parent and a
     * specialist whose name is signed on reports families have read, and the
     * screen prints the server's answer rather than guessing at it.
     */
    Route::get('auth/account', [AuthController::class, 'accountPreview']);
    Route::delete('auth/account', [AuthController::class, 'deleteAccount']);

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

    /*
     * One child's account — the only part of the billing module a parent
     * sees, and only for their own child. The gate is Student::readableBy,
     * the same one every other student endpoint uses, and it answers 404 so
     * that changing the id cannot be used to learn which children exist.
     */
    Route::get('billing/students/{student}', [BillingController::class, 'student'])->whereNumber('student');

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

        /*
         * المزامنة — ما وصل ومتى، وتوليد التوكن.
         *
         * `rotate` يولّد ويعرض مرّة واحدة: سرٌّ يمكن عرضه متى شئت هو سرٌّ
         * يبقى في لقطات الشاشة.
         */
        Route::get('sync/status', [SyncController::class, 'status']);
        Route::post('sync/token', [SyncController::class, 'rotate']);
        Route::delete('sync/token', [SyncController::class, 'disable']);

        /*
        |----------------------------------------------------------------------
        | The money
        |----------------------------------------------------------------------
        |
        | A monthly subscription per child, due on the first. Behind the office
        | wall entirely: a specialist who knows which family has not paid is a
        | specialist with a reason to treat two children differently.
        |
        | Issuing is a button, not a clock — there is no scheduler on this host
        | — and pressing it twice charges nobody twice. See App\Services\Billing.
        */
        Route::get('billing/invoices', [BillingController::class, 'index']);
        Route::get('billing/summary', [BillingController::class, 'summary']);

        // The agreed monthly fee, on its own — the billing screen prices a
        // child from a name and an id. See BillingController::fee.
        Route::put('students/{student}/fee', [BillingController::class, 'fee'])->whereNumber('student');

        Route::post('billing/issue', [BillingController::class, 'issue']);
        Route::get('billing/invoices/{invoice}', [BillingController::class, 'show'])->whereNumber('invoice');
        Route::put('billing/invoices/{invoice}', [BillingController::class, 'update'])->whereNumber('invoice');
        Route::delete('billing/invoices/{invoice}', [BillingController::class, 'destroy'])->whereNumber('invoice');

        Route::post('billing/invoices/{invoice}/pay', [BillingController::class, 'pay'])->whereNumber('invoice');
        Route::delete('billing/payments/{payment}', [BillingController::class, 'removePayment'])->whereNumber('payment');

        /*
        |----------------------------------------------------------------------
        | Maintenance
        |----------------------------------------------------------------------
        |
        | Schema upgrades, on a host with no terminal to run them from. There
        | is no SSH here and no cron a deploy can reach, so a release whose
        | migrations cannot run is a release that answers 500 to the office.
        |
        | Behind the office wall AND behind a key file placed on the server by
        | hand for the minutes a migration takes — without it both answer 404,
        | which is what they do on every developer machine and on the server
        | itself any day nobody is deploying. See MaintenanceController for
        | why the missing input is the security model and not an oversight.
        |
        | Throttled: a loop of migrations is a good way to take a shared host
        | down, and nobody needs to run one twice a second. Twelve a minute
        | rather than a handful because a release legitimately spends several
        | — status, migrate, status again — and the smoke test spends five
        | more proving the door is shut; a ceiling that a correct deploy can
        | hit is a ceiling people learn to work around.
        */
        Route::middleware('throttle:12,1')->group(function () {
            Route::get('maintenance/status', [MaintenanceController::class, 'status']);
            Route::post('maintenance/migrate', [MaintenanceController::class, 'migrate']);
        });
    });
});
