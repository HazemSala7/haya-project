<?php

namespace App\Http\Controllers\Api;

use App\Enums\Role;
use App\Enums\Specialty;
use App\Http\Controllers\Controller;
use App\Models\Setting;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/**
 * Accounts and the academy's own details.
 *
 * Guardian accounts are created here too, by the office, rather than by
 * families signing themselves up. A parent who can register unaided can
 * register against any child, and the only thing standing between a stranger
 * and a disabled child's file would be a form field.
 */
class StaffController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $users = User::query()
            ->search($request->query('q'))
            ->when($request->filled('role'), fn ($q) => $q->where('role', $request->query('role')))
            ->when($request->filled('specialty'), fn ($q) => $q->where('specialty', $request->query('specialty')))
            ->when($request->has('active'), fn ($q) => $q->where('is_active', $request->boolean('active')))
            ->withCount('children')
            ->orderBy('name')
            ->paginate($this->perPage($request));

        return $this->paginated($users);
    }

    public function store(Request $request): JsonResponse
    {
        $data = $request->validate([
            'name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'unique:users,email'],
            // Six, not eight: these are handed over on a slip and typed
            // once on a phone keypad by somebody who did not choose them.
            'password' => ['nullable', 'string', 'min:6'],
            'role' => ['required', Rule::in(array_column(Role::cases(), 'value'))],
            'phone' => ['nullable', 'string', 'max:32'],
            'specialty' => ['nullable', Rule::in(Specialty::values())],
            'title' => ['nullable', 'string', 'max:120'],
        ]);

        $this->refuseSpecialtyMismatch($data);

        /*
         * A generated password when the office does not set one, handed back
         * once in this response and never retrievable again.
         *
         * The alternative is the office inventing "123456" for every family,
         * which is what happens when a form demands a password from someone
         * who is not the person who will use it.
         */
        $generated = null;

        if (blank($data['password'] ?? null)) {
            $generated = Str::password(10, symbols: false);
            $data['password'] = $generated;
        }

        $user = User::create($data);

        return response()->json([
            'data' => $user,
            'meta' => ['generated_password' => $generated],
        ], 201);
    }

    public function update(Request $request, User $user): JsonResponse
    {
        $data = $request->validate([
            'name' => ['sometimes', 'string', 'max:120'],
            'email' => ['sometimes', 'email', Rule::unique('users', 'email')->ignore($user->id)],
            'phone' => ['nullable', 'string', 'max:32'],
            'specialty' => ['nullable', Rule::in(Specialty::values())],
            'title' => ['nullable', 'string', 'max:120'],
            'is_active' => ['boolean'],
        ]);

        /*
         * The role is not editable.
         *
         * Flipping a guardian into a specialist would hand the family every
         * child's file in the building while leaving their existing links in
         * place; flipping a specialist into a guardian orphans everything she
         * signed. Neither is a mistake worth leaving reachable from a dropdown
         * — the safe path is a new account.
         */

        $data['specialty'] = $data['specialty'] ?? $user->specialty?->value;

        $this->refuseSpecialtyMismatch([
            'role' => $user->role->value,
            'specialty' => $data['specialty'],
        ]);

        // Switching someone off has to take effect now, not when their token
        // expires. The middleware revokes on the next request; this closes the
        // window before it.
        if (array_key_exists('is_active', $data) && ! $data['is_active']) {
            $user->tokens()->delete();
        }

        $user->update($data);

        return response()->json(['data' => $user->fresh()]);
    }

    /**
     * Remove an account.
     *
     * Refused for anyone who has already signed something. A specialist's name
     * sits at the bottom of every report she published, and the foreign key
     * nulls on delete — so deleting her would quietly unsign months of reports
     * that families have already read. "Who wrote this?" would answer "—".
     *
     * Switching her off is the operation that was actually wanted: she cannot
     * sign in, her tokens are revoked immediately, and the record stays whole.
     */
    public function destroy(Request $request, User $user): JsonResponse
    {
        if ($user->id === $request->user()->id) {
            return response()->json([
                'message' => 'ما بتقدر تحذف حسابك إنت.',
            ], 422);
        }

        $sessions = $user->sessions()->withTrashed()->count();
        $programmes = $user->enrollments()->count();

        if ($sessions > 0 || $programmes > 0) {
            return response()->json([
                'message' => "هذا الحساب عليه {$sessions} جلسة و{$programmes} برنامج — اسمه موقّع على تقارير وصلت الأهل. أوقفه بدل ما تحذفه.",
            ], 422);
        }

        // A guardian's links go with them; the children themselves do not.
        $user->children()->detach();
        $user->tokens()->delete();
        $user->delete();

        return response()->json(['message' => 'تم حذف الحساب.']);
    }

    /** Set a new password for someone who has lost theirs. */
    public function resetPassword(Request $request, User $user): JsonResponse
    {
        $data = $request->validate([
            // Six, not eight: these are handed over on a slip and typed
            // once on a phone keypad by somebody who did not choose them.
            'password' => ['nullable', 'string', 'min:6'],
        ]);

        $password = $data['password'] ?? Str::password(10, symbols: false);

        $user->update(['password' => $password]);

        // Every session they had is gone. A reset that leaves the old sessions
        // alive has not actually reset anything.
        $user->tokens()->delete();

        return response()->json([
            'message' => 'تم تعيين كلمة مرور جديدة.',
            'meta' => ['generated_password' => $password],
        ]);
    }

    /** The families attached to this guardian account, for the office. */
    public function children(User $user): JsonResponse
    {
        abort_unless($user->isGuardian(), 422, 'هذا الحساب ليس حساب ولي أمر.');

        return response()->json([
            'data' => $user->children()->get(['students.id', 'name', 'file_number', 'status']),
        ]);
    }

    /* ---------------------------------------------------------------------
     | Settings
     |------------------------------------------------------------------- */

    public function settings(): JsonResponse
    {
        return response()->json(['data' => Setting::map()]);
    }

    public function updateSettings(Request $request): JsonResponse
    {
        $data = $request->validate([
            'academy_name' => ['nullable', 'string', 'max:120'],
            'phone' => ['nullable', 'string', 'max:32'],
            'address' => ['nullable', 'string', 'max:200'],
            'email' => ['nullable', 'email', 'max:120'],
            'report_footer' => ['nullable', 'string', 'max:500'],
        ]);

        foreach ($data as $key => $value) {
            Setting::put($key, $value);
        }

        return response()->json(['data' => Setting::map()]);
    }

    /**
     * A specialty belongs to a specialist and to nobody else.
     *
     * @param  array<string, mixed>  $data
     */
    private function refuseSpecialtyMismatch(array $data): void
    {
        $isSpecialist = ($data['role'] ?? null) === Role::Specialist->value;

        if ($isSpecialist && blank($data['specialty'] ?? null)) {
            abort(422, 'اختر تخصّص الأخصائية.');
        }

        if (! $isSpecialist && filled($data['specialty'] ?? null)) {
            abort(422, 'التخصّص بينحط للأخصائيات فقط.');
        }
    }
}
