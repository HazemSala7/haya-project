import 'package:flutter_test/flutter_test.dart';
import 'package:haya/core/models/records.dart';

/// Parsing what the server actually sends.
///
/// The payloads below are copied from live responses, not invented: a model
/// test written against a shape somebody imagined passes while the screen
/// shows «—». That is exactly what happened to the programme card — a tag was
/// handed a label where the widget expects a code — and a test on a made-up
/// map would not have caught it either.
void main() {

  group('StudentAccount', () {
    /*
     * The real answer of `GET /billing/students/{id}`.
     *
     * Three keys under `data`, not a list and a `meta` — which is what the
     * office's account screen assumed, so it drew an empty account for every
     * child from the day it was written. The decimals arrive as strings from
     * MySQL, as they do everywhere else.
     */
    const payload = {
      'student': {'id': 3, 'name': 'آدم رائد عمرو', 'file_number': '26-003', 'monthly_fee': '300.00'},
      'balance': {'billed': '900.00', 'paid': '600.00', 'due': '300.00', 'months': 3, 'overdue': 1},
      'invoices': [
        {
          'id': 11,
          'number': 'INV-11',
          'student_id': 3,
          'period': '2026-11-01',
          'period_label': 'تشرين الثاني ٢٠٢٦',
          'amount': '300.00',
          'discount': '0.00',
          'total': '300.00',
          'paid': '0.00',
          'due': '300.00',
          'status': 'overdue',
          'status_label': 'متأخّرة',
          'due_on': '2026-11-10',
          'payments': [],
        },
        {
          'id': 10,
          'number': 'INV-10',
          'student_id': 3,
          'period': '2026-10-01',
          'period_label': 'تشرين الأول ٢٠٢٦',
          'amount': '300.00',
          'discount': '0.00',
          'total': '300.00',
          'paid': '300.00',
          'due': '0.00',
          'status': 'paid',
          'status_label': 'مدفوعة',
          'due_on': '2026-10-10',
          'payments': [
            {'id': 4, 'receipt_no': 'R-4', 'amount': '300.00', 'paid_on': '2026-10-05', 'method': 'cash'},
          ],
        },
      ],
    };

    test('the balance and the invoices come through', () {
      final account = StudentAccount.fromJson(payload);

      expect(account.studentName, 'آدم رائد عمرو');
      expect(account.monthlyFee, 300);
      expect(account.due, 300);
      expect(account.paid, 600);
      expect(account.billed, 900);
      expect(account.months, 3);
      expect(account.overdue, 1);
      expect(account.invoices, hasLength(2));
      expect(account.settled, isFalse);
    });

    test('each invoice carries the child it belongs to', () {
      // The server does not repeat the child on every invoice; the row still
      // has to be able to say whose it is.
      final account = StudentAccount.fromJson(payload);
      expect(account.invoices.first.studentName, 'آدم رائد عمرو');
      expect(account.invoices.last.payments.single.amount, 300);
    });

    test('an account nobody has invoiced reads as settled, not broken', () {
      final account = StudentAccount.fromJson(const {
        'student': {'id': 9, 'name': 'طفل جديد', 'monthly_fee': null},
        'balance': {'billed': 0, 'paid': 0, 'due': 0, 'months': 0, 'overdue': 0},
        'invoices': [],
      });

      expect(account.invoices, isEmpty);
      expect(account.monthlyFee, isNull);
      expect(account.settled, isTrue);
    });
  });

  group('Student', () {
    /*
     * The monthly fee, in the two shapes the column arrives in.
     *
     * `monthly_fee` is `decimal:2`: MySQL hands it over as the string
     * "300.00" and SQLite as the number 300. The list row prints it, so a
     * cast that only handles one of them shows «—» on live and nothing on a
     * laptop — the hardest kind of difference to notice.
     */
    test('the fee is read whether it arrives as a string or a number', () {
      expect(
        Student.fromJson(const {'id': 3, 'monthly_fee': '300.00'}).monthlyFee,
        300,
      );
      expect(
        Student.fromJson(const {'id': 3, 'monthly_fee': 300}).monthlyFee,
        300,
      );
    });

    test('a child with no fee is null, not zero', () {
      // Zero and «not set» mean the same thing to the server (`fee` writes
      // null for both), and the row says «بلا رسوم» for null — so null must
      // not quietly become 0 on the way in.
      expect(Student.fromJson(const {'id': 3}).monthlyFee, isNull);
      expect(Student.fromJson(const {'id': 3, 'monthly_fee': null}).monthlyFee, isNull);
    });
  });

  group('Enrollment', () {
    // From GET /students/3 — the nested, active-only enrollments.
    const nested = {
      'id': 4,
      'student_id': 3,
      'specialty': 'occupational',
      'specialist_id': 3,
      'sessions_per_week': 2,
      'session_minutes': 45,
      'status': 'active',
      'specialty_label': 'العلاج الوظيفي والتكامل الحسي',
      'specialist': {'id': 3, 'name': 'آية الجعبري', 'title': 'أخصائية علاج وظيفي'},
    };

    test('reads the raw specialty code, which is what SpecialtyTag wants', () {
      final enrollment = Enrollment.fromJson(nested);

      // The widget looks the label up itself and picks the dot colour from
      // the code. Give it the Arabic name and it finds nothing and draws
      // «—» — which is what the card did.
      expect(enrollment.specialty, 'occupational');
    });

    test('reads the label the server appends, for plain text', () {
      expect(Enrollment.fromJson(nested).specialtyLabel, contains('العلاج الوظيفي'));
    });

    test('reads the specialist it is assigned to', () {
      final enrollment = Enrollment.fromJson(nested);

      expect(enrollment.specialistId, 3);
      expect(enrollment.specialist?.name, 'آية الجعبري');
    });

    test('an unassigned programme parses, it does not throw', () {
      final enrollment = Enrollment.fromJson({
        'id': 9,
        'student_id': 3,
        'specialty': 'speech',
        'status': 'active',
      });

      expect(enrollment.specialistId, isNull);
      expect(enrollment.specialist, isNull);
      // The office needs to see these: a programme with nobody on it is a
      // child nobody is scheduled to see.
      expect(enrollment.specialty, 'speech');
    });
  });

  group('Student', () {
    // From GET /students — the list, which counts programmes but does not
    // load them. The office list reads the count, not the relation.
    const listed = {
      'id': 3,
      'file_number': '26-003',
      'name': 'آدم رائد عمرو',
      'age_label': '5 سنوات و4 شهور',
      'status': 'active',
      'birth_date': '2021-06-20',
      'gender': 'male',
      'enrollments_count': 2,
    };

    test('reads the file number as the office says it out loud', () {
      expect(Student.fromJson(listed).fileNumber, '26-003');
    });

    test('counts programmes even when the relation was not loaded', () {
      final student = Student.fromJson(listed);

      expect(student.enrollmentsCount, 2);
      expect(student.enrollments, isEmpty);
    });

    test('a child with no programme is detectable from the list alone', () {
      final student = Student.fromJson({...listed, 'enrollments_count': 0});
      expect(student.enrollmentsCount, 0);
    });

    test('an archived file is recognised by its deletion stamp', () {
      final student = Student.fromJson({...listed, 'deleted_at': '2026-06-01T00:00:00Z'});
      expect(student.archived, isTrue);
    });

    test('a live file is not archived', () {
      expect(Student.fromJson(listed).archived, isFalse);
    });
  });

  group('Invoice', () {
    // From GET /billing/invoices.
    const row = {
      'id': 11,
      'number': 'INV-2026-0007',
      'student_id': 3,
      'period': '2026-11-01',
      'period_label': 'تشرين الثاني 2026',
      'amount': '400.00',
      'discount': '0.00',
      'total': '400.00',
      'paid': '150.00',
      'due': 250,
      'status': 'partial',
      'status_label': 'مدفوعة جزئياً',
      'student': {'id': 3, 'name': 'آدم رائد عمرو', 'file_number': '26-003'},
    };

    test('decimal columns arrive as strings and still read as numbers', () {
      final invoice = Invoice.fromJson(row);

      expect(invoice.total, 400);
      expect(invoice.paid, 150);
    });

    test('what is owed is the server figure, not total minus paid', () {
      // Two screens doing their own arithmetic eventually disagree by a
      // piastre, and the one a parent is looking at is the wrong one.
      expect(Invoice.fromJson(row).due, 250);
      expect(Invoice.fromJson(row).settled, isFalse);
    });

    test('a settled invoice reads as settled', () {
      expect(Invoice.fromJson({...row, 'due': 0}).settled, isTrue);
    });

    test('the child it belongs to comes through the nested relation', () {
      final invoice = Invoice.fromJson(row);

      expect(invoice.studentName, 'آدم رائد عمرو');
      expect(invoice.fileNumber, '26-003');
    });
  });
}
