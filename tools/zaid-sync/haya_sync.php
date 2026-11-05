<?php
/**
 * مزامنة zaid_system ← haya — الطرف الذي يدفع.
 *
 * يوضع على استضافة qadrs.com **خارج الجذر العام** ويُنادى من cron وحده.
 * ليس له رابط: لا يُفتح من متصفّح، ولا يُكتشَف بتخمين اسم، ولا يُنادى إلا من
 * سطر الأوامر. وهذا هو سبب اختيار الدفع على السحب — السحب كان يعني ملفَّ
 * بيانات مرضى جالساً على رابط بين كل تشغيلة وأخرى.
 *
 * ## ماذا يفعل
 *
 * يقرأ قاعدة zaid_system، ويرسل ما قرأه إلى haya عبر HTTPS بـtoken. لا يكتب
 * في القاعدة ولا يعدّل ملفاً ولا يلمس التطبيق الشغّال — SELECT وSHOW فقط.
 *
 * ## التشغيل
 *
 *   php haya_sync.php schema        # مرّة واحدة: الجداول وأعمدتها وعدد صفوفها
 *   php haya_sync.php rows          # كل تشغيلة: الصفوف
 *   php haya_sync.php rows --dry    # يطبع ولا يرسل — للتجربة
 *
 * ## الإعداد
 *
 * عدّل الثابتَين أدناه: عنوان haya والـtoken. الـtoken يُولَّد من haya
 * (الإعدادات ← المزامنة) ولا يُكتب في أي مكان آخر.
 *
 * ## لماذا يرسل كل شيء في كل مرّة
 *
 * عيادةٌ بياناتها بالآلاف لا بالملايين، والإرسال الكامل يجعل المزامنة
 * **قابلة للتكرار**: شُغّلت مرّة أو عشراً فالنتيجة واحدة، وانقطعت الشبكة في
 * المنتصف فالتشغيلة التالية تُصلح نفسها. المزامنة التفاضلية أسرع وأهشّ،
 * وتحتاج علامةَ مياهٍ تُفسد كل شيء حين تضيع. إن أظهر تقرير `schema` جداول
 * ضخمة فعندها — ولأجلها وحدها — تُضاف.
 */

declare(strict_types=1);

if (PHP_SAPI !== 'cli') {
    // حزامٌ ثانٍ فوق كونه خارج الجذر العام: لو نُقل يوماً إلى مجلّد عام،
    // فطلبُه عبر المتصفّح لا يفعل شيئاً.
    http_response_code(404);
    exit(1);
}

// =============================================================================
//  الإعداد
// =============================================================================

/** عنوان haya — بلا شرطة مائلة في آخره. */
const HAYA_URL = 'https://neurex.ps/haya/api';

/** الـtoken المولَّد من haya. استبدله قبل أوّل تشغيل. */
const HAYA_TOKEN = 'ضع-التوكن-هنا';

/** مسار `.env` الخاص بـzaid_system — عدّله إن وضعت الملف في مكان آخر. */
const ZAID_ENV = __DIR__ . '/../zaid_system/.env';

/**
 * الجداول التي تُرسَل، بالترتيب الذي يجب أن تصل به: المرجوع إليه قبل المُرجِع.
 * الطالب قبل موعده، والموعد قبل حركته المالية — وإلا وصل سطرٌ يشير إلى
 * شيءٍ لم يُنشأ بعد.
 */
const TABLES = ['users', 'patients', 'sessions', 'appointments', 'itransactions'];

/** كم صفّاً في الرسالة الواحدة. يكفي أن يبقى الطلب تحت حدود الاستضافة. */
const CHUNK = 500;

// =============================================================================
//  القراءة
// =============================================================================

function out(string $line): void
{
    fwrite(STDOUT, $line . PHP_EOL);
}

function die_with(string $message): void
{
    // cron يرسل stderr بالبريد، فالفشل يصل إلى صندوقٍ يقرأه أحد.
    fwrite(STDERR, 'haya_sync: ' . $message . PHP_EOL);
    exit(1);
}

/** يقرأ `.env` بنفسه — أبسط من إقلاع لارافيل كلّه لأجل أربعة أسطر. */
function env_values(string $path): array
{
    $lines = @file($path, FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES);
    if ($lines === false) {
        die_with("cannot read {$path}");
    }

    $values = [];
    foreach ($lines as $line) {
        $line = trim($line);
        if ($line === '' || $line[0] === '#' || strpos($line, '=') === false) {
            continue;
        }
        [$name, $value] = explode('=', $line, 2);
        $values[trim($name)] = trim(trim($value), "\"'");
    }

    return $values;
}

function connect(): PDO
{
    $env = env_values(ZAID_ENV);

    $host = $env['DB_HOST'] ?? '127.0.0.1';
    $port = $env['DB_PORT'] ?? '3306';
    $name = $env['DB_DATABASE'] ?? '';

    if ($name === '') {
        die_with('DB_DATABASE not set in ' . ZAID_ENV);
    }

    try {
        return new PDO(
            "mysql:host={$host};port={$port};dbname={$name};charset=utf8mb4",
            $env['DB_USERNAME'] ?? '',
            $env['DB_PASSWORD'] ?? '',
            [
                PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
                PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
                // أرقامٌ كأرقام: مبلغٌ يصل كسلسلة يُدوَّر في الطرف الآخر.
                PDO::ATTR_STRINGIFY_FETCHES => false,
            ]
        );
    } catch (Throwable $e) {
        die_with('connect failed: ' . $e->getMessage());
    }
}

/** @return list<string> */
function table_names(PDO $pdo): array
{
    $found = [];
    foreach ($pdo->query('SHOW TABLES') as $row) {
        $found[] = (string) reset($row);
    }

    return $found;
}

// =============================================================================
//  الإرسال
// =============================================================================

/**
 * يرسل جسماً واحداً إلى haya.
 *
 * بلا `-k` وبلا تعطيل تحقّق: شهادة neurex.ps صالحة، وإن فشل التحقّق يوماً
 * فذلك خبرٌ يجب أن يُسمَع لا أن يُسكَت.
 */
function post(array $body): array
{
    $json = json_encode($body, JSON_UNESCAPED_UNICODE);
    if ($json === false) {
        die_with('cannot encode payload: ' . json_last_error_msg());
    }

    $curl = curl_init(HAYA_URL . '/sync/zaid');
    curl_setopt_array($curl, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => $json,
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 120,
        CURLOPT_SSL_VERIFYPEER => true,
        CURLOPT_SSL_VERIFYHOST => 2,
        CURLOPT_HTTPHEADER => [
            'Content-Type: application/json',
            'Accept: application/json',
            'Authorization: Bearer ' . HAYA_TOKEN,
        ],
    ]);

    $response = curl_exec($curl);
    $status = (int) curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);

    if ($response === false) {
        die_with('request failed: ' . $error);
    }

    $decoded = json_decode((string) $response, true);

    if ($status >= 300) {
        $said = is_array($decoded) ? ($decoded['message'] ?? $response) : $response;
        die_with("haya answered {$status}: " . substr((string) $said, 0, 400));
    }

    return is_array($decoded) ? $decoded : [];
}

// =============================================================================
//  الأوضاع
// =============================================================================

/**
 * التقرير الذي يُبنى عليه كل شيء بعده.
 *
 * بلا أسماء الأعمدة الحقيقية لا يُكتب مُستورِد — يُكتب تخمين. وأعمدة haya
 * الإلزامية (تاريخ الميلاد، الجنس، تاريخ الالتحاق) إمّا لها مقابلٌ هنا أو
 * يجب أن يُقرَّر ماذا يُكتب مكانها، وهذا قرارٌ لا يُتخذ على التخمين.
 */
function send_schema(PDO $pdo, bool $dry): void
{
    $report = ['kind' => 'schema', 'tables' => []];

    foreach (table_names($pdo) as $table) {
        $columns = [];
        foreach ($pdo->query('SHOW COLUMNS FROM `' . $table . '`') as $column) {
            $columns[] = [
                'name' => $column['Field'],
                'type' => $column['Type'],
                'null' => $column['Null'] === 'YES',
                'key' => $column['Key'],
            ];
        }

        $report['tables'][] = [
            'name' => $table,
            'rows' => (int) $pdo->query('SELECT COUNT(*) FROM `' . $table . '`')->fetchColumn(),
            'columns' => $columns,
        ];
    }

    out(sprintf('schema: %d tables', count($report['tables'])));
    foreach ($report['tables'] as $table) {
        out(sprintf(
            '  %-28s %6d rows   %s',
            $table['name'],
            $table['rows'],
            implode(', ', array_column($table['columns'], 'name'))
        ));
    }

    if ($dry) {
        out('(--dry: nothing sent)');

        return;
    }

    $answer = post($report);
    out('sent. haya said: ' . json_encode($answer, JSON_UNESCAPED_UNICODE));
}

function send_rows(PDO $pdo, bool $dry): void
{
    $present = table_names($pdo);

    foreach (TABLES as $table) {
        if (!in_array($table, $present, true)) {
            out("skip {$table} — not in this database");
            continue;
        }

        $total = (int) $pdo->query('SELECT COUNT(*) FROM `' . $table . '`')->fetchColumn();
        $sent = 0;

        for ($offset = 0; $offset < $total; $offset += CHUNK) {
            $rows = $pdo
                ->query('SELECT * FROM `' . $table . '` ORDER BY `id` LIMIT ' . CHUNK . ' OFFSET ' . $offset)
                ->fetchAll();

            if ($rows === []) {
                break;
            }

            if ($dry) {
                out(sprintf('%s: would send %d rows at offset %d', $table, count($rows), $offset));
                $sent += count($rows);
                continue;
            }

            $answer = post([
                'kind' => 'rows',
                'table' => $table,
                'offset' => $offset,
                'rows' => $rows,
            ]);

            $sent += count($rows);
            out(sprintf(
                '%s: %d/%d  %s',
                $table,
                $sent,
                $total,
                json_encode($answer['counts'] ?? $answer, JSON_UNESCAPED_UNICODE)
            ));
        }
    }

    if (!$dry) {
        // يقول لـhaya إنّ الجولة اكتملت، فتعرف أنّ ما لم يصل محذوفٌ لا ناقص.
        post(['kind' => 'done', 'tables' => TABLES]);
        out('round closed.');
    }
}

// =============================================================================

$mode = $argv[1] ?? 'rows';
$dry = in_array('--dry', $argv, true);

if (!$dry && HAYA_TOKEN === 'ضع-التوكن-هنا') {
    die_with('set HAYA_TOKEN first (haya ← الإعدادات ← المزامنة)');
}

$pdo = connect();

if ($mode === 'schema') {
    send_schema($pdo, $dry);
} elseif ($mode === 'rows') {
    send_rows($pdo, $dry);
} else {
    die_with("unknown mode '{$mode}' — use schema or rows");
}
