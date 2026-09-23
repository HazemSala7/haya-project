<?php

namespace App\Enums;

/**
 * How much help the child needed to do the thing — the one number this whole
 * system exists to move.
 *
 * It is a five-point prompt hierarchy, the scale therapists already work on:
 * you start by doing it with him hand-over-hand and you finish by naming the
 * task and standing back. Scoring every goal on it every session is what turns
 * "تحسّن ملحوظ" — an opinion a parent has to take on trust — into "من مساعدة
 * كاملة إلى تلميح لفظي خلال ست جلسات", which is a claim the academy can be
 * held to.
 *
 * Backed by an int rather than a string on purpose: it is ordered, it gets
 * averaged, and it is plotted. A string would need a lookup table to sort.
 */
enum PromptLevel: int
{
    case Refused = 0;
    case FullHelp = 1;
    case PartialHelp = 2;
    case VerbalPrompt = 3;
    case Independent = 4;

    public function label(): string
    {
        return match ($this) {
            self::Refused => 'رفض / ما استجاب',
            self::FullHelp => 'مساعدة كاملة',
            self::PartialHelp => 'مساعدة جزئية',
            self::VerbalPrompt => 'تلميح لفظي',
            self::Independent => 'مستقل',
        };
    }

    /**
     * What the level means for the person holding the child's hand.
     *
     * Spelled out because the difference between "partial" and "full" is where
     * two specialists rating the same child will drift apart, and a drifting
     * scale makes every curve drawn from it a lie.
     */
    public function description(): string
    {
        return match ($this) {
            self::Refused => 'ما قبل يجرّب، أو ما استجاب إطلاقاً.',
            self::FullHelp => 'عملناها معه يداً بيد من أولها لآخرها.',
            self::PartialHelp => 'بدأ لحاله واحتاج مساعدة بالنص، أو لمسة توجيه.',
            self::VerbalPrompt => 'عملها لحاله بعد ما ذكّرناه بالكلام أو بالإشارة.',
            self::Independent => 'عملها لحاله بدون أي تذكير.',
        };
    }

    /**
     * The child no longer needs a hand on him.
     *
     * The threshold for "achieved" sits here rather than at Independent alone,
     * because a goal held at verbal prompt across the criteria window is a goal
     * that has moved out of therapy and into practice.
     */
    public function isIndependentish(): bool
    {
        return $this->value >= self::VerbalPrompt->value;
    }

    /** @return array<int, array<string, mixed>> The scale, for the rating form. */
    public static function scale(): array
    {
        return array_map(fn (self $level) => [
            'value' => $level->value,
            'label' => $level->label(),
            'description' => $level->description(),
        ], array_reverse(self::cases()));
    }
}
