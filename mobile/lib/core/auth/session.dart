import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_client.dart';
import '../api/api_exception.dart';
import '../models/profile.dart';

/// Where the API lives.
///
/// The same live server the web dashboard talks to — one academy, one source
/// of truth. A compile-time constant, so a build can be pointed at a local
/// Laravel with `--dart-define=API_BASE=http://10.0.2.2:8020/api` without a
/// file that then gets committed pointing at somebody's laptop.
const kApiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://neurex.ps/haya/api');

const _tokenKey = 'haya.token';
const _userKey = 'haya.user';

/// `restoring` exists so the first frame is a splash rather than the login
/// form: showing a login form for the milliseconds it takes to read the token
/// off disk — to somebody already signed in — reads as having been signed out.
enum SessionStatus { restoring, signedOut, signedIn }

@immutable
class Session {
  const Session({required this.status, this.user});

  const Session.restoring() : status = SessionStatus.restoring, user = null;
  const Session.signedOut() : status = SessionStatus.signedOut, user = null;

  final SessionStatus status;
  final Profile? user;
}

class SessionController extends StateNotifier<Session> {
  SessionController() : super(const Session.restoring()) {
    client = ApiClient(
      baseUrl: kApiBase,
      // The server has decided this token is dead. Whatever screen is open,
      // the only correct next screen is the login form.
      onUnauthenticated: () {
        if (state.status == SessionStatus.signedIn) signOut(serverRejected: true);
      },
    );

    _restore();
  }

  late final ApiClient client;

  /// Set when the session ended because the server refused the token. The
  /// login screen says so — "you were signed out" with no reason reads as a
  /// bug, and here the reason is usually that the office switched it off.
  bool wasRejected = false;

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final raw = prefs.getString(_userKey);

    if (token == null || raw == null) {
      state = const Session.signedOut();
      return;
    }

    /*
     * The cached profile is trusted for the first frame, then checked.
     *
     * Waiting for /auth/me before showing anything would put a spinner in
     * front of a specialist every time she opens the app between two children.
     * So the app opens on what it knew last; a role change or a switched-off
     * account is caught by the refresh a second later.
     */
    try {
      final user = Profile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      client.token = token;
      state = Session(status: SessionStatus.signedIn, user: user);
    } catch (_) {
      await _clear();
      state = const Session.signedOut();
      return;
    }

    unawaited(refreshUser());
  }

  /// Re-read the account — a child newly linked to this family, a new title.
  Future<void> refreshUser() async {
    try {
      final data = await client.get('/auth/me');
      if (data is! Map) return;

      final user = Profile.fromJson(Map<String, dynamic>.from(data));
      state = Session(status: SessionStatus.signedIn, user: user);

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_userKey, jsonEncode(user.toJson()));
    } on ApiException {
      // Offline or a hiccup: the cached profile stands. A 401 has already
      // been handled by the interceptor.
    }
  }

  Future<void> signIn(String email, String password) async {
    final body = await client.postEnvelope(
      '/auth/login',
      body: {'email': email.trim(), 'password': password},
    );

    final token = body['token'] as String?;
    final data = body['data'];

    if (token == null || data is! Map) {
      throw ApiException('استجابة غير متوقّعة من الخادم.');
    }

    final user = Profile.fromJson(Map<String, dynamic>.from(data));

    client.token = token;
    wasRejected = false;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userKey, jsonEncode(user.toJson()));

    state = Session(status: SessionStatus.signedIn, user: user);
  }

  Future<void> signOut({bool serverRejected = false}) async {
    wasRejected = serverRejected;

    // Best effort. A token that outlives the app on a lost phone is worse than
    // a slow sign-out — but a sign-out that hangs with no signal is worse
    // than either.
    if (!serverRejected) {
      try {
        await client.post('/auth/logout').timeout(const Duration(seconds: 6));
      } catch (_) {
        // Nothing to do about it.
      }
    }

    await _clear();
    client.token = null;
    state = const Session.signedOut();
  }

  Future<void> _clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}

final sessionProvider = StateNotifierProvider<SessionController, Session>(
  (ref) => SessionController(),
);

/// The one API client, carrying whatever token the session holds.
final apiProvider = Provider<ApiClient>((ref) => ref.watch(sessionProvider.notifier).client);

/// The signed-in account, or null.
final meProvider = Provider<Profile?>((ref) => ref.watch(sessionProvider).user);
