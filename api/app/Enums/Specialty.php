<?php

namespace App\Enums;

/**
 * The four programmes the academy runs.
 *
 * An enum and not a table: these are a clinical taxonomy, not a list the
 * office edits on a Tuesday. Making them rows would buy an admin screen
 * nobody asked for and cost a join on every session, every goal and every
 * report — and would let someone create a fifth programme that no specialist
 * is qualified for and no assessment form exists for.
 */
enum Specialty: string
{
    case Speech = 'speech';
    case Occupational = 'occupational';
    case Behavioral = 'behavioral';
    case SpecialEd = 'special_ed';

    public function label(): string
    {
        return match ($this) {
            self::Speech => 'النطق واللغة',
            self::Occupational => 'العلاج الوظيفي',
            self::Behavioral => 'تعديل السلوك',
            self::SpecialEd => 'التربية الخاصة',
        };
    }

    /** The long form, for a report header and the enrolment screen. */
    public function fullLabel(): string
    {
        return match ($this) {
            self::Speech => 'النطق واللغة والتخاطب',
            self::Occupational => 'العلاج الوظيفي والتكامل الحسي',
            self::Behavioral => 'تعديل السلوك والتوحد',
            self::SpecialEd => 'التربية الخاصة وصعوبات التعلّم',
        };
    }

    /** @return array<int, string> */
    public static function values(): array
    {
        return array_column(self::cases(), 'value');
    }
}
