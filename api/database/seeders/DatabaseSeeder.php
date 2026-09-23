<?php

namespace Database\Seeders;

use App\Enums\Role;
use App\Enums\Specialty;
use App\Models\Enrollment;
use App\Models\Goal;
use App\Models\ProgressReport;
use App\Models\Setting;
use App\Models\Student;
use App\Models\TherapySession;
use App\Models\User;
use App\Services\DocumentNumbers;
use App\Services\ReportDesk;
use Illuminate\Database\Seeder;
use Illuminate\Support\Carbon;

/**
 * An academy that has been open a couple of terms.
 *
 * Everything that can go through the real services does — reports are
 * published by ReportDesk, so they obey the same completeness rules a
 * specialist is held to, and the goal curves are made of ratings written one
 * session at a time. A demo whose numbers were typed in by hand proves nothing
 * about whether the numbers work.
 *
 * The children are invented, and deliberately not uniformly successful: one is
 * plateaued, one regressed after a hospital stay, one family has not opened a
 * report since October. A seed where every case improves is a seed that hides
 * exactly the screens this system was built to surface.
 */
class DatabaseSeeder extends Seeder
{
    /** Rotates the weekday pair so the children are spread across the week. */
    private static int $programmeCount = 0;

    private DocumentNumbers $numbers;

    private ReportDesk $desk;

    public function run(DocumentNumbers $numbers, ReportDesk $desk): void
    {
        $this->numbers = $numbers;
        $this->desk = $desk;

        $this->settings();

        $admin = User::create([
            'name' => 'هدى النتشة',
            'email' => 'admin@haya.test',
            'password' => 'password',
            'role' => Role::Admin,
            'phone' => '0599110220',
            'title' => 'مديرة الأكاديمية',
        ]);

        $specialists = $this->specialists();
        $guardians = $this->guardians();

        $this->students($specialists, $guardians, $admin);
    }

    private function settings(): void
    {
        foreach ([
            'academy_name' => 'أكاديمية الحياة للتأهيل',
            'phone' => '022345678',
            'address' => 'الخليل — شارع عين سارة، عمارة الحياة، الطابق الثاني',
            'email' => 'info@haya-academy.ps',
            'report_footer' => 'هذا التقرير خاص بولي الأمر ولا يُستخدم كوثيقة تشخيصية رسمية.',
        ] as $key => $value) {
            Setting::put($key, $value);
        }
    }

    /** @return array<string, User> keyed by specialty value */
    private function specialists(): array
    {
        $rows = [
            ['name' => 'رنا أبو سنينة', 'email' => 'rana@haya.test', 'specialty' => Specialty::Speech, 'title' => 'أخصائية نطق ولغة'],
            ['name' => 'آية الجعبري', 'email' => 'aya@haya.test', 'specialty' => Specialty::Occupational, 'title' => 'أخصائية علاج وظيفي'],
            ['name' => 'سُهى القواسمي', 'email' => 'suha@haya.test', 'specialty' => Specialty::Behavioral, 'title' => 'أخصائية تعديل سلوك — معالجة ABA'],
            ['name' => 'دعاء الشريف', 'email' => 'duaa@haya.test', 'specialty' => Specialty::SpecialEd, 'title' => 'معلمة تربية خاصة'],
            ['name' => 'لمى إدريس', 'email' => 'lama@haya.test', 'specialty' => Specialty::Speech, 'title' => 'أخصائية تخاطب'],
        ];

        $out = [];

        foreach ($rows as $row) {
            $user = User::create([
                'name' => $row['name'],
                'email' => $row['email'],
                'password' => 'password',
                'role' => Role::Specialist,
                'specialty' => $row['specialty'],
                'title' => $row['title'],
                'phone' => '059'.rand(1000000, 9999999),
                'last_seen_at' => now()->subHours(rand(1, 20)),
            ]);

            $out[$row['specialty']->value][] = $user;
        }

        return $out;
    }

    /** @return array<int, User> */
    private function guardians(): array
    {
        $names = [
            ['أم يوسف — سناء دعنا', 'sanaa@haya.test'],
            ['أبو يوسف — كمال دعنا', 'kamal@haya.test'],
            ['أم ليان — رغد التميمي', 'raghad@haya.test'],
            ['أم آدم — نور عمرو', 'noor@haya.test'],
            ['أبو زين — محمد سلهب', 'msalhab@haya.test'],
            ['أم سارة — إيمان زلوم', 'iman@haya.test'],
            ['أم كرم — هناء الرجبي', 'hanaa@haya.test'],
            ['أبو تالا — سامي الحلايقة', 'sami@haya.test'],
            ['أم جنى — ولاء أبو ريان', 'walaa@haya.test'],
        ];

        return collect($names)->map(fn ($row, $i) => User::create([
            'name' => $row[0],
            'email' => $row[1],
            'password' => 'password',
            'role' => Role::Guardian,
            'phone' => '059'.rand(1000000, 9999999),
            // One family has stopped opening the app — see the admin
            // dashboard's "silent_families" panel, which exists to find them.
            'last_seen_at' => $i === 6 ? now()->subDays(38) : now()->subDays(rand(0, 5)),
        ]))->all();
    }

    /**
     * @param  array<string, array<int, User>>  $specialists
     * @param  array<int, User>  $guardians
     */
    private function students(array $specialists, array $guardians, User $admin): void
    {
        /*
         * Each row: the child, who reads his file, and which programmes he is
         * in. `arc` shapes how his ratings move — the demo is only honest if
         * some children plateau and one goes backwards.
         */
        $roster = [
            [
                'name' => 'يوسف كمال دعنا', 'birth' => '2020-03-14', 'gender' => 'male',
                'diagnosis' => 'اضطراب طيف التوحد — درجة متوسطة',
                'alert' => 'حساسية من الفول السوداني. لا يُعطى أي طعام دون الرجوع للأم.',
                'guardians' => [[0, 'mother', true], [1, 'father', false]],
                'programmes' => [Specialty::Behavioral, Specialty::Speech],
                'arc' => 'steady_climb',
            ],
            [
                'name' => 'ليان أحمد التميمي', 'birth' => '2019-11-02', 'gender' => 'female',
                'diagnosis' => 'تأخر لغوي نمائي',
                'alert' => null,
                'guardians' => [[2, 'mother', true]],
                'programmes' => [Specialty::Speech],
                'arc' => 'fast_climb',
            ],
            [
                'name' => 'آدم رائد عمرو', 'birth' => '2021-06-20', 'gender' => 'male',
                'diagnosis' => 'تأخر نمائي شامل',
                'alert' => 'يتناول دواء Keppra صباحاً ومساءً — تاريخ تشنجات. عند أي نوبة يُتصل بالأم فوراً.',
                'guardians' => [[3, 'mother', true]],
                'programmes' => [Specialty::Occupational, Specialty::Speech],
                'arc' => 'setback',
            ],
            [
                'name' => 'زين محمد سلهب', 'birth' => '2018-01-09', 'gender' => 'male',
                'diagnosis' => 'فرط حركة وتشتت انتباه',
                'alert' => null,
                'guardians' => [[4, 'father', true]],
                'programmes' => [Specialty::Behavioral, Specialty::SpecialEd],
                'arc' => 'plateau',
            ],
            [
                'name' => 'سارة عماد زلوم', 'birth' => '2017-09-25', 'gender' => 'female',
                'diagnosis' => 'صعوبات تعلّم — عسر قراءة',
                'alert' => null,
                'guardians' => [[5, 'mother', true]],
                'programmes' => [Specialty::SpecialEd],
                'arc' => 'steady_climb',
            ],
            [
                'name' => 'كرم بلال الرجبي', 'birth' => '2020-12-11', 'gender' => 'male',
                'diagnosis' => 'متلازمة داون',
                'alert' => 'ضعف في عضلات الرقبة — يُدعم الرأس عند الجلوس على الكرة.',
                'guardians' => [[6, 'mother', true]],
                'programmes' => [Specialty::Occupational, Specialty::Speech],
                'arc' => 'slow_climb',
            ],
            [
                'name' => 'تالا سامي الحلايقة', 'birth' => '2019-04-30', 'gender' => 'female',
                'diagnosis' => 'شلل دماغي — نصفي أيمن',
                'alert' => 'جبيرة يد يمنى تُنزع أثناء الجلسة وتُعاد قبل الخروج.',
                'guardians' => [[7, 'father', true]],
                'programmes' => [Specialty::Occupational],
                'arc' => 'slow_climb',
            ],
            [
                'name' => 'جنى ياسر أبو ريان', 'birth' => '2021-02-18', 'gender' => 'female',
                'diagnosis' => 'تأخر نطق بسيط',
                'alert' => null,
                'guardians' => [[8, 'mother', true]],
                'programmes' => [Specialty::Speech],
                'arc' => 'fast_climb',
            ],
        ];

        foreach ($roster as $index => $row) {
            $student = Student::create([
                'file_number' => $this->numbers->studentFile(),
                'name' => $row['name'],
                'birth_date' => $row['birth'],
                'gender' => $row['gender'],
                'diagnosis' => $row['diagnosis'],
                'medical_alert' => $row['alert'],
                'school' => $index % 3 === 0 ? null : 'مدرسة الأمل الأساسية',
                'grade' => $index % 3 === 0 ? null : 'الصف الأول',
                'enrolled_at' => now()->subMonths(rand(4, 10))->toDateString(),
                'status' => 'active',
            ]);

            foreach ($row['guardians'] as [$g, $relation, $primary]) {
                $student->guardians()->attach($guardians[$g]->id, [
                    'relation' => $relation,
                    'is_primary' => $primary,
                ]);
            }

            foreach ($row['programmes'] as $specialty) {
                $pool = $specialists[$specialty->value];
                $specialist = $pool[array_rand($pool)];

                $enrollment = Enrollment::create([
                    'student_id' => $student->id,
                    'specialty' => $specialty,
                    'specialist_id' => $specialist->id,
                    'sessions_per_week' => 2,
                    'session_minutes' => 45,
                    'started_at' => $student->enrolled_at,
                    'status' => 'active',
                    'plan_summary' => $this->planSummary($specialty),
                ]);

                $goals = $this->goals($enrollment, $specialty);

                $this->sessions($enrollment, $specialist, $goals, $row['arc']);
            }

            $this->progressReports($student, $row['arc']);

            $this->conversation($student, $guardians[$row['guardians'][0][0]], $admin);
        }

        /*
         * One live programme with nobody on it — the therapist who ran it left.
         * It is the queue the admin dashboard's "unassigned" count points at,
         * and it only proves anything if the seed actually contains one.
         */
        Enrollment::create([
            'student_id' => Student::where('name', 'like', 'زين%')->value('id'),
            'specialty' => Specialty::Occupational,
            'specialist_id' => null,
            'sessions_per_week' => 1,
            'session_minutes' => 30,
            'started_at' => now()->subWeeks(2)->toDateString(),
            'status' => 'active',
            'plan_summary' => 'بانتظار إسناد أخصائية بعد استقالة الأخصائية السابقة.',
        ]);
    }

    private function planSummary(Specialty $specialty): string
    {
        return match ($specialty) {
            Specialty::Speech => 'تنمية اللغة الاستقبالية والتعبيرية، وتصحيح مخارج الأصوات، والانتقال من الكلمة المفردة إلى الجملة القصيرة.',
            Specialty::Occupational => 'تحسين المهارات الحركية الدقيقة والتكامل الحسي، ورفع الاستقلالية في مهارات العناية بالذات.',
            Specialty::Behavioral => 'تقليل السلوكيات غير المرغوبة وزيادة مدة الجلوس والانتباه المشترك، وبناء نظام تواصل وظيفي.',
            Specialty::SpecialEd => 'بناء المهارات الأكاديمية الأساسية في القراءة والكتابة والحساب وفق خطة تربوية فردية.',
        };
    }

    /** @return array<int, Goal> */
    private function goals(Enrollment $enrollment, Specialty $specialty): array
    {
        $sets = [
            Specialty::Speech->value => [
                ['ينطق صوت /س/ في بداية الكلمة', '٨ من ١٠ محاولات في ٣ جلسات متتالية', 0],
                ['يسمّي ١٠ صور من البطاقات دون نموذج', '١٠ صور صحيحة في جلستين', 1],
                ['يركّب جملة من كلمتين للطلب', '٥ طلبات تلقائية خلال الجلسة', 0],
                ['ينفّذ أمراً من خطوتين', '٤ من ٥ أوامر', 1],
            ],
            Specialty::Occupational->value => [
                ['يمسك القلم بقبضة ثلاثية', '٣ جلسات متتالية دون تصحيح', 1],
                ['يقصّ على خط مستقيم طوله ١٠ سم', 'انحراف أقل من ١ سم', 0],
                ['يزرّر ٣ أزرار لحاله', '٣ أزرار خلال دقيقتين', 0],
                ['يتحمّل نشاط التكامل الحسي ٥ دقائق', '٥ دقائق دون انسحاب', 1],
            ],
            Specialty::Behavioral->value => [
                ['يجلس على الكرسي ٥ دقائق دون قيام', '٤ من ٥ محاولات', 0],
                ['ينظر لعين المعالجة عند مناداته باسمه', '٨ من ١٠ مناداة', 1],
                ['يطلب بالإشارة أو الكلمة بدل الصراخ', '٧٠٪ من الطلبات', 0],
                ['ينتظر دوره في لعبة جماعية', '٣ أدوار متتالية', 0],
            ],
            Specialty::SpecialEd->value => [
                ['يقرأ ١٥ كلمة بصرية شائعة', '١٥ كلمة في دقيقة', 1],
                ['يكتب اسمه دون نموذج', '٣ مرات متتالية', 1],
                ['يجمع ضمن العشرة باستخدام الوسائل', '٨ من ١٠ مسائل', 0],
                ['يميّز الحروف المتشابهة بصرياً', '٩ من ١٠', 0],
            ],
        ];

        $goals = [];

        foreach ($sets[$specialty->value] as $i => [$title, $criteria, $baseline]) {
            $goals[] = Goal::create([
                'student_id' => $enrollment->student_id,
                'enrollment_id' => $enrollment->id,
                'title' => $title,
                'criteria' => $criteria,
                'baseline' => $baseline,
                'target' => 4,
                'status' => 'active',
                'started_at' => $enrollment->started_at,
                'sort_order' => $i + 1,
            ]);
        }

        return $goals;
    }

    /**
     * Ten weeks of sessions, twice a week, written up as they went.
     *
     * @param  array<int, Goal>  $goals
     */
    private function sessions(Enrollment $enrollment, User $specialist, array $goals, string $arc): void
    {
        $weeks = 10;
        $index = 0;

        /*
         * Which two days of the week this programme runs on.
         *
         * Staggered across the working week rather than the same pair for
         * everybody: a real academy has children in on every weekday, and
         * putting all of them on the same two days leaves the building empty
         * on the other three — which is exactly what the "today" panel showed.
         *
         * Offsets are counted from Sunday, named explicitly. `startOfWeek()`
         * with no argument follows the locale, and this application runs in
         * Arabic, where the week starts on Saturday — so the schedule silently
         * moved onto the weekend the day APP_LOCALE was set.
         */
        $pairs = [[0, 3], [1, 4], [2, 0], [3, 1], [4, 2]];
        [$dayA, $dayB] = $pairs[self::$programmeCount++ % count($pairs)];

        for ($week = $weeks; $week >= 0; $week--) {
            foreach ([$dayA, $dayB] as $dayOffset) {
                $at = Carbon::now()
                    ->subWeeks($week)
                    ->startOfWeek(Carbon::SUNDAY)
                    ->addDays($dayOffset)
                    ->setTime([9, 10, 11, 12][rand(0, 3)], [0, 30][rand(0, 1)]);

                if ($at->isFuture() && $week > 0) {
                    continue;
                }

                $index++;

                // Roughly one session in nine is missed, which is what a real
                // register looks like. A demo at 100% attendance never shows
                // the absence row a parent needs to see.
                $roll = rand(1, 100);
                $status = match (true) {
                    $at->isFuture() => 'scheduled',
                    $roll <= 6 => 'absent',
                    $roll <= 11 => 'excused',
                    $roll <= 13 => 'cancelled',
                    default => 'held',
                };

                $session = TherapySession::create([
                    'number' => $this->numbers->session(),
                    'student_id' => $enrollment->student_id,
                    'enrollment_id' => $enrollment->id,
                    'specialist_id' => $specialist->id,
                    'specialty' => $enrollment->specialty,
                    'scheduled_at' => $at,
                    'duration_minutes' => $enrollment->session_minutes,
                    'status' => $status,
                    'absence_reason' => match ($status) {
                        'excused' => 'الأم أبلغت — موعد عند الطبيب.',
                        'cancelled' => 'إغلاق الأكاديمية — ظروف طارئة.',
                        default => null,
                    },
                ]);

                if ($status !== 'held') {
                    continue;
                }

                $this->rate($session, $goals, $index, $arc);

                $this->desk->draft($session, $this->reportText($enrollment->specialty->value, $index));

                /*
                 * The two most recent sessions are left as drafts — that is
                 * what a specialist's screen looks like at four in the
                 * afternoon, and it is what the "unwritten reports" queue is
                 * for. Publishing everything would make that queue always
                 * empty and the feature invisible.
                 */
                if ($week > 0) {
                    $this->desk->publish($session, $specialist);

                    /*
                     * Stamp the send time back to the day of the session plus a
                     * believable lag. ReportDesk stamps `now()` — correct in
                     * the application, wrong in a seed, where it would make
                     * every report in two terms look like it went out this
                     * afternoon and give the turnaround chart a median of
                     * forty-five days that no family ever experienced.
                     */
                    $lag = match (true) {
                        rand(1, 100) <= 55 => 0,   // same evening
                        rand(1, 100) <= 75 => 1,
                        rand(1, 100) <= 92 => rand(2, 3),
                        default => rand(4, 9),     // the ones worth chasing
                    };

                    $session->forceFill([
                        'published_at' => $session->scheduled_at->copy()
                            ->addDays($lag)
                            ->setTime(rand(15, 21), rand(0, 59)),
                    ])->saveQuietly();

                    // Most families read most reports. Not all of them.
                    if (rand(1, 100) <= 78) {
                        foreach ($session->student->guardians as $guardian) {
                            if (rand(1, 100) <= 80) {
                                $this->desk->markRead($session, $guardian);
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * Score each goal, moving it along the arc this child was given.
     *
     * The noise is the point: a curve that climbs one clean step per session
     * looks like a spreadsheet, not a child. Real ratings wobble, and a parent
     * who has watched their son have a bad Tuesday should see that Tuesday.
     *
     * @param  array<int, Goal>  $goals
     */
    private function rate(TherapySession $session, array $goals, int $index, string $arc): void
    {
        $rows = [];

        foreach ($goals as $position => $goal) {
            // Not every goal is worked on every session.
            if (rand(1, 100) <= 22) {
                continue;
            }

            $pace = match ($arc) {
                'fast_climb' => 0.22,
                'steady_climb' => 0.15,
                'slow_climb' => 0.09,
                'plateau' => 0.04,
                'setback' => 0.13,
                default => 0.12,
            };

            $level = $goal->baseline + ($index * $pace) - ($position * 0.35);

            // The hospital stay: everything drops for a fortnight and then
            // starts back up.
            if ($arc === 'setback' && $index >= 11 && $index <= 15) {
                $level -= 1.4;
            }

            if ($arc === 'plateau') {
                $level = min($level, $goal->baseline + 1.6);
            }

            $level = (int) round(max(0, min(4, $level + (rand(-10, 10) / 20))));

            $trials = rand(0, 100) <= 60 ? rand(5, 10) : null;

            $rows[] = [
                'goal_id' => $goal->id,
                'level' => $level,
                'trials' => $trials,
                'successes' => $trials === null
                    ? null
                    : max(0, min($trials, (int) round($trials * ($level / 4) + rand(-1, 1)))),
                'note' => rand(1, 100) <= 25 ? $this->ratingNote($level) : null,
            ];
        }

        if ($rows !== []) {
            $this->desk->rate($session, $rows);
        }
    }

    private function ratingNote(int $level): string
    {
        return match (true) {
            $level >= 4 => 'عملها لحاله من أول محاولة اليوم.',
            $level === 3 => 'احتاج تذكير بسيط بالكلام بس.',
            $level === 2 => 'بلّش لحاله وبعدين احتاج مساعدة.',
            $level === 1 => 'اشتغلنا عليها يد بيد.',
            default => 'اليوم ما كان متعاون على هذا النشاط.',
        };
    }

    /**
     * The five boxes, written the way a specialist writes them.
     *
     * @return array<string, string>
     */
    private function reportText(string $specialty, int $index): array
    {
        $activities = [
            'speech' => [
                'اشتغلنا على بطاقات الصور (١٢ بطاقة)، وتمارين نفخ للهوا لتقوية عضلات الفم، ولعبة الأسماء مع المرآة.',
                'تمارين مخارج صوت /س/ قدام المرآة، وقراءة قصة قصيرة مع أسئلة، ولعبة «شو هاد؟» بالصور.',
                'تدريب على طلب الأشياء بجملة من كلمتين، وتمارين تقليد أصوات الحيوانات، ولعبة الغميضة اللفظية.',
            ],
            'occupational' => [
                'تمارين قبضة القلم بالمعجون، تخطيط على خطوط مستقيمة، ونشاط تكامل حسي على الكرة الكبيرة.',
                'تدريب قص بالمقص على خطوط، تزرير وفك أزرار على لوحة التدريب، ونشاط رمل حسي.',
                'تمارين توازن على المشّاية، تركيب مكعبات صغيرة، وتدريب على استعمال الملعقة لحاله.',
            ],
            'behavioral' => [
                'جدول مصوّر للجلسة، تدريب على الجلوس ٥ دقائق مع معزّز، وتمارين انتباه مشترك بالبالون.',
                'تدريب على انتظار الدور بلعبة السيارات، وتقليل الصراخ عبر تعليم طلب بديل بالإشارة.',
                'تدريب النظر بالعين عند المناداة، ونشاط تبادل أدوار، وتعزيز بالرمز عند كل استجابة صحيحة.',
            ],
            'special_ed' => [
                'قراءة ١٥ كلمة بصرية بالبطاقات، وكتابة الاسم على السبورة، وتمارين جمع ضمن العشرة بالمكعبات.',
                'تمييز الحروف المتشابهة (ب/ت/ث)، ونسخ جملة قصيرة، ومسائل حسابية بالوسائل الملموسة.',
                'قراءة نص قصير بصوت عالي، وإملاء ٥ كلمات، وترتيب أرقام تصاعدياً.',
            ],
        ];

        $progress = [
            'اليوم لاحظنا تحسّن واضح في الانتباه — قعد للنشاط كامل بدون ما يقوم.',
            'بلّش يبادر لحاله بدون ما نطلب منه، وهاي أول مرة نلاحظها بهالوضوح.',
            'زادت مدة تركيزه شوي عن الجلسة الماضية، وصار يستجيب أسرع للتعليمات.',
            'أنجز نشاطين من أصل ثلاثة باستقلالية، والثالث احتاج تلميح بسيط.',
            'صار يتقبّل الأنشطة الجديدة أسهل من قبل، ومقاومته للتغيير قلّت.',
        ];

        $difficulties = [
            'تعب بالنص وطلب استراحة — كمّلنا بعد ٣ دقائق.',
            'انزعج من صوت المكيّف وصار يغطّي أذنيه، حوّلنا لغرفة تانية.',
            'كان في مقاومة بالبداية للنشاط الجديد، احتاج وقت حتى تأقلم.',
            'التشتت كان أعلى من المعتاد اليوم — يمكن لأنه إجا متأخر ومستعجل.',
            'ما في صعوبات تذكر اليوم، الجلسة مشت مرتاحة من أولها لآخرها.',
        ];

        $home = [
            'كرّروا تمرين النفخ بالشلموه ٥ دقايق يومياً قبل النوم، وسجّلوا كم مرة نجح.',
            'خلّوه يطلب أكله بجملة من كلمتين قبل ما تعطوه — حتى لو أخدت وقت، استنّوا عليه.',
            'اقرأوا معه القصة المرفقة كل يوم، ووقّفوا عند الصور واسألوه «شو هاد؟».',
            'خلّوه يزرّر قميصه لحاله كل صباح، وساعدوه بس بآخر زر إذا تعب.',
            'طبّقوا نفس جدول الصور بالبيت وقت الواجبات، وعزّزوه فوراً لما يخلّص.',
            'درّبوه على انتظار دوره بلعبة بسيطة مع إخوته ١٠ دقايق يومياً.',
        ];

        $private = [
            'الأم متعاونة جداً وبتطبّق البرنامج المنزلي — التقدم واضح لأن في متابعة بالبيت.',
            'يبدو إن البرنامج المنزلي مش عم ينطبق. لازم نحكي مع الأم بلطف بالجلسة الجاية.',
            'الطفل بيجي متأخر كثير وهاد بياكل من وقت الجلسة. أنبّه الاستقبال.',
            'أفكر أعدّل معيار الهدف الثالث — طالع صعب عليه أكثر من المتوقع بهالمرحلة.',
            'ننتبه: لاحظت علامات إرهاق متكررة آخر أسبوعين. يستحق ملاحظة للأم عن النوم.',
        ];

        // All six, weighted the way a waiting room actually looks: mostly
        // settled, sometimes tired, occasionally a bad morning. The cycle used
        // to hold only four, so "بيبكي" and "رافض" were never once recorded
        // and the mood chart had two permanently empty bars.
        $moods = [
            'happy', 'calm', 'tired', 'calm', 'agitated', 'happy',
            'calm', 'crying', 'tired', 'happy', 'resistant', 'calm',
        ];

        return [
            'mood' => $moods[$index % count($moods)],
            'activities' => $activities[$specialty][$index % 3],
            'progress' => $progress[$index % count($progress)],
            'difficulties' => $difficulties[$index % count($difficulties)],
            'home_plan' => $home[$index % count($home)],
            'private_notes' => rand(1, 100) <= 35 ? $private[$index % count($private)] : null,
        ];
    }

    /**
     * التقارير الدورية — the quarter, not the day.
     *
     * Every child gets one closed quarter that the family already has, and
     * roughly half get a second one still being written. Both states have to
     * exist in a demo: the screen is about the difference between a report the
     * academy is drafting and one a mother has already taken to a school.
     *
     * The prose is written against the child's real figures — the attendance
     * and the goal movement are read back out of the tables the sessions just
     * produced, so the words and the numbers underneath them agree. A seeded
     * report whose paragraphs were invented independently of its own data is
     * exactly the contradiction this system exists to prevent.
     */
    private function progressReports(Student $student, string $arc): void
    {
        $enrollment = $student->enrollments()->with('specialist')->first();

        if (! $enrollment || ! $enrollment->specialist) {
            return;
        }

        $goals = $student->goals()->with('ratings')->ordered()->get();

        $moved = $goals->filter(function (Goal $goal) {
            $latest = $goal->ratings->last()?->level?->value;

            return $latest !== null && $latest > $goal->baseline;
        });

        $held = $student->sessions()->where('status', 'held')->count();
        $missed = $student->sessions()->whereIn('status', ['absent', 'excused'])->count();
        $rate = $held + $missed > 0 ? (int) round($held / ($held + $missed) * 100) : 0;

        $names = $moved->take(2)->pluck('title')->implode('، و');

        $summary = match ($arc) {
            'fast_climb' => "تقدّم واضح خلال الفترة. حضر {$held} جلسة بنسبة {$rate}٪، وتحرّك في {$moved->count()} من أهدافه — أبرزها {$names}. صار يبادر لحاله في مواقف ما كان يبادر فيها قبل، ومدة انتباهه زادت بشكل ملموس.",
            'steady_climb' => "تقدّم ثابت ومطّرد. حضر {$held} جلسة بنسبة {$rate}٪، وتحرّك في {$moved->count()} من أهدافه، منها {$names}. التقدّم بطيء لكنه في اتجاه واحد ولم ينتكس.",
            'slow_climb' => "تقدّم بطيء يحتاج صبراً. حضر {$held} جلسة بنسبة {$rate}٪. الحركة في الأهداف محدودة لكنها موجودة، وأوضحها {$names}. نوصي بتمديد الفترة الحالية قبل رفع سقف الأهداف.",
            'plateau' => "الفترة كانت ثابتة أكثر منها متقدّمة. حضر {$held} جلسة بنسبة {$rate}٪، والأهداف بقيت قريبة من مستواها في بداية الفترة. نقترح مراجعة معايير الإتقان — قد تكون موضوعة أعلى من المرحلة الحالية.",
            'setback' => "الفترة انقسمت نصفين. حضر {$held} جلسة بنسبة {$rate}٪، وكان هناك تراجع واضح في منتصفها تزامن مع انقطاعه الصحّي، ثم عاد يستعيد ما فقده. الوضع الحالي قريب من مستواه قبل الانقطاع.",
            default => "حضر {$held} جلسة بنسبة {$rate}٪ خلال الفترة، مع حركة في {$moved->count()} من أهدافه.",
        };

        $achieved = $moved->isEmpty()
            ? 'لم يُغلق أي هدف في هذه الفترة، والأهداف الحالية ما زالت قيد العمل.'
            : "تحرّكت الأهداف التالية عن خط بدايتها:\n— ".$moved->take(4)->pluck('title')->implode("\n— ");

        // The closed quarter the family already has.
        ProgressReport::create([
            'student_id' => $student->id,
            'enrollment_id' => $enrollment->id,
            'author_id' => $enrollment->specialist->id,
            'period_start' => now()->copy()->subWeeks(10)->toDateString(),
            'period_end' => now()->copy()->subWeeks(2)->toDateString(),
            'summary' => $summary,
            'achieved' => $achieved,
            'recommendations' => 'الاستمرار على نفس عدد الجلسات الأسبوعية، مع مراجعة الأهداف بعد ستّ جلسات. يُنصح بمتابعة البرنامج المنزلي بانتظام — الفرق بين الأطفال الذين يُطبَّق معهم في البيت والذين لا يُطبَّق واضح في المنحنيات.',
            'home_program' => "خمس عشرة دقيقة يومياً، في وقت ثابت وقبل أن يتعب:\n— التمرين المرفق في تقرير الجلسة الأخيرة.\n— تسجيل عدد المحاولات الناجحة في ورقة صغيرة وإحضارها معكم.\n— تعزيز فوري بعد كل محاولة، ولو لم تكتمل.",
            'status' => 'published',
            'published_at' => now()->copy()->subWeeks(2)->addDays(1)->setTime(18, rand(0, 59)),
        ]);

        // And, for some of them, the one still being written.
        if (rand(1, 100) <= 45) {
            ProgressReport::create([
                'student_id' => $student->id,
                'enrollment_id' => $enrollment->id,
                'author_id' => $enrollment->specialist->id,
                'period_start' => now()->copy()->subWeeks(2)->toDateString(),
                'period_end' => now()->toDateString(),
                'summary' => 'مسودة قيد الكتابة — بانتظار جلستَي هذا الأسبوع قبل إغلاق الفترة.',
                'achieved' => null,
                'recommendations' => null,
                'home_program' => null,
                'status' => 'draft',
                'published_at' => null,
            ]);
        }
    }

    /** A short thread on each child, so the messages screen is not empty. */
    private function conversation(Student $student, User $guardian, User $admin): void
    {
        $specialist = $student->enrollments()->first()?->specialist;

        if (! $specialist) {
            return;
        }

        $lastReport = $student->sessions()->published()->latest('scheduled_at')->first();

        $student->messages()->create([
            'sender_id' => $guardian->id,
            'therapy_session_id' => $lastReport?->id,
            'body' => 'مرحبا، قرأت التقرير. بالبيت بلاحظ إنه بحاول بس بستعجل ويترك. في شي معيّن بتنصحوني فيه؟',
            'created_at' => now()->subDays(3),
            'updated_at' => now()->subDays(3),
        ]);

        $student->messages()->create([
            'sender_id' => $specialist->id,
            'body' => 'أهلاً فيكي. طبيعي بهالمرحلة. جرّبي تقسّمي النشاط لخطوتين بس، وعزّزيه فوراً بعد كل خطوة — واذا ترك، رجّعيه بهدوء لنفس الخطوة بدون إعادة من الأول.',
            'read_at' => now()->subDays(2),
            'created_at' => now()->subDays(2),
            'updated_at' => now()->subDays(2),
        ]);

        // Left unread on purpose on some children, so the unanswered-questions
        // counter on the office screen has something real to point at.
        if (rand(1, 100) <= 45) {
            $student->messages()->create([
                'sender_id' => $guardian->id,
                'body' => 'تمام، رح جرّب. بس سؤال — هل ممكن نزيد جلسة بالأسبوع؟',
                'created_at' => now()->subDay(),
                'updated_at' => now()->subDay(),
            ]);
        }
    }
}
