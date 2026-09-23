<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Student;
use App\Models\User;
use App\Services\DocumentNumbers;
use App\Services\Progress;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\Rule;

class StudentController extends Controller
{
    public function __construct(
        private DocumentNumbers $numbers,
        private Progress $progress,
    ) {}

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $students = Student::query()
            ->visibleTo($user)
            /*
             * Archived files are reachable, not gone. A child who left in June
             * is often back in September, and a family told "your son's two
             * years of records are gone" is a family that tells everyone.
             */
            ->when($request->boolean('archived'), fn ($q) => $q->onlyTrashed())
            ->search($request->query('q'))
            ->when($request->filled('status'), fn ($q) => $q->where('status', $request->query('status')))
            /*
             * "مين طلابي؟" — the filter a specialist opens the screen with.
             * Not the default, because covering for a colleague is the case
             * where she needs everyone, and a filter she has to switch off is
             * a filter she will not notice is on.
             */
            ->when($request->filled('specialist_id'), fn ($q) => $q->whereHas(
                'enrollments',
                fn ($e) => $e->active()->where('specialist_id', $request->query('specialist_id')),
            ))
            ->when($request->filled('specialty'), fn ($q) => $q->whereHas(
                'enrollments',
                fn ($e) => $e->active()->where('specialty', $request->query('specialty')),
            ))
            ->withCount(['enrollments' => fn ($q) => $q->active()])
            ->orderBy('name')
            ->paginate($this->perPage($request));

        return $this->paginated($students);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $this->validated($request);

        $data['file_number'] = $this->numbers->studentFile();

        $student = Student::create($data);

        return response()->json(['data' => $student], 201);
    }

    /**
     * The child's file.
     *
     * Everything a specialist needs before she opens the door, and everything
     * a parent's home screen is built from — in one request, because both are
     * the first screen after a tap and a second round trip is a spinner where
     * a name should be.
     *
     * Counts and summaries only. The sessions themselves come from
     * `GET /sessions?student_id=…`, which is paged: a child two years into
     * therapy has three hundred of them.
     */
    public function show(Request $request, Student $student): JsonResponse
    {
        $user = $request->user();

        abort_unless($student->readableBy($user), 404, 'العنصر المطلوب غير موجود.');

        $student->load([
            'guardians:id,name,phone,email',
            'enrollments' => fn ($q) => $q->active()->with('specialist:id,name,title'),
        ]);

        return response()->json([
            'data' => $student,
            'meta' => $this->progress->studentSummary($student, $user),
        ]);
    }

    public function update(Request $request, Student $student): JsonResponse
    {
        $student->update($this->validated($request, $student));

        return response()->json(['data' => $student->fresh()]);
    }

    /**
     * Filed away, not destroyed — the model soft-deletes.
     *
     * A child who leaves in June is often back in September, and a family that
     * comes back to be told their son's two years of records are gone is a
     * family that tells everyone.
     */
    public function destroy(Student $student): JsonResponse
    {
        $student->delete();

        return response()->json(['message' => 'تم أرشفة ملف الطالب.']);
    }

    /** Bring an archived file back — the September case. */
    public function restore(int $student): JsonResponse
    {
        $record = Student::onlyTrashed()->findOrFail($student);
        $record->restore();

        return response()->json(['data' => $record->fresh(), 'message' => 'تم استرجاع الملف.']);
    }

    /* ---------------------------------------------------------------------
     | Guardians
     |------------------------------------------------------------------- */

    /**
     * Give a family access to this child's file.
     *
     * Attaching an existing account rather than creating one, because a mother
     * with two children here must end up with one login that opens both — and
     * a "create parent" button on a child's screen is how she ends up with
     * two, each showing her half of her family.
     */
    public function attachGuardian(Request $request, Student $student): JsonResponse
    {
        $data = $request->validate([
            'user_id' => ['required', 'exists:users,id'],
            'relation' => ['required', Rule::in(['father', 'mother', 'grandparent', 'sibling', 'guardian'])],
            'is_primary' => ['boolean'],
        ]);

        $guardian = User::findOrFail($data['user_id']);

        if (! $guardian->isGuardian()) {
            return response()->json([
                'message' => 'هذا الحساب ليس حساب ولي أمر.',
            ], 422);
        }

        // Exactly one first contact per child.
        if ($request->boolean('is_primary')) {
            $student->guardians()->newPivotQuery()->update(['is_primary' => false]);
        }

        $student->guardians()->syncWithoutDetaching([
            $guardian->id => [
                'relation' => $data['relation'],
                'is_primary' => $request->boolean('is_primary'),
            ],
        ]);

        return response()->json([
            'data' => $student->fresh()->load('guardians:id,name,phone,email'),
        ]);
    }

    public function detachGuardian(Student $student, User $user): JsonResponse
    {
        $student->guardians()->detach($user->id);

        return response()->json(['message' => 'تم إلغاء ربط ولي الأمر بالطالب.']);
    }

    /** @return array<string, mixed> */
    private function validated(Request $request, ?Student $student = null): array
    {
        return $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'birth_date' => ['required', 'date', 'before:today'],
            'gender' => ['required', Rule::in(['male', 'female'])],
            'national_id' => ['nullable', 'string', 'max:24'],
            'diagnosis' => ['nullable', 'string', 'max:160'],
            'diagnosis_notes' => ['nullable', 'string', 'max:4000'],
            'medical_alert' => ['nullable', 'string', 'max:1000'],
            'school' => ['nullable', 'string', 'max:120'],
            'grade' => ['nullable', 'string', 'max:40'],
            'enrolled_at' => ['required', 'date'],
            'status' => ['nullable', Rule::in(['active', 'paused', 'graduated', 'withdrawn'])],
            'left_at' => ['nullable', 'date', 'after_or_equal:enrolled_at'],
            'notes' => ['nullable', 'string', 'max:4000'],
        ]);
    }
}
