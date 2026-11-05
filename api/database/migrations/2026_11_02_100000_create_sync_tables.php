<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * المزامنة من النظام القديم (zaid_system على qadrs.com) — باتجاه واحد.
 *
 * ## لماذا عمودان على كل جدول
 *
 * المزامنة تعمل كل ساعة إلى الأبد، فالسؤال الذي يتكرّر مليون مرّة هو: «هذا
 * الصفّ الوارد — هل أنشأتُه من قبل؟». الجواب لا يمكن أن يكون الاسم (الأسماء
 * تتكرّر وتُصحَّح)، ولا رقم الملف (haya يولّده، والقديم لا يعرفه). الجواب
 * الوحيد الثابت هو مفتاح الصفّ في النظام المصدر.
 *
 * لذلك `source` و`source_id`، وفريدان معاً: مريضُ زيد رقم ٤٢ يصير طالباً
 * واحداً في haya مهما شُغّلت المزامنة، وتشغيلةٌ ثانيةٌ تُحدِّثه ولا تُنشئ
 * نسخةً ثانية. وبدون هذا القيد تصير كل تشغيلةٍ طبقةً جديدة من الأطفال.
 *
 * وكلاهما قابل للفراغ: الطفل الذي سُجِّل في haya مباشرةً ليس له أصلٌ في
 * القديم، وهذا هو الحال الطبيعي لا الاستثناء.
 *
 * ## ولماذا جدول للتشغيلات
 *
 * مزامنةٌ لا سجلّ لها هي مزامنةٌ لا أحد يعرف متى توقّفت. تتعطّل في ليلةٍ ما
 * — انتهى التوكن، تغيّر عمود، امتلأ القرص — ويظلّ المكتب يرى بياناتٍ تبدو
 * صحيحة لأنها صحيحةٌ حتى تلك الليلة. السجلّ هو ما يجعل الصمت مرئياً.
 */
return new class extends Migration
{
    /** الجداول التي تستقبل صفوفاً من النظام القديم. */
    private const SOURCED = [
        'users',
        'students',
        'enrollments',
        'therapy_sessions',
        'invoices',
        'payments',
    ];

    public function up(): void
    {
        foreach (self::SOURCED as $table) {
            if (! Schema::hasTable($table) || Schema::hasColumn($table, 'source')) {
                continue;
            }

            Schema::table($table, function (Blueprint $blueprint) {
                // `zaid` اليوم. عمودٌ لا ثابتٌ في الكود، لأن نظاماً ثانياً
                // يُضاف يوماً ولا يُراد له هجرةٌ جديدة.
                $blueprint->string('source', 24)->nullable()->after('id');
                $blueprint->string('source_id', 64)->nullable()->after('source');

                $blueprint->unique(['source', 'source_id']);
            });
        }

        Schema::create('sync_runs', function (Blueprint $table) {
            $table->id();

            $table->string('source', 24)->index();

            // schema | rows | done
            $table->string('kind', 16);

            // اسم جدول المصدر في تشغيلات الصفوف، وفراغ في غيرها.
            $table->string('table_name', 64)->nullable();

            $table->unsignedInteger('received')->default(0);
            $table->unsignedInteger('created')->default(0);
            $table->unsignedInteger('updated')->default(0);
            $table->unsignedInteger('skipped')->default(0);

            /*
             * الصفوف التي رُفضت ولماذا — لا لتُقرأ كسجلّ أخطاء بل لتُصلَح.
             * صفٌّ بلا تاريخ ميلاد يُرفض اليوم ويُقبل غداً بعد أن يُقرَّر ماذا
             * يُكتب مكانه، والقائمة هي ما يقول كم طفلاً ينتظر ذلك القرار.
             */
            $table->json('problems')->nullable();

            $table->timestamps();

            $table->index(['source', 'kind', 'created_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sync_runs');

        foreach (self::SOURCED as $table) {
            if (! Schema::hasTable($table) || ! Schema::hasColumn($table, 'source')) {
                continue;
            }

            Schema::table($table, function (Blueprint $blueprint) {
                $blueprint->dropUnique(['source', 'source_id']);
                $blueprint->dropColumn(['source', 'source_id']);
            });
        }
    }
};
