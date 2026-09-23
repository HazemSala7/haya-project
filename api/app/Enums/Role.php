<?php

namespace App\Enums;

/**
 * Three kinds of people sign in to an academy this size.
 *
 * The split that matters is not seniority, it is the child's file: a
 * specialist writes it, the office runs it, and the family reads their own
 * child's part of it and nothing else.
 *
 * `Guardian` rather than `Parent` — deliberately. `parent` is a reserved word
 * in PHP and an enum case is a class constant, so the obvious name is a fatal
 * error. It is also the more accurate word: a grandmother or a legal guardian
 * signs in the same way a father does.
 */
enum Role: string
{
    case Admin = 'admin';
    case Specialist = 'specialist';
    case Guardian = 'guardian';

    public function label(): string
    {
        return match ($this) {
            self::Admin => 'الإدارة',
            self::Specialist => 'أخصائية',
            self::Guardian => 'ولي أمر',
        };
    }

    /** Who works here — as opposed to who is a family reading their file. */
    public function isStaff(): bool
    {
        return $this !== self::Guardian;
    }

    /**
     * Who may read what a specialist wrote for herself.
     *
     * The admin can: she is clinically responsible for the case and reviews
     * files. The family cannot, and that is the whole point of the column.
     */
    public function seesPrivateNotes(): bool
    {
        return $this->isStaff();
    }
}
