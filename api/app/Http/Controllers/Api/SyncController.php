<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Setting;
use App\Models\SyncRun;
use App\Services\ZaidSync;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;

/**
 * الباب الذي يدفع منه النظام القديم.
 *
 * ## لماذا ليس خلف `auth:sanctum`
 *
 * الذي يطرق هنا ليس شخصاً — هو مهمّة cron على خادمٍ آخر. ولا يُفتح له حساب
 * مستخدم: حسابٌ له كلمة مرور وجلسة ودورٌ هو حسابٌ يمكن أن يسجّل الدخول من
 * متصفّح، ومهمّةٌ مجدولة لا تحتاج شيئاً من ذلك. فـtoken واحد، يُقارَن
 * بـ`hash_equals`، ويُدوَّر بزرّ.
 *
 * ## ولماذا ٤٠٤ بلا توكن
 *
 * ما دام التوكن غير مضبوط فالباب غير موجود. نفس منطق `MaintenanceController`:
 * «٤٠١ غير مصرّح» تقول لمن يجسّ الخادم إنّ هنا شيئاً يستحقّ المحاولة، و«٤٠٤»
 * لا تقول شيئاً. والفرق يهمّ على مسارٍ يقبل بيانات أطفال.
 */
class SyncController extends Controller
{
    public function __construct(private ZaidSync $sync) {}

    /**
     * يستقبل دفعةً من `tools/zaid-sync/haya_sync.php`.
     */
    public function receive(Request $request): JsonResponse
    {
        $this->authorizeMachine($request);

        $data = $request->validate([
            'kind' => ['required', 'string', 'in:schema,rows,done'],
            'table' => ['nullable', 'string', 'max:64'],
            'offset' => ['nullable', 'integer', 'min:0'],
            'rows' => ['nullable', 'array'],
            'tables' => ['nullable', 'array'],
        ]);

        $answer = match ($data['kind']) {
            'schema' => $this->sync->schema($data),
            'rows' => $this->sync->rows($data),
            'done' => $this->sync->done($data),
        };

        // ٤٠٩ حين يكون الترتيب هو المشكلة لا الطلب: الطرف الآخر سليم، وإعادة
        // المحاولة بعد كتابة المقابل تنجح بلا تغيير عنده.
        $status = ($answer['ok'] ?? true) ? 200 : 409;

        return response()->json($answer, $status);
    }

    /**
     * ما وصل ومتى — للمكتب، ولمن يكتب المقابل.
     */
    public function status(): JsonResponse
    {
        $schema = Setting::get(ZaidSync::SCHEMA_KEY);

        return response()->json([
            'data' => [
                'configured' => Setting::get(ZaidSync::TOKEN_KEY) !== null,
                'schema_reviewed' => $this->sync->schemaReviewed(),
                'schema' => $schema === null ? null : json_decode($schema, true),
                'runs' => SyncRun::query()
                    ->where('source', ZaidSync::SOURCE)
                    ->latest('id')
                    ->limit(30)
                    ->get(),
            ],
        ]);
    }

    /**
     * يولّد توكناً جديداً ويعرضه مرّة.
     *
     * التوليد هو التدوير: لا يوجد «اعرض التوكن الحالي» عمداً — سرٌّ يمكن
     * عرضه متى شئت هو سرٌّ يُنسخ في محادثات ويبقى في لقطات شاشة. يُولَّد،
     * يُلصَق في السكربت، ويُنسى.
     */
    public function rotate(): JsonResponse
    {
        $token = Str::random(64);

        Setting::put(ZaidSync::TOKEN_KEY, hash('sha256', $token));

        return response()->json([
            'data' => [
                'token' => $token,
                'note' => 'انسخه الآن والصقه في haya_sync.php — ما بينعرض مرّة تانية.',
            ],
        ]);
    }

    /**
     * يوقف المزامنة: بلا توكن، الباب غير موجود.
     */
    public function disable(): JsonResponse
    {
        Setting::put(ZaidSync::TOKEN_KEY, null);

        return response()->json(['data' => ['configured' => false]]);
    }

    private function authorizeMachine(Request $request): void
    {
        $stored = Setting::get(ZaidSync::TOKEN_KEY);
        $given = (string) $request->bearerToken();

        // التوكن مخزَّنٌ مُلبَّداً: نسخةُ قاعدةٍ تُسرَّب لا تعطي من يملكها
        // مفتاحاً يعمل.
        abort_if(
            $stored === null || $given === '' || ! hash_equals($stored, hash('sha256', $given)),
            404
        );
    }
}
