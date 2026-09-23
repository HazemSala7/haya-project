<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class SessionAttachment extends Model
{
    protected $fillable = [
        'therapy_session_id', 'uploaded_by', 'path',
        'original_name', 'mime', 'size', 'caption',
    ];

    /**
     * The storage path never leaves the server.
     *
     * Files are handed out by a route that checks the viewer against the
     * child's guardians. Serialising the path would let a client build a URL
     * to the public disk and skip that check the day someone symlinks it.
     */
    protected $hidden = ['path'];

    protected $appends = ['kind'];

    protected function casts(): array
    {
        return ['size' => 'integer'];
    }

    public function session(): BelongsTo
    {
        return $this->belongsTo(TherapySession::class, 'therapy_session_id');
    }

    public function uploader(): BelongsTo
    {
        return $this->belongsTo(User::class, 'uploaded_by');
    }

    /** image | video — what the screen should render it as. */
    public function getKindAttribute(): string
    {
        return str_starts_with($this->mime, 'video/') ? 'video' : 'image';
    }
}
