<?php

namespace App\Exceptions;

use RuntimeException;

/**
 * The system refusing something it understands: publishing a report with
 * nothing in it, rewriting one a mother already read, scoring a goal that
 * belongs to another child.
 *
 * A dedicated class rather than a bare RuntimeException, because rendering on
 * RuntimeException catches far more than intended — Symfony's
 * NotFoundHttpException extends it, so every 404 would come back as a 422
 * carrying an internal message.
 *
 * The message is written for the specialist and shown to her.
 */
class OperationRefused extends RuntimeException
{
    //
}
