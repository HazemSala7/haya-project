import 'package:dio/dio.dart';

/// A failed call, in a shape a screen can render.
///
/// The server's refusals are written for the person holding the phone — «اكتب
/// شو بدكم من الأهل بالبيت», «التقرير مُرسل — ما بينعدّل» — so the rule here is
/// to carry that sentence to the screen intact, and only invent one when the
/// server did not send any.
class ApiException implements Exception {
  ApiException(
    this.message, {
    this.statusCode,
    this.errors = const {},
    this.isConnection = false,
  });

  final String message;
  final int? statusCode;

  /// field name → the first message for that field.
  final Map<String, String> errors;

  /// The request never reached the server.
  final bool isConnection;

  bool get isUnauthenticated => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isValidation => statusCode == 422;

  /// The message for one field, for under its input.
  String? field(String name) => errors[name];

  factory ApiException.from(DioException error) {
    final response = error.response;

    if (response == null) {
      final offline = switch (error.type) {
        DioExceptionType.connectionError ||
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout =>
          true,
        _ => false,
      };

      return ApiException(
        offline ? 'ما في اتصال بالإنترنت.' : 'تعذّر الوصول للخادم. جرّب كمان مرة.',
        isConnection: true,
      );
    }

    final status = response.statusCode ?? 0;
    final body = response.data;

    final errors = <String, String>{};
    String? message;

    if (body is Map) {
      final raw = body['message'];
      if (raw is String && raw.isNotEmpty) message = raw;

      final fields = body['errors'];
      if (fields is Map) {
        fields.forEach((key, value) {
          final first = value is List && value.isNotEmpty ? value.first : value;
          if (first is String) errors['$key'] = first;
        });
      }
    }

    // Laravel's 422 message for several invalid fields reads "X (and 2 more
    // errors)" in English. The first field's own message is Arabic and says
    // the same thing better.
    if (status == 422 && errors.isNotEmpty) {
      message = errors.values.first;
    }

    message ??= switch (status) {
      401 => 'انتهت الجلسة. سجّل دخول من جديد.',
      403 => 'ما عندك صلاحية لهاد الإجراء.',
      404 => 'العنصر غير موجود.',
      413 => 'الملف أكبر من المسموح.',
      429 => 'محاولات كثيرة. استنّى شوي وجرّب.',
      >= 500 => 'خطأ في الخادم. جرّب بعد شوي.',
      _ => 'تعذّر إتمام العملية.',
    };

    return ApiException(message, statusCode: status, errors: errors);
  }

  @override
  String toString() => message;
}
