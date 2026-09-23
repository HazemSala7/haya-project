import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'api_exception.dart';

/// Every call the app makes to the academy's API.
///
/// Three things live here and nowhere else: the bearer token, the translation
/// of a failure into a sentence, and what happens when the server says the
/// session is over. A screen that had to remember the header would forget it
/// on one call eventually, and that call would fail in front of a parent.
class ApiClient {
  ApiClient({required this.baseUrl, this.onUnauthenticated})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          // A phone on Palestinian mobile data, not a datacentre.
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 40),
          sendTimeout: const Duration(minutes: 3),
          headers: {'Accept': 'application/json'},
          // Non-2xx is handled below rather than thrown by dio, so the
          // interceptor sees the body and can read Laravel's message.
          validateStatus: (status) => status != null && status < 500,
        )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = this.token;
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onResponse: (response, handler) {
          final status = response.statusCode ?? 0;

          if (status >= 200 && status < 300) {
            handler.next(response);
            return;
          }

          /*
           * A 401 means the token is gone — the office switched the account
           * off, or reset the password, which revokes every session. The app
           * has to end the session itself; a dead token left in place gives
           * every later screen an error instead of a login form.
           *
           * A wrong password is a 422 here, never a 401, so the login call
           * cannot trip this.
           */
          if (status == 401) onUnauthenticated?.call();

          handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
            ),
            true,
          );
        },
      ),
    );

    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(requestBody: false, responseBody: false));
    }
  }

  final String baseUrl;
  final Dio _dio;
  final void Function()? onUnauthenticated;

  /// The bearer token. Public for the one consumer that cannot go through
  /// dio: the video player, which fetches its own bytes and takes headers.
  String? token;

  Future<T> _send<T>(Future<Response<dynamic>> Function() call, T Function(dynamic) parse) async {
    try {
      final response = await call();
      return parse(response.data);
    } on DioException catch (error) {
      throw ApiException.from(error);
    }
  }

  /// A GET whose body is `{ "data": ... }`.
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) => _send(
        () => _dio.get<dynamic>(path, queryParameters: _clean(query)),
        (body) => body is Map ? body['data'] : body,
      );

  /// The whole envelope — for lists, which carry `meta` beside `data`, and for
  /// the child's file, whose summary rides in `meta`.
  Future<Map<String, dynamic>> getEnvelope(String path, {Map<String, dynamic>? query}) => _send(
        () => _dio.get<dynamic>(path, queryParameters: _clean(query)),
        (body) => Map<String, dynamic>.from(body as Map),
      );

  Future<dynamic> post(String path, {Object? body}) => _send(
        () => _dio.post<dynamic>(path, data: body ?? const <String, dynamic>{}),
        (data) => data is Map ? data['data'] ?? data : data,
      );

  Future<Map<String, dynamic>> postEnvelope(String path, {Object? body}) => _send(
        () => _dio.post<dynamic>(path, data: body ?? const <String, dynamic>{}),
        (data) => Map<String, dynamic>.from(data as Map),
      );

  Future<dynamic> put(String path, {Object? body}) => _send(
        () => _dio.put<dynamic>(path, data: body ?? const <String, dynamic>{}),
        (data) => data is Map ? data['data'] ?? data : data,
      );

  Future<dynamic> delete(String path) => _send(
        () => _dio.delete<dynamic>(path),
        (data) => data,
      );

  /// A photo or a clip, as multipart.
  ///
  /// The content type is left for dio to write: setting it by hand drops the
  /// boundary and the server sees an empty body.
  Future<dynamic> upload(
    String path, {
    required String filePath,
    required String fileName,
    String? caption,
    void Function(double progress)? onProgress,
  }) =>
      _send(
        () async => _dio.post<dynamic>(
          path,
          data: FormData.fromMap({
            'file': await MultipartFile.fromFile(filePath, filename: fileName),
            if (caption != null && caption.isNotEmpty) 'caption': caption,
          }),
          onSendProgress: onProgress == null
              ? null
              : (sent, total) {
                  if (total > 0) onProgress(sent / total);
                },
        ),
        (data) => data is Map ? data['data'] ?? data : data,
      );

  /// Raw bytes — a session photo, fetched with the Authorization header.
  ///
  /// Never by putting the token in the image URL: query strings end up in
  /// access logs, and this token opens every child's file in the building.
  Future<Uint8List> bytes(String path) => _send(
        () => _dio.get<List<int>>(
          path,
          options: Options(responseType: ResponseType.bytes, headers: {'Accept': '*/*'}),
        ),
        (data) => Uint8List.fromList(data as List<int>),
      );

  /// Drop empty filters rather than sending `?q=&status=`.
  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;

    final out = <String, dynamic>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.isEmpty) return;
      if (value is bool) {
        if (value) out[key] = 1;
        return;
      }
      out[key] = value;
    });

    return out.isEmpty ? null : out;
  }
}
