import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:haya/admin/student_billing_sheet.dart';
import 'package:haya/admin/students_list_screen.dart';
import 'package:haya/core/api/api_client.dart';
import 'package:haya/core/auth/session.dart';
import 'package:haya/core/models/records.dart';
import 'package:haya/core/widgets/forms.dart';
import 'package:haya/core/widgets/ui.dart';
import 'package:haya/guardian/statement_screen.dart';
import 'package:haya/shared/session_actions.dart';

/// The ⋮ on a row, and what it is allowed to offer.
///
/// These drive the real widgets — the sheet, the confirm dialog, the
/// attendance form — against a client whose only fake part is the wire. What
/// they are really guarding is the agreement with the server: the app must
/// not offer a button the server will refuse, and when it does act it must
/// call the path the server actually exposes.
void main() {
  late _FakeApi api;

  setUp(() => api = _FakeApi());

  /// A phone, not the 800x600 the binding defaults to: a sheet of four
  /// actions does not fit in a surface that shape.
  void asAPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  /// Puts [child] on screen inside the app's own locale, direction and
  /// providers, with a fake server behind it.
  Future<void> host(WidgetTester tester, Widget child) async {
    asAPhone(tester);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiProvider.overrideWithValue(api)],
        child: MaterialApp(
          locale: const Locale('ar'),
          supportedLocales: const [Locale('ar')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// A button that opens the actions built from a live context and ref.
  Widget opener(List<SheetAction> Function(BuildContext, WidgetRef) build, {String title = 'سجل'}) {
    return Consumer(
      builder: (context, ref, _) => TextButton(
        onPressed: () => showActions(context, title: title, actions: build(context, ref)),
        child: const Text('افتح'),
      ),
    );
  }

  /// A text box by its label. The label is a line drawn above the box rather
  /// than a decoration inside it, so it is reached through the field widget.
  Finder field(String label) => find.descendant(
        of: find.byWidgetPredicate((widget) => widget is AppTextField && widget.label == label),
        matching: find.byType(TextField),
      );

  Future<void> press(WidgetTester tester, Finder what) async {
    await tester.ensureVisible(what);
    await tester.pumpAndSettle();
    await tester.tap(what);
    await tester.pumpAndSettle();
  }

  /* ------------------------------------------------------------- the sheet */

  group('the actions sheet', () {
    testWidgets('shows every action and runs the one that is pressed', (tester) async {
      var ran = '';

      await host(
        tester,
        opener((context, ref) => [
              SheetAction(label: 'عدّل', icon: Icons.edit_outlined, onTap: () => ran = 'edit'),
              SheetAction(label: 'احذف', icon: Icons.delete_outline_rounded, tone: 'bad', onTap: () => ran = 'delete'),
            ]),
      );

      await press(tester, find.text('افتح'));
      expect(find.text('عدّل'), findsOneWidget);
      expect(find.text('احذف'), findsOneWidget);

      await press(tester, find.text('احذف'));
      expect(ran, 'delete');
      // The sheet closes behind the action rather than sitting over its result.
      expect(find.text('عدّل'), findsNothing);
    });

    testWidgets('a refused action is shown with its reason and does nothing', (tester) async {
      var ran = false;

      await host(
        tester,
        opener((context, ref) => [
              SheetAction(
                label: 'احذف',
                icon: Icons.delete_outline_rounded,
                tone: 'bad',
                disabledReason: 'عليها دفعات مسجّلة — احذف الدفعات أول.',
                onTap: () => ran = true,
              ),
            ]),
      );

      await press(tester, find.text('افتح'));
      expect(find.text('عليها دفعات مسجّلة — احذف الدفعات أول.'), findsOneWidget);

      await tester.tap(find.text('احذف'));
      await tester.pumpAndSettle();
      expect(ran, isFalse, reason: 'a disabled action fired anyway');
    });
  });

  /* ---------------------------------------------------------- the sessions */

  group('a session row', () {
    TherapySession session({String status = 'scheduled', String report = 'none'}) =>
        TherapySession.fromJson({
          'id': 7,
          'number': 'S-7',
          'student_id': 3,
          'enrollment_id': 4,
          'specialty': 'speech',
          'scheduled_at': '2026-11-04T08:30:00.000000Z',
          'duration_minutes': 45,
          'status': status,
          'report_status': report,
          'student': {'id': 3, 'name': 'يوسف كمال دعنا'},
        });

    testWidgets('offers the report, the diary and the delete', (tester) async {
      await host(
        tester,
        opener((context, ref) => sessionActions(context, ref, session(), onChanged: () {})),
      );

      await press(tester, find.text('افتح'));
      expect(find.text('اكتب التقرير'), findsOneWidget);
      expect(find.text('علّم الحضور'), findsOneWidget);
      expect(find.text('احذف الجلسة'), findsOneWidget);
    });

    testWidgets('a published report freezes both the diary and the delete', (tester) async {
      await host(
        tester,
        opener((context, ref) => sessionActions(
              context,
              ref,
              session(status: 'held', report: 'published'),
              onChanged: () {},
            )),
      );

      await press(tester, find.text('افتح'));

      // The server's own two refusals, said before the tap rather than after.
      expect(find.text('التقرير انبعت — الحضور ما بينغيّر بعده.'), findsOneWidget);
      expect(
        find.text('التقرير انبعت للأهل — بينضاف عليه تصحيح ولا بينحذف.'),
        findsOneWidget,
      );
      expect(find.text('اقرأ التقرير'), findsOneWidget);
    });

    testWidgets('the delete asks first, then calls the route the server has', (tester) async {
      var changed = 0;

      await host(
        tester,
        opener((context, ref) => sessionActions(context, ref, session(), onChanged: () => changed++)),
      );

      await press(tester, find.text('افتح'));
      await press(tester, find.text('احذف الجلسة'));

      // The dialog, not the delete: nothing is gone after one tap.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(api.sent, isEmpty);

      await press(tester, find.widgetWithText(FilledButton, 'احذف'));
      expect(api.sent.single, ('DELETE', '/sessions/7'));
      expect(changed, 1, reason: 'the list was not told to reload');
    });

    testWidgets('the diary records what happened, and why', (tester) async {
      await host(
        tester,
        opener((context, ref) => sessionActions(context, ref, session(), onChanged: () {})),
      );

      await press(tester, find.text('افتح'));
      await press(tester, find.text('علّم الحضور'));

      // «ما إجا» is the state the app could never record before this sheet.
      await press(tester, find.text('ما إجا'));
      await tester.enterText(field('السبب'), 'مريض');
      await press(tester, find.widgetWithText(FilledButton, 'احفظ'));

      expect(api.sent.single, ('POST', '/sessions/7/attendance'));
      expect(api.lastBody, {'status': 'absent', 'absence_reason': 'مريض'});
    });
  });

  /* ---------------------------------------------------------- the invoices */

  group('an invoice row', () {
    Invoice invoice({double paid = 0, List<Map<String, dynamic>> payments = const []}) =>
        Invoice.fromJson({
          'id': 11,
          'number': 'INV-11',
          'student_id': 3,
          'student': {'id': 3, 'name': 'يوسف كمال دعنا'},
          'period': '2026-11-01',
          'period_label': 'تشرين الثاني ٢٠٢٦',
          'amount': 300,
          'discount': 0,
          'total': 300,
          'paid': paid,
          'due': 300 - paid,
          'status': paid > 0 ? 'partial' : 'sent',
          'status_label': paid > 0 ? 'مدفوعة جزئياً' : 'مرسلة',
          'due_on': '2026-11-10',
          'payments': payments,
        });

    testWidgets('an invoice with money on it cannot be deleted, and says why', (tester) async {
      await host(
        tester,
        opener((context, ref) => invoiceActions(
              context,
              ref,
              invoice(paid: 100, payments: const [
                {'id': 2, 'amount': 100, 'paid_on': '2026-11-02', 'method': 'cash'},
              ]),
              onChanged: () {},
            )),
      );

      await press(tester, find.text('افتح'));
      expect(find.text('عليها دفعات مسجّلة — احذف الدفعات أول.'), findsOneWidget);

      await tester.tap(find.text('احذف الفاتورة'));
      await tester.pumpAndSettle();
      expect(api.sent, isEmpty);
    });

    testWidgets('an untouched invoice is deleted through the billing route', (tester) async {
      await host(
        tester,
        opener((context, ref) => invoiceActions(context, ref, invoice(), onChanged: () {})),
      );

      await press(tester, find.text('افتح'));
      await press(tester, find.text('احذف الفاتورة'));
      await press(tester, find.widgetWithText(FilledButton, 'احذف'));

      expect(api.sent.single, ('DELETE', '/billing/invoices/11'));
    });

    testWidgets('editing sends the four fields the server validates', (tester) async {
      await host(
        tester,
        opener((context, ref) => invoiceActions(context, ref, invoice(), onChanged: () {})),
      );

      await press(tester, find.text('افتح'));
      await press(tester, find.text('عدّل الفاتورة'));

      await tester.enterText(field('القيمة'), '250');
      await tester.enterText(field('الخصم'), '50');
      await press(tester, find.widgetWithText(FilledButton, 'احفظ'));

      expect(api.sent.single, ('PUT', '/billing/invoices/11'));
      expect(api.lastBody?['amount'], 250);
      expect(api.lastBody?['discount'], 50);
      expect(api.lastBody?['due_on'], '2026-11-10');
    });
  });

  /* ------------------------------------------------------------- the row */

  testWidgets('a student row shows the fee without being opened', (tester) async {
    await host(
      tester,
      StudentRow(
        student: Student.fromJson(const {
          'id': 3,
          'name': 'يوسف كمال دعنا',
          'file_number': '26-001',
          'age_label': '6 سنوات',
          'status': 'active',
          'monthly_fee': '300.00',
          'enrollments_count': 1,
        }),
        onTap: () {},
      ),
    );

    expect(find.textContaining('300 ₪ بالشهر'), findsOneWidget);
    expect(find.text('بلا رسوم'), findsNothing);
  });

  testWidgets('a child nobody priced is flagged on the row', (tester) async {
    await host(
      tester,
      StudentRow(
        student: Student.fromJson(const {
          'id': 4,
          'name': 'تالا سامي',
          'file_number': '26-007',
          'status': 'active',
          'enrollments_count': 1,
        }),
        onTap: () {},
      ),
    );

    // The month's invoices would skip her, and nothing else on the screen
    // would say so.
    expect(find.text('بلا رسوم'), findsOneWidget);
  });

  /* ------------------------------------------------- the parent's copy */

  group('the statement a parent opens', () {
    // `GET /billing/students/{id}` — the server lets a guardian read her own
    // child's account and refuses a specialist.
    const account = {
      'student': {'id': 3, 'name': 'آدم رائد عمرو', 'file_number': '26-003', 'monthly_fee': '300.00'},
      'balance': {'billed': '600.00', 'paid': '300.00', 'due': '300.00', 'months': 2, 'overdue': 1},
      'invoices': [
        {
          'id': 11,
          'number': 'INV-11',
          'student_id': 3,
          'period': '2026-11-01',
          'period_label': 'تشرين الثاني',
          'amount': '300.00',
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
          'period_label': 'تشرين الأول',
          'amount': '300.00',
          'total': '300.00',
          'paid': '300.00',
          'due': '0.00',
          'status': 'paid',
          'status_label': 'مدفوعة',
          'payments': [
            {'id': 4, 'receipt_no': 'R-4', 'amount': '300.00', 'paid_on': '2026-10-05', 'method': 'cash'},
          ],
        },
      ],
    };

    testWidgets('shows what is owed, the months, and the receipts', (tester) async {
      api.reads = {'/billing/students/3': account};

      await host(tester, const StatementScreen(studentId: 3, studentName: 'آدم رائد عمرو'));
      await tester.pumpAndSettle();

      expect(find.text('المتبقّي عليكم'), findsOneWidget);
      expect(find.text('فاتورة متأخّرة'), findsNothing); // «1 فاتورة متأخّرة»
      expect(find.textContaining('فاتورة متأخّرة'), findsOneWidget);
      expect(find.text('تشرين الثاني'), findsOneWidget);
      expect(find.text('تشرين الأول'), findsOneWidget);

      // The receipt line is the point of a statement: a family matching what
      // it handed over against what the academy recorded.
      expect(find.textContaining('وصل R-4'), findsOneWidget);
    });

    testWidgets('gives a parent nothing to press on the money', (tester) async {
      api.reads = {'/billing/students/3': account};

      await host(tester, const StatementScreen(studentId: 3, studentName: 'آدم رائد عمرو'));
      await tester.pumpAndSettle();

      for (final forbidden in ['اقبض', 'عدّل الفاتورة', 'احذف الفاتورة', 'الرسوم الشهرية']) {
        expect(find.text(forbidden), findsNothing, reason: '«$forbidden» on a parent screen');
      }
      expect(find.byType(RowMenu), findsNothing);

      // And it read, it did not write.
      expect(api.sent.where((call) => call.$1 != 'GET'), isEmpty);
    });
  });

  testWidgets('a student row carries the ⋮ that opens all of it', (tester) async {
    var opened = 0;

    await host(
      tester,
      StudentRow(
        student: Student.fromJson(const {
          'id': 3,
          'name': 'يوسف كمال دعنا',
          'file_number': '26-001',
          'status': 'active',
        }),
        onTap: () {},
        onMore: () => opened++,
      ),
    );

    await press(tester, find.byIcon(Icons.more_vert_rounded));
    expect(opened, 1);
  });
}

/// The server, as far as these widgets can tell.
///
/// It extends the real client rather than faking the interface, so the calls
/// under test go through the app's own methods; only the wire is replaced.
class _FakeApi extends ApiClient {
  _FakeApi() : super(baseUrl: 'http://localhost/test');

  /// Verb and path, in order — the agreement with the server.
  final List<(String, String)> sent = [];
  Map<String, dynamic>? lastBody;

  /// What a GET answers, by path. The shapes are the server's own.
  Map<String, dynamic> reads = {};

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    sent.add(('GET', path));
    return reads[path] ?? <String, dynamic>{};
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    sent.add(('POST', path));
    lastBody = body is Map ? Map<String, dynamic>.from(body) : null;
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    sent.add(('PUT', path));
    lastBody = body is Map ? Map<String, dynamic>.from(body) : null;
    return <String, dynamic>{};
  }

  @override
  Future<dynamic> delete(String path, {Object? body}) async {
    sent.add(('DELETE', path));
    return <String, dynamic>{};
  }
}
