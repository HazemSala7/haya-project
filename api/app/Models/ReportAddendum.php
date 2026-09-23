<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * A dated correction under a published report. Never a replacement for it.
 */
class ReportAddendum extends Model
{
    /*
     * Laravel pluralises this class to `report_addendums`. The table is the
     * Latin plural, so the name has to be stated rather than inferred.
     */
    protected $table = 'report_addenda';

    protected $fillable = ['therapy_session_id', 'author_id', 'body'];

    public function session(): BelongsTo
    {
        return $this->belongsTo(TherapySession::class, 'therapy_session_id');
    }

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }
}
