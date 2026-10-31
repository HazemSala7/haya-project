<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/**
 * The academy's money: a monthly subscription per child, and what came in
 * against it.
 *
 * There was none of this. The system could describe a child's therapy in
 * detail and could not say whether his family had paid for it, so the fees
 * lived in a notebook beside the keyboard — and the one question the office is
 * asked every morning, «مين ما دفع؟», had no answer on any screen.
 *
 * ---------------------------------------------------------------------------
 * THE SUBSCRIPTION IS ON THE CHILD, THE CHARGE IS A ROW.
 *
 * `students.monthly_fee` is what the academy agreed with this family — set by
 * the administration, changed when the arrangement changes. It is a standing
 * fact and it is not money.
 *
 * `invoices` is the money: one row per child per month, dated the first of
 * that month because that is when the academy says it falls due. Keeping them
 * apart is what lets the fee change in March without rewriting January, and
 * what lets March be issued twice without charging twice — the unique index
 * below refuses the second one at the database, not in a controller somebody
 * can forget to call.
 *
 * ---------------------------------------------------------------------------
 * WHY A MONTH COLUMN AND NOT JUST A DATE.
 *
 * `period` is the first day of the month the invoice is for. A date alone
 * would make "has March been issued?" a range query and "issue March twice" a
 * race; as a column it is an equality check and a unique key. The due date is
 * stored beside it rather than derived, because an academy that lets a family
 * pay by the tenth should be able to say so without the system arguing.
 */
return new class extends Migration
{
    public function up(): void
    {
        Schema::table('students', function (Blueprint $table) {
            // What this family pays a month. Null until the administration
            // sets it — a child with no agreed fee is not a child who owes
            // zero, and the billing screen says so rather than inventing one.
            $table->decimal('monthly_fee', 10, 2)->nullable()->after('status');
        });

        Schema::create('invoices', function (Blueprint $table) {
            $table->id();
            $table->string('number', 24)->unique();
            $table->foreignId('student_id')->constrained()->cascadeOnDelete();

            // The first day of the month being charged for.
            $table->date('period')->index();
            $table->date('due_on');

            $table->decimal('amount', 10, 2);
            $table->decimal('discount', 10, 2)->default(0);
            $table->decimal('total', 10, 2)->default(0);
            // Derived from the payments by the model, stored so that listing
            // and filtering stays one query.
            $table->decimal('paid', 10, 2)->default(0);
            $table->string('status')->default('unpaid')->index();

            $table->string('note')->nullable();
            $table->foreignId('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();
            // Money is archived, never destroyed.
            $table->softDeletes();

            // One charge per child per month. The database refuses the second
            // one, so a double-click cannot bill a family twice.
            $table->unique(['student_id', 'period']);
            $table->index(['status', 'due_on']);
        });

        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->string('receipt_no', 24)->unique();
            $table->foreignId('invoice_id')->constrained()->cascadeOnDelete();

            $table->decimal('amount', 10, 2);
            $table->date('paid_on')->index();
            $table->string('method')->default('cash'); // cash|transfer|cheque
            $table->string('reference')->nullable();
            $table->string('note')->nullable();

            $table->foreignId('received_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index('invoice_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('payments');
        Schema::dropIfExists('invoices');

        Schema::table('students', function (Blueprint $table) {
            $table->dropColumn('monthly_fee');
        });
    }
};
