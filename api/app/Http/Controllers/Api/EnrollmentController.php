<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Enums\Specialty;
use App\Http\Controllers\Controller;
use App\Models\Enrollment;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class EnrollmentController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $enrollments = Enrollment::query()
            ->when($request->filled('student_id'), fn ($q) => $q->where('student_id', $request->query('student_id')))
            ->when($request->filled('specialist_id'), fn ($q) => $q->where('specialist_id', $request->query('specialist_id')))
            ->when($request->filled('specialty'), fn ($q) => $q->where('specialty', $request->query('specialty')))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->query('status')))
            ->when($request->boolean('unassigned'), fn ($q) => $q->unassigned())
            ->with([
                'student:id,name,file_number,medical_alert',
                'specialist:id,name,title',
            ])
            ->withCount([
                'goals' => fn ($q) => $q->active(),
                'sessions',
            ])
            ->orderByDesc('started_at')
            ->paginate($this->perPage($request));

        return $this->paginated($enrollments, [
            'unassigned' => Enrollment::unassigned()->count(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request);

        /*
         * One live programme of a kind per child.
         *
         * Two open speech files for the same boy is not a case, it is a
         * bookkeeping error — and it splits his goals and his curve across two
         * rows so that neither tells the truth. The rule is here rather than a
         * unique index because a child who did speech, stopped, and came back
         * legitimately has several ended rows; see the migration.
         */
        $clash = Enrollment::where('student_id', $data['student_id'])
            ->where('specialty', $data['specialty'])
            ->where('status', 'active')
            ->exists();

        if ($clash) {
            return response()->json([
                'message' => 'الطالب عنده برنامج شغّال بنفس التخصص. أنهِ القديم أو عدّل عليه.',
            ], 422);
        }

        $this->refuseMismatchedSpecialist($data);

        return response()->json([
            'data' => Enrollment::create($data)->load('specialist:id,name,title'),
        ], 201);
    }

    public function update(Request $request, Enrollment $enrollment): JsonResponse
    {
        $data = $request->validate([
            'specialist_id' => ['nullable', 'exists:users,id'],
            'sessions_per_week' => ['nullable', 'integer', 'min:1', 'max:14'],
            'session_minutes' => ['nullable', 'integer', 'min:15', 'max:180'],
            'ended_at' => ['nullable', 'date'],
            'status' => ['nullable', Rule::in(['active', 'paused', 'ended'])],
            'plan_summary' => ['nullable', 'string', 'max:4000'],
        ]);

        if (array_key_exists('specialist_id', $data) && $data['specialist_id']) {
            $this->refuseMismatchedSpecialist([
                'specialist_id' => $data['specialist_id'],
                'specialty' => $enrollment->specialty->value,
            ]);
        }

        $enrollment->update($data);

        return response()->json([
            'data' => $enrollment->fresh()->load('specialist:id,name,title'),
        ]);
    }

    public function destroy(Enrollment $enrollment): JsonResponse
    {
        if ($enrollment->sessions()->exists()) {
            return response()->json([
                'message' => 'البرنامج عليه جلسات مسجّلة — أنهِه بدل ما تحذفه، حتى يضلّ تاريخه محفوظ.',
            ], 422);
        }

        $enrollment->delete();

        return response()->json(['message' => 'تم حذف البرنامج.']);
    }

    /**
     * A speech therapist is not put on a sensory-integration case.
     *
     * Refused rather than warned, because an assignment nobody is qualified
     * for is not caught later — the reports come out looking exactly like
     * every other report, signed by someone whose name a parent will read as
     * an expert in something she is not.
     *
     * @param  array<string, mixed>  $data
     */
    private function refuseMismatchedSpecialist(array $data): void
    {
        if (empty($data['specialist_id'])) {
            return;
        }

        $specialist = User::find($data['specialist_id']);

        abort_unless(
            $specialist && $specialist->hasRole(Role::Specialist),
            422,
            'هذا الحساب ليس حساب أخصائية.',
        );

        if ($specialist->specialty?->value !== $data['specialty']) {
            abort(422, 'تخصّص الأخصائية لا يطابق تخصّص البرنامج.');
        }
    }

    /** @return array<string, mixed> */
    private function validated(Request $request): array
    {
        return $request->validate([
            'student_id' => ['required', 'exists:students,id'],
            'specialty' => ['required', Rule::in(Specialty::values())],
            'specialist_id' => ['nullable', 'exists:users,id'],
            'sessions_per_week' => ['nullable', 'integer', 'min:1', 'max:14'],
            'session_minutes' => ['nullable', 'integer', 'min:15', 'max:180'],
            'started_at' => ['required', 'date'],
            'plan_summary' => ['nullable', 'string', 'max:4000'],
        ]);
    }
}
