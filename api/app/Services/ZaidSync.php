<?php

namespace App\Services;

use App\Models\Setting;
use App\Models\SyncRun;
use Illuminate\Support\Facades\DB;

/**
 * استقبال ما يدفعه النظام القديم (zaid_system على qadrs.com).
 *
 * ## الاتجاه واحد، عمداً
 *
 * المكتب يشتغل على القديم، وhaya مرآةٌ حيّة له. ما تسجّله haya وحدها —
 * الأهداف، التقارير المنشورة، الحضور والتقييم، رسائل الأولياء — يبقى في haya
 * ولا يعود. لأن القديم ليس فيه مكانٌ له أصلاً: لا أخصائيةً معيّنة على جلسة،
 * ولا تقريراً له حالة نشر، ولا ولياً له دخول. المزامنة العكسية ليست أصعب،
 * هي بلا معنى.
 *
 * ## لماذا لا شيء يُكتب قبل أن تصل الـschema
 *
 * أعمدة `patients` عند زيد غير معروفة هنا، و`students` في haya تطلب تاريخ
 * ميلادٍ وجنساً وتاريخ التحاقٍ **إلزامية**. مُستورِدٌ يُكتب على التخمين إمّا
 * يرفض كل صفّ أو — وهذا الأسوأ — يملأ الفراغات بقيمٍ مخترعة فيصير في الملف
 * أطفالٌ مواليدهم اليوم الذي وصلوا فيه.
 *
 * فالوضع `rows` مقفول حتى تصل `schema` ويُكتب المقابلُ عموداً بعمود. وهذا
 * ليس نقصاً في التنفيذ — هو الترتيب الوحيد الذي لا يُفسد ملفّاً.
 */
class ZaidSync
{
    public const SOURCE = 'zaid';

    /** مفتاح التقرير في الإعدادات — لا يُعرَض مع بقية الإعدادات. */
    public const SCHEMA_KEY = 'sync.zaid_schema';

    public const TOKEN_KEY = 'sync.zaid_token';

    /**
     * خريطة القاعدة القديمة — تُحفَظ ولا تُنفَّذ.
     *
     * هي أول ما يصل وأهمّه: منها يُكتب المقابل، وبها يُعرَف أيّ عمودٍ من
     * أعمدة haya الإلزامية له مصدرٌ وأيّها يحتاج قراراً.
     *
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    public function schema(array $payload): array
    {
        $tables = is_array($payload['tables'] ?? null) ? $payload['tables'] : [];

        Setting::put(self::SCHEMA_KEY, json_encode([
            'received_at' => now()->toIso8601String(),
            'tables' => $tables,
        ], JSON_UNESCAPED_UNICODE));

        $run = SyncRun::create([
            'source' => self::SOURCE,
            'kind' => 'schema',
            'received' => count($tables),
        ]);

        return [
            'ok' => true,
            'run' => $run->id,
            'tables' => count($tables),
            'rows' => array_sum(array_map(
                fn ($table) => (int) ($table['rows'] ?? 0),
                $tables
            )),
            'message' => 'وصلت الخريطة. المقابل يُكتب عليها قبل أن يُستورَد صفّ.',
        ];
    }

    /**
     * صفوف جدولٍ واحد.
     *
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    public function rows(array $payload): array
    {
        $table = (string) ($payload['table'] ?? '');
        $rows = is_array($payload['rows'] ?? null) ? $payload['rows'] : [];

        if (! $this->schemaReviewed()) {
            // ٤٠٩ لا ٥٠٠: الطرف الآخر ليس معطوباً، الترتيب فقط لم يكتمل.
            // ويُسجَّل ما وصل عدداً — فيُعرف الحجم قبل أن يُكتب المقابل.
            SyncRun::create([
                'source' => self::SOURCE,
                'kind' => 'rows',
                'table_name' => $table,
                'received' => count($rows),
                'skipped' => count($rows),
                'problems' => ['المقابل لم يُكتب بعد — شغّل الوضع schema أولاً.'],
            ]);

            return [
                'ok' => false,
                'code' => 'schema_not_reviewed',
                'message' => 'الخريطة ما وصلت أو ما انراجعت بعد. شغّل: php haya_sync.php schema',
            ];
        }

        return DB::transaction(fn () => $this->importTable($table, $rows));
    }

    /**
     * نهاية الجولة.
     *
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    public function done(array $payload): array
    {
        $run = SyncRun::create([
            'source' => self::SOURCE,
            'kind' => 'done',
            'received' => count(is_array($payload['tables'] ?? null) ? $payload['tables'] : []),
        ]);

        return ['ok' => true, 'run' => $run->id];
    }

    /** هل وصلت الخريطة وكُتب المقابل عليها؟ */
    public function schemaReviewed(): bool
    {
        // المقابل يُكتب في `importTable`؛ وما دام فارغاً فلا شيء يُستورَد
        // مهما وصلت خرائط. الشرطان معاً عمداً: خريطةٌ وصلت ومقابلٌ كُتب.
        return Setting::get(self::SCHEMA_KEY) !== null && $this->mappings() !== [];
    }

    /**
     * جدول المصدر ← كيف يصير صفّاً في haya.
     *
     * فارغةٌ اليوم: تُملأ عموداً بعمود حين تصل الخريطة الحقيقية. انظر شرح
     * الصنف أعلاه — المقابلُ المكتوب على التخمين أسوأ من غيابه.
     *
     * @return array<string, callable>
     */
    private function mappings(): array
    {
        return [];
    }

    /**
     * @param  list<array<string, mixed>>  $rows
     * @return array<string, mixed>
     */
    private function importTable(string $table, array $rows): array
    {
        $mapping = $this->mappings()[$table] ?? null;

        if ($mapping === null) {
            SyncRun::create([
                'source' => self::SOURCE,
                'kind' => 'rows',
                'table_name' => $table,
                'received' => count($rows),
                'skipped' => count($rows),
                'problems' => ["لا مقابل لجدول «{$table}» — غير مطلوب أو لم يُكتب بعد."],
            ]);

            return ['ok' => true, 'counts' => ['skipped' => count($rows)]];
        }

        $counts = ['created' => 0, 'updated' => 0, 'skipped' => 0];
        $problems = [];

        foreach ($rows as $row) {
            $outcome = $mapping($row, $problems);
            $counts[$outcome] = ($counts[$outcome] ?? 0) + 1;
        }

        SyncRun::create([
            'source' => self::SOURCE,
            'kind' => 'rows',
            'table_name' => $table,
            'received' => count($rows),
            'created' => $counts['created'],
            'updated' => $counts['updated'],
            'skipped' => $counts['skipped'],
            // تُقصّ: سجلٌّ بألف مشكلةٍ متطابقة لا يُقرأ، وعشرٌ منها تُقرأ.
            'problems' => array_slice($problems, 0, 20) ?: null,
        ]);

        return ['ok' => true, 'counts' => $counts];
    }
}
