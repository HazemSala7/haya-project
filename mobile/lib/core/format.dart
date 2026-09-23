import 'package:intl/intl.dart';

/// Dates and numbers, formatted once.
///
/// ---------------------------------------------------------------------------
/// THE SERVER'S CLOCK IS UTC (`api/config/app.php` → `'timezone' => 'UTC'`).
///
/// That produces two shapes of timestamp, and both are UTC:
///
///   "2026-08-20T12:30:00.000000Z"  — every Eloquent date cast
///   "2026-08-24 12:30:00"          — `toDateTimeString()` and raw columns
///                                    (`next_session`, `read_by`, `last_at`)
///
/// The second has no zone on it, and `DateTime.parse` would read it as the
/// phone's local time — three hours off in summer. [Fmt.at] reads both as UTC
/// and hands back local time, which is also exactly what the web dashboard
/// shows (`new Date(...)` in the browser), so the two clients agree on when a
/// session was.
///
/// Date-only columns (`birth_date`, `started_at`) arrive as UTC midnight and
/// are converted the same way before the date is taken. Slicing the first ten
/// characters would also work today — but not if the server's timezone is
/// ever set to Asia/Hebron, when they arrive as 21:00Z the day before.
/// ---------------------------------------------------------------------------
abstract final class Fmt {
  static final _dayMonth = DateFormat('d MMMM', 'ar');
  static final _dayMonthYear = DateFormat('d MMMM yyyy', 'ar');
  static final _weekday = DateFormat('EEEE', 'ar');
  static final _number = NumberFormat.decimalPattern('en');

  static final _naive = RegExp(r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}(:\d{2})?$');
  static final _dateOnly = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Any timestamp the API sends, as local time.
  static DateTime? at(String? value) {
    if (value == null || value.isEmpty) return null;

    if (_dateOnly.hasMatch(value)) {
      return DateTime.tryParse(value);
    }

    if (_naive.hasMatch(value)) {
      return DateTime.tryParse('${value.replaceFirst(' ', 'T')}Z')?.toLocal();
    }

    return DateTime.tryParse(value)?.toLocal();
  }

  /// Latin digits throughout. intl writes the ar locale in Arabic-Indic ones,
  /// and "٢٣ أغسطس" above "89%" reads as two half-finished decisions. The web
  /// dashboard writes Latin digits too.
  static String _latin(String value) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    final buffer = StringBuffer();
    for (final char in value.split('')) {
      final index = arabicIndic.indexOf(char);
      buffer.write(index == -1 ? char : '$index');
    }
    return buffer.toString();
  }

  /// "23 أغسطس 2026"
  static String date(String? value) {
    final d = at(value);
    return d == null ? '—' : _latin(_dayMonthYear.format(d));
  }

  /// "23 أغسطس"
  static String shortDate(String? value) {
    final d = at(value);
    return d == null ? '—' : _latin(_dayMonth.format(d));
  }

  /// "الأحد 23 أغسطس" — for a diary, where the weekday is what is scanned for.
  static String dayDate(String? value) {
    final d = at(value);
    return d == null ? '—' : _latin('${_weekday.format(d)} ${_dayMonth.format(d)}');
  }

  /// "10:30"
  static String time(String? value) {
    final d = at(value);
    if (d == null) return '—';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  /// "23 أغسطس، 10:30"
  static String dateTime(String? value) {
    final d = at(value);
    return d == null ? '—' : '${shortDate(value)}، ${time(value)}';
  }

  /// "اليوم" / "أمس" / "بكرة" / the weekday and date.
  static String relativeDay(String? value) {
    final d = at(value);
    if (d == null) return '—';

    final now = DateTime.now();
    final days = DateTime(d.year, d.month, d.day).difference(DateTime(now.year, now.month, now.day)).inDays;

    return switch (days) {
      0 => 'اليوم',
      -1 => 'أمس',
      1 => 'بكرة',
      _ => dayDate(value),
    };
  }

  /// "قبل 3 أيام" / "بعد ساعتين".
  ///
  /// Arabic counts in three forms — one, two, many — and "قبل 2 يوم" is the
  /// kind of thing that makes software read as foreign.
  static String relative(String? value) {
    final d = at(value);
    if (d == null) return '—';

    final diff = d.difference(DateTime.now());
    final past = diff.isNegative;
    final minutes = diff.inMinutes.abs();

    String phrase(int n, String one, String two, String few, String many) {
      if (n == 1) return one;
      if (n == 2) return two;
      if (n <= 10) return '$n $few';
      return '$n $many';
    }

    final String unit;
    if (minutes < 1) {
      return 'الآن';
    } else if (minutes < 60) {
      unit = phrase(minutes, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة');
    } else if (minutes < 1440) {
      unit = phrase((minutes / 60).round(), 'ساعة', 'ساعتين', 'ساعات', 'ساعة');
    } else if (minutes < 43200) {
      unit = phrase((minutes / 1440).round(), 'يوم', 'يومين', 'أيام', 'يوماً');
    } else {
      unit = phrase((minutes / 43200).round(), 'شهر', 'شهرين', 'شهور', 'شهراً');
    }

    return past ? 'قبل $unit' : 'بعد $unit';
  }

  static String number(num? value) => value == null ? '—' : _number.format(value);

  /*
   * A counted noun, in Arabic's four shapes rather than English's two.
   *
   * «٢٩ أيام» is what a two-branch plural produces and it is wrong; Arabic
   * counts 1 alone, 2 as a dual, 3–10 with the broken plural, and 11 upward
   * with the singular again — «٢٩ يوماً». Zero takes the last shape too.
   *
   * The number is dropped for one and two because the word already carries
   * it: «يوم» is one day and «يومان» is two, and printing the digit beside
   * them reads as a stutter.
   *
   *   counted(1,  'يوم', 'يومان', 'أيام', 'يوماً')  →  يوم
   *   counted(2,  …)                                 →  يومان
   *   counted(5,  …)                                 →  5 أيام
   *   counted(29, …)                                 →  29 يوماً
   */
  static String counted(int n, String one, String two, String few, String many) =>
      switch (n) {
        1 => one,
        2 => two,
        >= 3 && <= 10 => '${number(n)} $few',
        _ => '${number(n)} $many',
      };

  /// The four shapes of the words this app counts most.
  static String days(int n) => counted(n, 'يوم', 'يومان', 'أيام', 'يوماً');
  static String sessions(int n) => counted(n, 'جلسة', 'جلستان', 'جلسات', 'جلسة');
  static String reports(int n) => counted(n, 'تقرير', 'تقريران', 'تقارير', 'تقريراً');
  static String messages(int n) => counted(n, 'رسالة', 'رسالتان', 'رسائل', 'رسالة');
  static String children(int n) => counted(n, 'طفل', 'طفلان', 'أطفال', 'طفلاً');

  static String percent(num? value) => value == null ? '—' : '${value.round()}%';

  /// "2026-08-23", for a date field the API validates with `date`.
  static String isoDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// A date column from the API as the value of a date input.
  static String? toDateInput(String? value) {
    final d = at(value);
    return d == null ? null : isoDate(d);
  }

  /// A local moment, written the way the server stores it: UTC, no zone.
  ///
  /// Carbon does not convert an offset on the way into a datetime column — it
  /// keeps the wall-clock digits and drops the zone — so sending "10:30+03:00"
  /// would be stored as 10:30 UTC and shown back as 13:30. Converting here is
  /// what makes a session booked for 10:30 come back as 10:30, on the phone
  /// and on the dashboard alike.
  static String toServerDateTime(DateTime local) {
    final u = local.toUtc();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${isoDate(u)} ${two(u.hour)}:${two(u.minute)}:00';
  }

  static String fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// The wording, in one place — the same words the web dashboard uses
/// (`web/lib/format.ts`). Everything below is read by a worried parent on a
/// phone, and "ما إجا ع الجلسة" is a letter where "الحالة: غياب" is a case file.
abstract final class Labels {
  static const levels = {
    4: 'مستقل',
    3: 'تلميح لفظي',
    2: 'مساعدة جزئية',
    1: 'مساعدة كاملة',
    0: 'رفض / ما استجاب',
  };

  /// What each step means — so two specialists score the same child the same.
  static const levelHints = {
    4: 'عملها لحاله بدون أي تذكير.',
    3: 'عملها لحاله بعد ما ذكّرناه بالكلام أو بالإشارة.',
    2: 'بدأ لحاله واحتاج مساعدة بالنص، أو لمسة توجيه.',
    1: 'عملناها معه يداً بيد من أولها لآخرها.',
    0: 'ما قبل يجرّب، أو ما استجاب إطلاقاً.',
  };

  static String level(int? value) => value == null ? '—' : levels[value] ?? '—';

  static const sessionStatus = {
    'scheduled': 'مجدولة',
    'held': 'تمّت',
    'absent': 'ما إجا',
    'excused': 'غياب بعذر',
    'cancelled': 'ملغية',
  };

  static const sessionTone = {
    'scheduled': 'muted',
    'held': 'good',
    'absent': 'bad',
    'excused': 'warn',
    'cancelled': 'muted',
  };

  static const reportStatus = {'draft': 'مسوّدة', 'published': 'وصل الأهل'};
  static const reportTone = {'draft': 'warn', 'published': 'good'};

  static const moods = ['happy', 'calm', 'tired', 'agitated', 'crying', 'resistant'];

  static const mood = {
    'calm': 'هادئ',
    'happy': 'مبسوط',
    'tired': 'تعبان',
    'agitated': 'متوتّر',
    'crying': 'بيبكي',
    'resistant': 'رافض',
  };

  static const moodFace = {
    'calm': '😌',
    'happy': '😄',
    'tired': '😪',
    'agitated': '😣',
    'crying': '😢',
    'resistant': '😤',
  };

  static const specialties = ['speech', 'occupational', 'behavioral', 'special_ed'];

  static const specialty = {
    'speech': 'النطق واللغة',
    'occupational': 'العلاج الوظيفي',
    'behavioral': 'تعديل السلوك',
    'special_ed': 'التربية الخاصة',
  };

  static const specialtyFull = {
    'speech': 'النطق واللغة والتخاطب',
    'occupational': 'العلاج الوظيفي والتكامل الحسي',
    'behavioral': 'تعديل السلوك والتوحد',
    'special_ed': 'التربية الخاصة وصعوبات التعلّم',
  };

  static const goalStatus = {
    'active': 'شغّال',
    'achieved': 'تحقّق',
    'paused': 'موقوف',
    'dropped': 'أُلغي',
  };

  static const goalTone = {
    'active': 'brand',
    'achieved': 'good',
    'paused': 'warn',
    'dropped': 'muted',
  };

  static const studentStatus = {
    'active': 'مستمرّ',
    'paused': 'متوقّف مؤقتاً',
    'graduated': 'تخرّج',
    'withdrawn': 'انسحب',
  };

  static const studentTone = {
    'active': 'good',
    'paused': 'warn',
    'graduated': 'brand',
    'withdrawn': 'muted',
  };

  static const enrollmentStatus = {'active': 'شغّال', 'paused': 'موقوف مؤقتاً', 'ended': 'انتهى'};

  static const relation = {
    'father': 'الأب',
    'mother': 'الأم',
    'grandparent': 'جد/جدة',
    'sibling': 'أخ/أخت',
    'guardian': 'وصي',
  };

  static const trend = {'improving': 'متحسّن', 'steady': 'ثابت', 'declining': 'متراجع'};
  static const trendTone = {'improving': 'good', 'steady': 'muted', 'declining': 'bad'};

  static const role = {'admin': 'الإدارة', 'specialist': 'أخصائية', 'guardian': 'ولي أمر'};

  static const gender = {'male': 'ذكر', 'female': 'أنثى'};
}
