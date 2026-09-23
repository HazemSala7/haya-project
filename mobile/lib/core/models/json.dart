/// Reading Laravel's JSON without trusting its types.
///
/// A pivot's `is_primary` arrives as `1` from MySQL and `true` from SQLite; an
/// average arrives as `2` or `2.5`; a count computed in SQL can arrive as a
/// string. Every model below reads through these instead of casting, so one
/// driver's habits cannot crash a screen built against the other's.
abstract final class J {
  static int? intOrNull(Object? value) => switch (value) {
        null => null,
        int v => v,
        num v => v.toInt(),
        String v => int.tryParse(v) ?? double.tryParse(v)?.toInt(),
        bool v => v ? 1 : 0,
        _ => null,
      };

  static int int0(Object? value) => intOrNull(value) ?? 0;

  static double? doubleOrNull(Object? value) => switch (value) {
        null => null,
        num v => v.toDouble(),
        String v => double.tryParse(v),
        _ => null,
      };

  static String? str(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text.isEmpty ? null : text;
  }

  static String s(Object? value) => value?.toString() ?? '';

  static bool boolean(Object? value) => switch (value) {
        bool v => v,
        num v => v != 0,
        String v => v == '1' || v == 'true',
        _ => false,
      };

  static Map<String, dynamic>? map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : null;

  static List<T> list<T>(Object? value, T Function(Map<String, dynamic>) parse) {
    if (value is! List) return const [];
    return [
      for (final item in value)
        if (item is Map) parse(Map<String, dynamic>.from(item)),
    ];
  }
}
