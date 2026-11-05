<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

/**
 * سطرٌ لكل تشغيلة مزامنة.
 *
 * مزامنةٌ بلا سجلّ هي مزامنةٌ لا أحد يعرف متى توقّفت: تتعطّل في ليلةٍ ما —
 * توكن انتهى، عمودٌ تغيّر، شبكةٌ انقطعت — ويظلّ المكتب يرى بياناتٍ تبدو
 * صحيحة، لأنها صحيحةٌ فعلاً حتى تلك الليلة. هذا الجدول هو ما يجعل الصمت
 * مرئياً.
 */
class SyncRun extends Model
{
    protected $fillable = [
        'source',
        'kind',
        'table_name',
        'received',
        'created',
        'updated',
        'skipped',
        'problems',
    ];

    protected function casts(): array
    {
        return [
            'problems' => 'array',
            'received' => 'integer',
            'created' => 'integer',
            'updated' => 'integer',
            'skipped' => 'integer',
        ];
    }
}
