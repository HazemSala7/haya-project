<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Message;
use App\Models\Student;
use App\Models\TherapySession;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

class MessageController extends Controller
{
    /**
     * The thread about one child, oldest first.
     *
     * Oldest first because it is read as a conversation, not as an inbox — and
     * a specialist picking up a case wants to start where the family started,
     * not work backwards through it.
     */
    public function index(Request $request, Student $student): JsonResponse
    {
        abort_unless($student->readableBy($request->user()), 404, 'العنصر المطلوب غير موجود.');

        $messages = $student->messages()
            ->with(['sender:id,name,role,title', 'session:id,number,scheduled_at'])
            ->oldest()
            ->paginate($this->perPage($request, 50));

        // Opening the thread marks everything in it that this person did not
        // write. A per-message "seen" tick would be a promise this system has
        // no way to keep.
        $student->messages()->unread()->notFrom($request->user())->update(['read_at' => now()]);

        return $this->paginated($messages);
    }

    public function store(Request $request, Student $student): JsonResponse
    {
        $user = $request->user();

        abort_unless($student->readableBy($user), 404, 'العنصر المطلوب غير موجود.');

        $data = $request->validate([
            'body' => ['required', 'string', 'max:4000'],
            'therapy_session_id' => ['nullable', 'exists:therapy_sessions,id'],
        ]);

        /*
         * A question tied to a report has to be tied to a report about *this*
         * child. Without the check, a parent could attach their question to
         * any session id in the building and pull its number and date into a
         * thread the specialist would then answer from.
         */
        if (! empty($data['therapy_session_id'])) {
            $belongs = TherapySession::whereKey($data['therapy_session_id'])
                ->where('student_id', $student->id)
                ->exists();

            abort_unless($belongs, 422, 'هذه الجلسة ليست لهذا الطالب.');
        }

        $message = $student->messages()->create([
            'sender_id' => $user->id,
            'therapy_session_id' => $data['therapy_session_id'] ?? null,
            'body' => $data['body'],
        ]);

        return response()->json([
            'data' => $message->load(['sender:id,name,role,title', 'session:id,number,scheduled_at']),
        ], 201);
    }

    /**
     * Threads with something waiting in them, for whoever is asking.
     *
     * This is what puts a number on the bell. A family's question that sat
     * unanswered for four days is the single most damaging thing an academy
     * can do to the trust these reports are building, so the count is on the
     * first screen rather than behind a menu.
     */
    public function unread(Request $request): JsonResponse
    {
        $user = $request->user();

        $threads = Message::query()
            ->select('student_id', DB::raw('count(*) as unread'), DB::raw('max(created_at) as last_at'))
            ->unread()
            ->notFrom($user)
            ->when($user->isGuardian(), fn ($q) => $q->whereHas(
                'student.guardians',
                fn ($g) => $g->where('users.id', $user->id),
            ))
            ->groupBy('student_id')
            ->orderByDesc('last_at')
            ->limit(20)
            ->get();

        $names = Student::whereIn('id', $threads->pluck('student_id'))
            ->pluck('name', 'id');

        return response()->json([
            'data' => $threads->map(fn ($row) => [
                'student_id' => $row->student_id,
                'student_name' => $names[$row->student_id] ?? '—',
                'unread' => (int) $row->unread,
                'last_at' => $row->last_at,
            ]),
            'meta' => ['total' => (int) $threads->sum('unread')],
        ]);
    }
}
