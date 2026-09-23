<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\ProgressReport;
use App\Models\Student;
use App\Services\Progress;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

/**
 * التقرير الدوري — the quarter, not the day.
 */
class ProgressReportController extends Controller
{
    public function __construct(private Progress $progress) {}

    public function index(Request $request): JsonResponse
    {
        $reports = ProgressReport::query()
            ->visibleTo($request->user())
            ->when($request->filled('student_id'), fn ($q) => $q->where('student_id', $request->query('student_id')))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->query('status')))
            ->with([
                'student:id,name,file_number',
                'author:id,name,title',
                'enrollment:id,specialty',
            ])
            ->orderByDesc('period_end')
            ->paginate($this->perPage($request));

        return $this->paginated($reports);
    }

    public function show(Request $request, ProgressReport $report): JsonResponse
    {
        $visible = ProgressReport::whereKey($report->id)
            ->visibleTo($request->user())
            ->exists();

        abort_unless($visible, 404, 'العنصر المطلوب غير موجود.');

        return response()->json([
            'data' => $report->load([
                'student:id,name,file_number,birth_date,diagnosis',
                'author:id,name,title',
                'enrollment:id,specialty,plan_summary',
            ]),
        ]);
    }

    /**
     * Open a periodic report with the figures already in it.
     *
     * The attendance and goal numbers for the period come back alongside the
     * blank form, so the specialist writes her paragraphs against the same
     * arithmetic the parent will see underneath them. A report whose prose and
     * whose figures were assembled separately is a report that eventually
     * contradicts itself in front of a family.
     */
    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'student_id' => ['required', 'exists:students,id'],
            'enrollment_id' => ['nullable', 'exists:enrollments,id'],
            'period_start' => ['required', 'date'],
            'period_end' => ['required', 'date', 'after_or_equal:period_start'],
            'summary' => ['required', 'string', 'max:8000'],
            'achieved' => ['nullable', 'string', 'max:8000'],
            'recommendations' => ['nullable', 'string', 'max:8000'],
            'home_program' => ['nullable', 'string', 'max:8000'],
        ]);

        $data['author_id'] = $request->user()->id;

        $report = ProgressReport::create($data);

        return response()->json(['data' => $report->fresh()], 201);
    }

    public function update(Request $request, ProgressReport $report): JsonResponse
    {
        if ($report->isPublished()) {
            return response()->json([
                'message' => 'التقرير مُرسل — ما بينعدّل بعد ما وصل الأهل.',
            ], 422);
        }

        $data = $request->validate([
            'period_start' => ['sometimes', 'date'],
            'period_end' => ['sometimes', 'date'],
            'summary' => ['sometimes', 'string', 'max:8000'],
            'achieved' => ['nullable', 'string', 'max:8000'],
            'recommendations' => ['nullable', 'string', 'max:8000'],
            'home_program' => ['nullable', 'string', 'max:8000'],
        ]);

        $report->update($data);

        return response()->json(['data' => $report->fresh()]);
    }

    public function publish(ProgressReport $report): JsonResponse
    {
        if ($report->isPublished()) {
            return response()->json(['message' => 'التقرير مُرسل من قبل.'], 422);
        }

        $report->update(['status' => 'published', 'published_at' => now()]);

        return response()->json([
            'data' => $report->fresh(),
            'message' => 'تم إرسال التقرير الدوري لولي الأمر.',
        ]);
    }

    public function destroy(ProgressReport $report): JsonResponse
    {
        if ($report->isPublished()) {
            return response()->json([
                'message' => 'التقرير مُرسل — ما بينحذف.',
            ], 422);
        }

        $report->delete();

        return response()->json(['message' => 'تم حذف التقرير.']);
    }

    /**
     * The figures for a period, before anything has been written.
     *
     * `GET /progress-reports/figures?student_id=…&from=…&to=…`
     */
    public function figures(Request $request): JsonResponse
    {
        $request->validate([
            'student_id' => ['required', 'exists:students,id'],
        ]);

        $student = Student::findOrFail($request->query('student_id'));

        abort_unless($student->readableBy($request->user()), 404, 'العنصر المطلوب غير موجود.');

        $goals = $student->goals()->with('ratings')->ordered()->get();

        return response()->json([
            'data' => [
                'summary' => $this->progress->studentSummary($student, $request->user()),
                'goals' => $goals->map(fn ($goal) => [
                    'id' => $goal->id,
                    'title' => $goal->title,
                    'status' => $goal->status,
                    'baseline' => $goal->baseline,
                    'target' => $goal->target,
                    ...$goal->trend(),
                ]),
            ],
        ]);
    }
}
