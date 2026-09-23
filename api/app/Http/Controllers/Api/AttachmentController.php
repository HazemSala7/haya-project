<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\SessionAttachment;
use App\Models\TherapySession;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

/**
 * Photos and short clips from a session.
 *
 * Nothing here is public. Every file is streamed by `show()` after the viewer
 * has been checked against the child's guardians — a public disk with a long
 * filename is not access control, it is a delay, and the thing being protected
 * is a photograph of a disabled child.
 */
class AttachmentController extends Controller
{
    /** Roughly a minute of phone video, or a large photo. */
    private const MAX_KB = 20480;

    public function store(Request $request, TherapySession $session): JsonResponse
    {
        abort_unless(
            $request->user()->mayWriteOn($session),
            403,
            'هذه الجلسة مسجّلة على أخصائية أخرى.',
        );

        $request->validate([
            'file' => [
                'required', 'file', 'max:'.self::MAX_KB,
                'mimetypes:image/jpeg,image/png,image/webp,video/mp4,video/quicktime',
            ],
            'caption' => ['nullable', 'string', 'max:200'],
        ]);

        $file = $request->file('file');

        /*
         * Stored on the private disk under the session id, with a generated
         * name. The uploaded name is kept in the row for display only — using
         * it on disk would let a caller pick the path, and a caller who picks
         * the path eventually picks one with `..` in it.
         */
        $path = $file->store("sessions/{$session->id}", 'local');

        $attachment = $session->attachments()->create([
            'uploaded_by' => $request->user()->id,
            'path' => $path,
            'original_name' => $file->getClientOriginalName(),
            'mime' => $file->getMimeType(),
            'size' => $file->getSize(),
            'caption' => $request->input('caption'),
        ]);

        return response()->json(['data' => $attachment], 201);
    }

    /**
     * Hand the file over — after checking who is asking.
     *
     * Reuses the session's own visibility scope rather than re-deriving it, so
     * a draft report's photos are as invisible to a family as its text is.
     */
    public function show(Request $request, SessionAttachment $attachment): StreamedResponse
    {
        $visible = TherapySession::whereKey($attachment->therapy_session_id)
            ->visibleTo($request->user())
            ->exists();

        abort_unless($visible, 404, 'العنصر المطلوب غير موجود.');

        abort_unless(Storage::disk('local')->exists($attachment->path), 404);

        return Storage::disk('local')->response(
            $attachment->path,
            $attachment->original_name,
            [
                'Content-Type' => $attachment->mime,
                // Files are immutable once uploaded, so a parent scrolling a
                // timeline of twenty photos fetches each one once.
                'Cache-Control' => 'private, max-age=604800',
            ],
        );
    }

    public function destroy(Request $request, SessionAttachment $attachment): JsonResponse
    {
        $session = $attachment->session;

        abort_unless(
            $session && $request->user()->mayWriteOn($session),
            403,
            'هذه الجلسة مسجّلة على أخصائية أخرى.',
        );

        // The file goes with the row. An orphaned blob on a shared host is
        // storage nobody will ever account for.
        Storage::disk('local')->delete($attachment->path);

        $attachment->delete();

        return response()->json(['message' => 'تم حذف المرفق.']);
    }
}
