<?php

namespace App\Http\Controllers\Api;

use App\Enums\PromptLevel;
use App\Http\Controllers\Controller;
use App\Models\Enrollment;
use App\Models\Goal;
use App\Models\Student;
use App\Services\Progress;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class GoalController extends Controller
{
    public function __construct(private Progress $progress) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $goals = Goal::query()
            ->when($request->filled('student_id'), fn ($q) => $q->where('student_id', $request->query('student_id')))
            ->when($request->filled('enrollment_id'), fn ($q) => $q->where('enrollment_id', $request->query('enrollment_id')))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->query('status')))
            // A family reads their own children's goals and no one else's.
            ->when($user->isGuardian(), fn ($q) => $q->whereHas(
                'student.guardians',
                fn ($g) => $g->where('users.id', $user->id),
            ))
            ->with([
                'enrollment:id,specialty',
                'student:id,name,file_number',
                'ratings' => fn ($q) => $q->reorder('measured_at', 'desc')->limit(1),
            ])
            ->ordered()
            ->paginate($this->perPage($request, 50));

        // The two numbers that make a goal row mean something: where he is now
        // and how far that is from where he began.
        foreach ($goals->items() as $goal) {
            $goal->setAttribute('trend', $goal->trend());
        }

        return $this->paginated($goals);
    }

    /**
     * The curve.
     *
     * The single screen that justifies the whole scoring discipline — every
     * session's rating for one goal, from the baseline forward.
     */
    public function show(Request $request, Goal $goal): JsonResponse
    {
        $student = Student::findOrFail($goal->student_id);

        abort_unless($student->readableBy($request->user()), 404, 'العنصر المطلوب غير موجود.');

        return response()->json(['data' => $this->progress->goalCurve($goal)]);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request);

        $enrollment = Enrollment::findOrFail($data['enrollment_id']);

        // The goal hangs off a programme, so the child is the programme's
        // child — never one the caller nominated. A goal filed against the
        // wrong student pollutes two curves at once.
        $data['student_id'] = $enrollment->student_id;
        $data['started_at'] = $data['started_at'] ?? now()->toDateString();
        $data['sort_order'] = $data['sort_order']
            ?? ((int) Goal::where('enrollment_id', $enrollment->id)->max('sort_order') + 1);

        return response()->json(['data' => Goal::create($data)], 201);
    }

    public function update(Request $request, Goal $goal): JsonResponse
    {
        $data = $request->validate([
            'title' => ['sometimes', 'string', 'max:200'],
            'description' => ['nullable', 'string', 'max:2000'],
            'criteria' => ['nullable', 'string', 'max:200'],
            'target' => ['nullable', 'integer', Rule::in(array_column(PromptLevel::cases(), 'value'))],
            'status' => ['nullable', Rule::in(['active', 'achieved', 'paused', 'dropped'])],
            'sort_order' => ['nullable', 'integer', 'min:0', 'max:999'],
        ]);

        /*
         * `baseline` is deliberately not editable.
         *
         * It is the number every curve is measured against. Letting it be
         * revised after the fact would let a goal that went nowhere be made to
         * look like progress by lowering where it started — which is precisely
         * the thing a parent is trusting this system not to do.
         */

        if (($data['status'] ?? null) === 'achieved' && ! $goal->achieved_at) {
            $data['achieved_at'] = now()->toDateString();
        }

        if (($data['status'] ?? null) === 'active') {
            $data['achieved_at'] = null;
        }

        $goal->update($data);

        return response()->json(['data' => $goal->fresh()]);
    }

    public function destroy(Goal $goal): JsonResponse
    {
        if ($goal->ratings()->exists()) {
            return response()->json([
                'message' => 'الهدف عليه قياسات — أوقفه أو علّمه محقّقاً بدل ما تحذفه.',
            ], 422);
        }

        $goal->delete();

        return response()->json(['message' => 'تم حذف الهدف.']);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request): array
    {
        return $request->validate([
            'enrollment_id' => ['required', 'exists:enrollments,id'],
            'title' => ['required', 'string', 'max:200'],
            'description' => ['nullable', 'string', 'max:2000'],
            'criteria' => ['nullable', 'string', 'max:200'],
            'baseline' => ['required', 'integer', Rule::in(array_column(PromptLevel::cases(), 'value'))],
            'target' => ['nullable', 'integer', Rule::in(array_column(PromptLevel::cases(), 'value'))],
            'started_at' => ['nullable', 'date'],
            'sort_order' => ['nullable', 'integer', 'min:0', 'max:999'],
        ]);
    }
}
