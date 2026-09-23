<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

class AuthController extends Controller
{
    public function login(Request $request): JsonResponse
    {
        $data = $request->validate([
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
        ]);

        $user = User::where('email', $data['email'])->first();

        // One message for both failures on purpose: telling a stranger that an
        // address exists but the password is wrong is telling them half of it.
        if (! $user || ! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages([
                'email' => 'البريد الإلكتروني أو كلمة المرور غير صحيحة.',
            ]);
        }

        if (! $user->is_active) {
            throw ValidationException::withMessages([
                'email' => 'هذا الحساب موقوف. راجع إدارة الأكاديمية.',
            ]);
        }

        $user->forceFill(['last_seen_at' => now()])->saveQuietly();

        return response()->json([
            'token' => $user->createToken('haya')->plainTextToken,
            'data' => $this->profile($user),
        ]);
    }

    public function me(Request $request): JsonResponse
    {
        return response()->json(['data' => $this->profile($request->user())]);
    }

    public function logout(Request $request): JsonResponse
    {
        $request->user()->currentAccessToken()->delete();

        return response()->json(['message' => 'تم تسجيل الخروج.']);
    }

    public function changePassword(Request $request): JsonResponse
    {
        $data = $request->validate([
            'current_password' => ['required', 'string'],
            'password' => ['required', 'string', 'min:8', 'confirmed'],
        ]);

        $user = $request->user();

        if (! Hash::check($data['current_password'], $user->password)) {
            throw ValidationException::withMessages([
                'current_password' => 'كلمة المرور الحالية غير صحيحة.',
            ]);
        }

        $user->update(['password' => $data['password']]);

        // Every other session is signed out — a password change that leaves
        // the old sessions alive has not actually changed anything.
        $user->tokens()
            ->where('id', '!=', $request->user()->currentAccessToken()->id)
            ->delete();

        return response()->json(['message' => 'تم تغيير كلمة المرور.']);
    }

    /**
     * Everything the frontend needs to draw the right menu, and nothing more.
     *
     * `children` is here rather than behind another request because a parent's
     * whole app is scoped to it: the shell cannot render its first screen
     * without knowing whether this family has one child or three.
     *
     * @return array<string, mixed>
     */
    private function profile(User $user): array
    {
        $profile = [
            'id' => $user->id,
            'name' => $user->name,
            'email' => $user->email,
            'phone' => $user->phone,
            'role' => $user->role->value,
            'role_label' => $user->role->label(),
            'title' => $user->title,
            'specialty' => $user->specialty?->value,
            'specialty_label' => $user->specialty?->fullLabel(),
            'is_staff' => $user->role->isStaff(),
        ];

        if ($user->isGuardian()) {
            $profile['children'] = $user->children()
                ->select('students.id', 'students.name', 'students.file_number', 'students.status')
                ->get()
                ->map(fn ($child) => [
                    'id' => $child->id,
                    'name' => $child->name,
                    'file_number' => $child->file_number,
                    'status' => $child->status,
                    'relation' => $child->pivot->relation,
                ]);
        }

        return $profile;
    }
}
