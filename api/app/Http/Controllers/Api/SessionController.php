<?php

namespace App\Http\Controllers\Api;

use App\Enums\PromptLevel;
use App\Http\Controllers\Controller;
use App\Models\Enrollment;
use App\Models\TherapySession;
use App\Services\DocumentNumbers;
use App\Services\ReportDesk;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;

class SessionController extends Controller
{
    public function __construct(
        private ReportDesk $desk,
        private DocumentNumbers $numbers,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $sessions = TherapySession::query()
            ->visibleTo($user)
            ->between($request->query('from'), $request->query('to'))
            ->when($request->filled('student_id'), fn ($q) => $q->where('student_id', $request->query('student_id')))
            ->when($request->filled('specialist_id'), fn ($q) => $q->where('specialist_id', $request->query('specialist_id')))
            ->when($request->filled('specialty'), fn ($q) => $q->where('specialty', $request->query('specialty')))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->query('status')))
            ->when($request->filled('report_status'), fn ($q) => $q->where('report_status', $request->query('report_status')))
            ->when($request->boolean('unwritten'), fn ($q) => $q->awaitingReport())
            ->with([
                'student:id,name,file_number,medical_alert',
                'specialist:id,name,title',
            ])
            ->withCount(['ratings', 'attachments'])
            ->orderByDesc('scheduled_at')
            ->paginate($this->perPage($request));

        /*
         * Staff get a flag, never the text.
         *
         * A specialist scanning her week wants to see which sessions she left
         * a note on — but the note itself has no business travelling in a
         * fifty-row list to be read by whoever is looking over her shoulder.
         * The text is loaded on the one session she opens, in `hydrate`.
         */
        if ($user->role->seesPrivateNotes()) {
            foreach ($sessions->items() as $session) {
                $session->setAttribute('has_private_note', filled($session->getRawOriginal('private_notes')));
            }
        }

        /*
         * A guardian's list carries the read flag so the timeline can mark
         * what is new. Computed here in one query rather than per row on the
         * client, which cannot see other people's reads anyway.
         */
        if ($user->isGuardian()) {
            $read = DB::table('report_reads')
                ->where('user_id', $user->id)
                ->whereIn('therapy_session_id', collect($sessions->items())->pluck('id'))
                ->pluck('therapy_session_id')
                ->flip();

            foreach ($sessions->items() as $session) {
                $session->setAttribute('is_read', $read->has($session->id));
            }
        }

        return $this->paginated($sessions, [
            'unwritten' => $user->role->isStaff()
                ? TherapySession::awaitingReport()->where('scheduled_at', '<=', now())->count()
                : null,
        ]);
    }

    /**
     * Book a session.
     *
     * The specialty and the specialist are copied off the enrolment rather
     * than accepted from the caller: they are facts about the programme, and
     * letting a form send them is how a speech session ends up filed under
     * occupational therapy on the one day somebody covered.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'enrollment_id' => ['required', 'exists:enrollments,id'],
            'scheduled_at' => ['required', 'date'],
            'duration_minutes' => ['nullable', 'integer', 'min:5', 'max:240'],
            'specialist_id' => ['nullable', 'exists:users,id'],
        ]);

        $enrollment = Enrollment::findOrFail($data['enrollment_id']);

        $session = TherapySession::create([
            'number' => $this->numbers->session(),
            'student_id' => $enrollment->student_id,
            'enrollment_id' => $enrollment->id,
            'specialty' => $enrollment->specialty,
            'specialist_id' => $data['specialist_id'] ?? $enrollment->specialist_id,
            'scheduled_at' => $data['scheduled_at'],
            'duration_minutes' => $data['duration_minutes'] ?? $enrollment->session_minutes,
            'status' => 'scheduled',
        ]);

        return response()->json(['data' => $this->hydrate($session, $request)], 201);
    }

    public function show(Request $request, TherapySession $session): JsonResponse
    {
        $user = $request->user();

        // The same scope the list uses, applied to one row — because a
        // guardian can type an id into the address bar, and a draft report or
        // another family's child must come back as "not found" rather than as
        // a 403 that confirms it exists.
        $visible = TherapySession::whereKey($session->id)->visibleTo($user)->exists();

        abort_unless($visible, 404, 'العنصر المطلوب غير موجود.');

        // A parent opening the report is the read receipt. Staff opening it is
        // not — the specialist checking her own work must not show up as the
        // family having seen it.
        if ($user->isGuardian() && $session->isPublished()) {
            $this->desk->markRead($session, $user);
        }

        return response()->json(['data' => $this->hydrate($session, $request)]);
    }

    /** Save the report. Draft only — publishing is its own endpoint. */
    public function update(Request $request, TherapySession $session): JsonResponse
    {
        $this->authorizeWrite($request, $session);

        $data = $request->validate([
            'mood' => ['nullable', Rule::in(['calm', 'happy', 'tired', 'agitated', 'crying', 'resistant'])],
            'activities' => ['nullable', 'string', 'max:5000'],
            'progress' => ['nullable', 'string', 'max:5000'],
            'difficulties' => ['nullable', 'string', 'max:5000'],
            'home_plan' => ['nullable', 'string', 'max:5000'],
            'private_notes' => ['nullable', 'string', 'max:5000'],
        ]);

        $this->desk->draft($session, $data);

        return response()->json(['data' => $this->hydrate($session->fresh(), $request)]);
    }

    /**
     * Attendance.
     *
     * Separate from the report because it is answered at a different moment by
     * a different person: the diary is marked when the child walks in (or does
     * not), and the report is written afterwards.
     */
    public function attendance(Request $request, TherapySession $session): JsonResponse
    {
        $this->authorizeWrite($request, $session);

        $data = $request->validate([
            'status' => ['required', Rule::in(['scheduled', 'held', 'absent', 'excused', 'cancelled'])],
            'absence_reason' => ['nullable', 'string', 'max:200'],
        ]);

        if ($session->isPublished() && $data['status'] !== 'held') {
            return response()->json([
                'message' => 'التقرير مُرسل — ما بينفع تغيّر الحضور بعده.',
            ], 422);
        }

        $session->update([
            'status' => $data['status'],
            'absence_reason' => $data['status'] === 'held' ? null : ($data['absence_reason'] ?? null),
        ]);

        return response()->json(['data' => $this->hydrate($session->fresh(), $request)]);
    }

    /** Score the goals worked on today. */
    public function rate(Request $request, TherapySession $session): JsonResponse
    {
        $this->authorizeWrite($request, $session);

        $data = $request->validate([
            'ratings' => ['present', 'array'],
            'ratings.*.goal_id' => ['required', 'integer', 'exists:goals,id'],
            'ratings.*.level' => ['required', 'integer', Rule::in(array_column(PromptLevel::cases(), 'value'))],
            'ratings.*.trials' => ['nullable', 'integer', 'min:0', 'max:999'],
            'ratings.*.successes' => ['nullable', 'integer', 'min:0', 'max:999'],
            'ratings.*.note' => ['nullable', 'string', 'max:300'],
        ]);

        $this->desk->rate($session, $data['ratings']);

        return response()->json(['data' => $this->hydrate($session->fresh(), $request)]);
    }

    /** Send it to the family. */
    public function publish(Request $request, TherapySession $session): JsonResponse
    {
        $this->authorizeWrite($request, $session);

        $this->desk->publish($session, $request->user());

        return response()->json([
            'data' => $this->hydrate($session->fresh(), $request),
            'message' => 'تم إرسال التقرير لولي الأمر.',
        ]);
    }

    /** التصحيح — a dated line under a report that has already gone out. */
    public function addendum(Request $request, TherapySession $session): JsonResponse
    {
        $this->authorizeWrite($request, $session);

        $data = $request->validate([
            'body' => ['required', 'string', 'max:2000'],
        ]);

        $this->desk->addendum($session, $request->user(), $data['body']);

        return response()->json(['data' => $this->hydrate($session->fresh(), $request)]);
    }

    public function destroy(TherapySession $session): JsonResponse
    {
        if ($session->isPublished()) {
            return response()->json([
                'message' => 'التقرير مُرسل ومقروء — ما بينحذف. ضيف تصحيح عليه.',
            ], 422);
        }

        $session->delete();

        return response()->json(['message' => 'تم حذف الجلسة.']);
    }

    /* ---------------------------------------------------------------------
     | Plumbing
     |------------------------------------------------------------------- */

    private function authorizeWrite(Request $request, TherapySession $session): void
    {
        abort_unless(
            $request->user()->mayWriteOn($session),
            403,
            'هذه الجلسة مسجّلة على أخصائية أخرى. الإدارة بتقدر تحوّلها إلك.',
        );
    }

    /**
     * One session, loaded for whoever is looking at it.
     *
     * The private notes are switched on for staff here and only here — the
     * column is hidden on the model, so any endpoint that forgets this call
     * fails safe by leaving them out rather than by leaking them.
     */
    private function hydrate(TherapySession $session, Request $request): TherapySession
    {
        $user = $request->user();

        $session->load([
            'student:id,name,file_number,birth_date,medical_alert,diagnosis',
            'specialist:id,name,title',
            'enrollment:id,specialty,plan_summary',
            'ratings.goal:id,title,criteria,baseline,target,status',
            'attachments',
            'addenda.author:id,name',
        ]);

        if ($user->role->seesPrivateNotes()) {
            $session->makeVisible('private_notes');

            // Who has opened it — the number that tells a specialist whether
            // writing these is reaching anyone.
            $session->setAttribute('read_by', $session->reads()
                ->with('user:id,name')
                ->get()
                ->map(fn ($read) => [
                    'name' => $read->user?->name,
                    'read_at' => $read->read_at?->toDateTimeString(),
                ]));
        }

        return $session;
    }
}
