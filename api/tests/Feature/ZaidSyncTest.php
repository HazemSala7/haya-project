<?php

namespace Tests\Feature;

use App\Models\Setting;
use App\Models\Student;
use App\Models\SyncRun;
use App\Models\User;
use App\Services\ZaidSync;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * الباب الذي يدفع منه النظام القديم — ومن لا يُسمح له أن يطرقه.
 *
 * نصف هذا الملف عن القبول، ونصفه عن الرفض. والنصف الثاني هو المهمّ: مسارٌ
 * يستقبل بيانات أطفال من خادمٍ آخر هو المسار الوحيد في النظام الذي لا يقف
 * خلفه مستخدمٌ مسجَّل، فالحارس الوحيد فيه هو ما يُختبَر هنا.
 */
class ZaidSyncTest extends TestCase
{
    use RefreshDatabase;

    private const SCHEMA = [
        'kind' => 'schema',
        'tables' => [
            [
                'name' => 'patients',
                'rows' => 120,
                'columns' => [
                    ['name' => 'id', 'type' => 'bigint', 'null' => false, 'key' => 'PRI'],
                    ['name' => 'name', 'type' => 'varchar(255)', 'null' => false, 'key' => ''],
                ],
            ],
        ],
    ];

    /** يضبط توكناً ويعيد النصّ الخام الذي يُرسَل به. */
    private function configureToken(): string
    {
        $token = 'test-token-'.str_repeat('a', 40);
        Setting::put(ZaidSync::TOKEN_KEY, hash('sha256', $token));

        return $token;
    }

    /** طفلٌ بأقلّ ما تقبله `students`: الأعمدة الإلزامية وحدها. */
    private function student(array $attributes = []): Student
    {
        static $serial = 0;
        $serial++;

        return Student::create($attributes + [
            'file_number' => '9'.str_pad((string) $serial, 4, '0', STR_PAD_LEFT),
            'name' => 'طفل اختبار '.$serial,
            'birth_date' => '2019-03-01',
            'gender' => 'male',
            'enrolled_at' => '2026-01-01',
        ]);
    }

    private function push(array $body, ?string $token = null)
    {
        return $this->withHeaders($token === null ? [] : ['Authorization' => 'Bearer '.$token])
            ->postJson('/api/sync/zaid', $body);
    }

    /*
    |--------------------------------------------------------------------------
    | الباب
    |--------------------------------------------------------------------------
    */

    public function test_the_door_does_not_exist_until_a_token_is_set(): void
    {
        // لا ٤٠١ ولا ٤٠٣: «غير مصرّح» تقول لمن يجسّ الخادم إنّ هنا شيئاً.
        $this->push(self::SCHEMA)->assertNotFound();
        $this->push(self::SCHEMA, 'anything')->assertNotFound();
    }

    public function test_a_wrong_token_is_also_a_404(): void
    {
        $this->configureToken();

        $this->push(self::SCHEMA, 'wrong-token')->assertNotFound();
    }

    public function test_the_right_token_gets_in(): void
    {
        $token = $this->configureToken();

        $this->push(self::SCHEMA, $token)->assertOk();
    }

    public function test_the_token_is_stored_hashed(): void
    {
        $token = $this->configureToken();

        // نسخةُ قاعدةٍ تُسرَّب يجب ألّا تعطي من يملكها مفتاحاً يعمل.
        $this->assertNotSame($token, Setting::get(ZaidSync::TOKEN_KEY));
        $this->assertSame(64, strlen((string) Setting::get(ZaidSync::TOKEN_KEY)));
    }

    public function test_an_unknown_kind_is_refused(): void
    {
        $token = $this->configureToken();

        $this->push(['kind' => 'drop_everything'], $token)
            ->assertStatus(422);
    }

    /*
    |--------------------------------------------------------------------------
    | الخريطة
    |--------------------------------------------------------------------------
    */

    public function test_the_schema_is_kept_and_counted(): void
    {
        $token = $this->configureToken();

        $this->push(self::SCHEMA, $token)
            ->assertOk()
            ->assertJsonPath('tables', 1)
            ->assertJsonPath('rows', 120);

        $this->assertNotNull(Setting::get(ZaidSync::SCHEMA_KEY));
        $this->assertDatabaseHas('sync_runs', ['kind' => 'schema', 'source' => 'zaid']);
    }

    /*
    |--------------------------------------------------------------------------
    | لا استيراد على التخمين
    |--------------------------------------------------------------------------
    |
    | أعمدة `patients` عند زيد غير معروفة، و`students` تطلب تاريخ ميلادٍ وجنساً
    | وتاريخ التحاقٍ إلزامية. استيرادٌ يُكتب قبل أن تُعرَف الأعمدة يملأ
    | الفراغات بقيمٍ مخترعة — وطفلٌ مولده يوم وصوله أسوأ من طفلٍ لم يصل.
    */

    public function test_rows_are_refused_while_the_mapping_is_unwritten(): void
    {
        $token = $this->configureToken();
        $this->push(self::SCHEMA, $token)->assertOk();

        $this->push([
            'kind' => 'rows',
            'table' => 'patients',
            'rows' => [['id' => 1, 'name' => 'طفل']],
        ], $token)
            ->assertStatus(409)
            ->assertJsonPath('code', 'schema_not_reviewed');

        $this->assertSame(0, Student::count(), 'استورد طفلاً بلا مقابل مكتوب');
    }

    public function test_the_refusal_still_records_what_arrived(): void
    {
        $token = $this->configureToken();

        $this->push([
            'kind' => 'rows',
            'table' => 'patients',
            'rows' => [['id' => 1], ['id' => 2], ['id' => 3]],
        ], $token)->assertStatus(409);

        // الحجم يُعرَف قبل أن يُكتب المقابل: ثلاثة صفوفٍ تنتظر قراراً.
        $this->assertDatabaseHas('sync_runs', [
            'kind' => 'rows',
            'table_name' => 'patients',
            'received' => 3,
            'skipped' => 3,
        ]);
    }

    public function test_nothing_in_haya_is_touched_by_a_refused_round(): void
    {
        $token = $this->configureToken();

        $before = [Student::count(), User::count()];

        $this->push(['kind' => 'rows', 'table' => 'patients', 'rows' => [['id' => 1]]], $token);
        $this->push(['kind' => 'rows', 'table' => 'users', 'rows' => [['id' => 1]]], $token);
        $this->push(['kind' => 'done', 'tables' => ['patients']], $token)->assertOk();

        $this->assertSame($before, [Student::count(), User::count()]);
    }

    /*
    |--------------------------------------------------------------------------
    | المكتب
    |--------------------------------------------------------------------------
    */

    public function test_only_the_admin_reads_the_sync_status(): void
    {
        $this->getJson('/api/sync/status')->assertUnauthorized();

        foreach (['specialist', 'guardian'] as $role) {
            $user = User::factory()->create(['role' => $role, 'is_active' => true]);
            $this->actingAs($user)->getJson('/api/sync/status')->assertForbidden();
        }

        $admin = User::factory()->create(['role' => 'admin', 'is_active' => true]);
        $this->actingAs($admin)->getJson('/api/sync/status')->assertOk();
    }

    public function test_the_status_says_whether_the_door_is_open(): void
    {
        $admin = User::factory()->create(['role' => 'admin', 'is_active' => true]);

        $this->actingAs($admin)->getJson('/api/sync/status')
            ->assertOk()
            ->assertJsonPath('data.configured', false)
            ->assertJsonPath('data.schema_reviewed', false);

        $this->configureToken();

        $this->actingAs($admin)->getJson('/api/sync/status')
            ->assertJsonPath('data.configured', true);
    }

    public function test_rotating_shows_the_token_once_and_stores_only_its_hash(): void
    {
        $admin = User::factory()->create(['role' => 'admin', 'is_active' => true]);

        $token = $this->actingAs($admin)->postJson('/api/sync/token')
            ->assertOk()
            ->json('data.token');

        $this->assertIsString($token);
        $this->assertSame(64, strlen($token));
        $this->assertSame(hash('sha256', $token), Setting::get(ZaidSync::TOKEN_KEY));

        // ولا طريق لقراءته ثانيةً — الحالة تقول «مضبوط» ولا تقول ماذا هو.
        $this->actingAs($admin)->getJson('/api/sync/status')
            ->assertOk()
            ->assertJsonMissing(['token' => $token]);
    }

    public function test_rotating_invalidates_the_previous_token(): void
    {
        $old = $this->configureToken();
        $admin = User::factory()->create(['role' => 'admin', 'is_active' => true]);

        $this->actingAs($admin)->postJson('/api/sync/token')->assertOk();

        $this->push(self::SCHEMA, $old)->assertNotFound();
    }

    public function test_disabling_shuts_the_door(): void
    {
        $token = $this->configureToken();
        $admin = User::factory()->create(['role' => 'admin', 'is_active' => true]);

        $this->actingAs($admin)->deleteJson('/api/sync/token')->assertOk();

        $this->push(self::SCHEMA, $token)->assertNotFound();
    }

    public function test_a_specialist_cannot_rotate_the_token(): void
    {
        $user = User::factory()->create(['role' => 'specialist', 'is_active' => true]);

        $this->actingAs($user)->postJson('/api/sync/token')->assertForbidden();
        $this->actingAs($user)->deleteJson('/api/sync/token')->assertForbidden();
    }

    /*
    |--------------------------------------------------------------------------
    | الأعمدة
    |--------------------------------------------------------------------------
    */

    public function test_every_table_that_receives_rows_can_remember_where_a_row_came_from(): void
    {
        // بلا هذين العمودين تصير كل تشغيلةٍ طبقةً جديدة من الأطفال.
        foreach (['users', 'students', 'enrollments', 'therapy_sessions', 'invoices', 'payments'] as $table) {
            $this->assertTrue(
                \Illuminate\Support\Facades\Schema::hasColumn($table, 'source'),
                "{$table} بلا عمود source"
            );
            $this->assertTrue(
                \Illuminate\Support\Facades\Schema::hasColumn($table, 'source_id'),
                "{$table} بلا عمود source_id"
            );
        }
    }

    public function test_the_same_source_row_cannot_be_imported_twice(): void
    {
        $this->student(['source' => 'zaid', 'source_id' => '42']);

        $this->expectException(\Illuminate\Database\QueryException::class);

        $this->student(['source' => 'zaid', 'source_id' => '42']);
    }

    public function test_a_child_entered_in_haya_directly_has_no_source(): void
    {
        $first = $this->student();
        $second = $this->student();

        // القيد الفريد يسمح بفراغاتٍ متعدّدة — وإلا لما أمكن تسجيل طفلٍ
        // ثانٍ في haya مباشرةً.
        $this->assertNull($first->source);
        $this->assertNull($second->source);
    }

    public function test_the_run_log_is_readable_by_the_office(): void
    {
        $token = $this->configureToken();
        $this->push(self::SCHEMA, $token)->assertOk();

        $admin = User::factory()->create(['role' => 'admin', 'is_active' => true]);

        $runs = $this->actingAs($admin)->getJson('/api/sync/status')->json('data.runs');

        $this->assertCount(1, $runs);
        $this->assertSame('schema', $runs[0]['kind']);
        $this->assertSame(SyncRun::count(), count($runs));
    }
}
