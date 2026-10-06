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
     * What closing this account would do, before anything is done.
     *
     * Both stores require that a person can close their account from inside
     * the app, and a screen that asks "هل أنت متأكد؟" without saying what is
     * about to disappear is not consent. The answer differs by who is asking,
     * so the server computes it and the screen prints what it is told rather
     * than carrying a second copy of the rule.
     */
    public function accountPreview(Request $request): JsonResponse
    {
        $user = $request->user();

        if ($user->isGuardian()) {
            $children = $user->children()->pluck('name');

            return response()->json(['data' => [
                'can_delete' => true,
                'title' => 'حذف حسابك',
                'what_goes' => [
                    'حسابك وكلمة مرورك، وكل جلسات الدخول المفتوحة.',
                    'ربطك بأطفالك — لن تصلك تقاريرهم بعد اليوم.',
                ],
                /*
                 * The child's record is the academy's, not the parent's.
                 *
                 * Saying so plainly is the point: a mother deleting her login
                 * is not asking for her son's therapy history to be destroyed,
                 * and an app that quietly did that would be deleting a
                 * clinical record on a misunderstanding.
                 */
                'what_stays' => [
                    'ملف ' . ($children->count() === 1 ? $children->first() : 'أطفالك')
                        . ' في الأكاديمية — الجلسات والتقارير والأهداف. هو سجلّ المركز عن خدمة قُدّمت، وليس بيانات حسابك.',
                ],
                'children' => $children,
            ]]);
        }

        // Staff. What they have written is the reason this is not symmetrical.
        $sessions = $user->sessions()->withTrashed()->count();
        $programmes = $user->enrollments()->count();

        if ($sessions === 0 && $programmes === 0) {
            return response()->json(['data' => [
                'can_delete' => true,
                'title' => 'حذف حسابك',
                'what_goes' => ['حسابك وكلمة مرورك، وكل جلسات الدخول المفتوحة.'],
                'what_stays' => [],
                'children' => [],
            ]]);
        }

        return response()->json(['data' => [
            'can_delete' => false,
            'title' => 'إغلاق حسابك',
            'what_goes' => [
                'كل جلسات الدخول المفتوحة — ولن تستطيع الدخول بعدها.',
            ],
            /*
             * Her name is on reports families have already read. Removing it
             * would leave those reports unsigned, which is worse for the
             * families than a dormant row in the staff table — so the account
             * is closed rather than erased, and she is told why.
             */
            'what_stays' => [
                "اسمك على {$sessions} جلسة و{$programmes} برنامج. التقارير التي أرسلتِها وصلت الأهل موقّعة باسمك، "
                    . 'وحذفه يترك تلك التقارير بلا كاتب — لذلك يُغلق الحساب ولا يُمحى.',
            ],
            'children' => [],
        ]]);
    }

    /**
     * Close it.
     *
     * A guardian's account goes; a member of staff who has written anything is
     * deactivated instead, for the reason the preview gave her. Either way she
     * is signed out of every device before this returns.
     */
    public function deleteAccount(Request $request): JsonResponse
    {
        $data = $request->validate([
            // Not ceremony: this is reached from a phone in a pocket, and the
            // password is the only thing proving the person holding it is the
            // one closing the account.
            'password' => ['required', 'string'],
        ]);

        $user = $request->user();

        if (! Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages([
                'password' => 'كلمة المرور غير صحيحة.',
            ]);
        }

        if ($user->isGuardian()) {
            $user->children()->detach();
            $user->tokens()->delete();
            $user->delete();

            return response()->json(['message' => 'تم حذف حسابك.']);
        }

        $erasable = $user->sessions()->withTrashed()->count() === 0
            && $user->enrollments()->count() === 0;

        if ($erasable) {
            $user->tokens()->delete();
            $user->delete();

            return response()->json(['message' => 'تم حذف حسابك.']);
        }

        $user->forceFill(['is_active' => false])->save();
        $user->tokens()->delete();

        return response()->json([
            'message' => 'تم إغلاق حسابك. لإعادة فتحه راجع إدارة الأكاديمية.',
        ]);
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
