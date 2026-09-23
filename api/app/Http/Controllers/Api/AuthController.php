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
        /*
         * The field takes an email OR a mobile number.
         *
         * It used to validate `email` strictly, while the app's own field said
         * «البريد الإلكتروني أو رقم الهاتف» — so a specialist who typed the
         * number she was given was told her address was invalid. She is signing
         * in on a phone keypad, where an address with an `@` in it is the
         * hardest thing to type and the easiest to get wrong.
         *
         * The key stays `email` because the dashboard already sends it.
         */
        $data = $request->validate([
            'email' => ['required', 'string', 'max:255'],
            'password' => ['required', 'string'],
        ]);

        $identifier = trim($data['email']);
        $digits = self::digits($identifier);

        $user = str_contains($identifier, '@')
            ? User::whereRaw('LOWER(email) = ?', [mb_strtolower($identifier)])->first()
            : self::byPhone($digits);

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
            // Matches what the office can set, so a person cannot be
            // refused a password the academy itself just gave them.
            'password' => ['required', 'string', 'min:6', 'confirmed'],
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

    /**
     * A Palestinian mobile reduced to the digits that identify it.
     *
     * The same phone is written five ways by five people — `0599085820`,
     * `599085820`, `+970599085820`, `059 908 5820`, `٠٥٩٩٠٨٥٨٢٠` — and the
     * office types one of them into the file while the mother types another
     * into this screen. Comparing what was stored against what was typed only
     * works if both are first reduced to the same thing, so both ends are cut
     * down to the nine digits after the country code and the leading zero.
     */
    private static function digits(string $value): string
    {
        $arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
        $latin = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

        $d = preg_replace('/\D/', '', str_replace($arabic, $latin, $value)) ?? '';

        foreach (['00970', '00972', '970', '972'] as $prefix) {
            if (str_starts_with($d, $prefix)) {
                $d = substr($d, strlen($prefix));
                break;
            }
        }

        return ltrim($d, '0');
    }

    /**
     * The one account that number belongs to, or none.
     *
     * A number reaching two accounts returns null rather than the first match:
     * guessing which of two people is signing in is the one mistake here that
     * hands somebody another family's children.
     */
    private static function byPhone(string $digits): ?User
    {
        if (strlen($digits) < 8) {
            return null;
        }

        $matches = User::whereNotNull('phone')->get()
            ->filter(fn (User $user) => self::digits((string) $user->phone) === $digits);

        return $matches->count() === 1 ? $matches->first() : null;
    }
}
