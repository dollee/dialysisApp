import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleAuthService {
  GoogleAuthService({
    FlutterSecureStorage? storage,
    GoogleSignIn? googleSignIn,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _googleSignIn = googleSignIn ??
            GoogleSignIn(
              scopes: [
                'email',
              ],
            );

  final FlutterSecureStorage _storage;
  final GoogleSignIn _googleSignIn;

  String? _currentEmail;

  String? get currentUserEmail => _currentEmail;

  Future<String?> signInSilently() async {
    try {
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        _currentEmail = account.email;
        await _storage.write(
          key: 'googleUserEmail',
          value: account.email,
        );
        return account.email;
      }
    } catch (_) {
      // Silent sign-in 실패는 정상
    }
    return null;
  }

  Future<String?> signIn() async {
    try {
      print('[GoogleAuth] Starting sign in...');
      final account = await _googleSignIn.signIn().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          print('[GoogleAuth] Sign in timeout');
          throw TimeoutException('로그인 시간 초과', const Duration(seconds: 60));
        },
      );
      print('[GoogleAuth] Sign in completed, account: ${account?.email ?? 'null'}');
      if (account != null) {
        _currentEmail = account.email;
        await _storage.write(
          key: 'googleUserEmail',
          value: account.email,
        );
        print('[GoogleAuth] Email saved: ${account.email}');
        return account.email;
      }
      print('[GoogleAuth] Sign in returned null account');
    } catch (e, stackTrace) {
      print('[GoogleAuth] Sign in error: $e');
      print('[GoogleAuth] Stack trace: $stackTrace');
    }
    return null;
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    _currentEmail = null;
    await _storage.delete(key: 'googleUserEmail');
  }

  Future<bool> hasDriveAccess() async {
    final account = await _googleSignIn.signInSilently();
    if (account == null) {
      return false;
    }
    final granted = await _googleSignIn.requestScopes([
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive',
    ]);
    return granted == true;
  }

  Future<Map<String, String>> authHeaders({
    bool promptIfNecessary = false,
    List<String>? scopes,
  }) async {
    var account = await _googleSignIn.signInSilently();
    if (account == null && promptIfNecessary) {
      account = await _googleSignIn.signIn();
    }
    if (account == null) {
      return {};
    }

    final requiredScopes = scopes ?? [
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive',
    ];
    final granted = await _googleSignIn.requestScopes(requiredScopes);
    if (granted != true) {
      return {};
    }

    final authHeaders = await account.authHeaders;
    return {
      'Authorization': authHeaders['Authorization'] ?? '',
      'X-Goog-AuthUser': '0',
    };
  }

  Future<http.Client> getAuthenticatedClient({
    bool promptIfNecessary = false,
  }) async {
    var account = await _googleSignIn.signInSilently();
    if (account == null && promptIfNecessary) {
      account = await _googleSignIn.signIn();
    }
    if (account == null) {
      throw Exception('Not authenticated');
    }
    final requiredScopes = [
      'https://www.googleapis.com/auth/spreadsheets',
      'https://www.googleapis.com/auth/drive',
    ];
    final granted = await _googleSignIn.requestScopes(requiredScopes);
    if (granted != true) {
      throw Exception('Required scopes not granted');
    }
    final headers = await account.authHeaders;
    return _AuthenticatedHttpClient(headers);
  }
}

class _AuthenticatedHttpClient extends http.BaseClient {
  _AuthenticatedHttpClient(this._headers) : _inner = http.Client();

  final Map<String, String> _headers;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _inner.send(request);
  }

  @override
  void close() {
    _inner.close();
  }
}
