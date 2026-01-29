import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

class GoogleAuthService {
  GoogleAuthService({FlutterSecureStorage? storage, GoogleSignIn? googleSignIn})
    : _storage = storage ?? const FlutterSecureStorage(),
      _googleSignIn =
          googleSignIn ??
          GoogleSignIn(
            scopes: [
              'email',
              'https://www.googleapis.com/auth/spreadsheets',
              'https://www.googleapis.com/auth/drive',
            ],
          );

  final FlutterSecureStorage _storage;
  final GoogleSignIn _googleSignIn;

  String? _currentEmail;

  String? get currentUserEmail => _currentEmail;

  Future<String?> signInSilently() async {
    try {
      // ignore: avoid_print
      print('[GoogleAuth] signInSilently 호출');
      final account = await _googleSignIn.signInSilently();
      if (account != null) {
        _currentEmail = account.email;
        await _storage.write(key: 'googleUserEmail', value: account.email);
        // ignore: avoid_print
        print('[GoogleAuth] signInSilently 성공: ${account.email}');
        return account.email;
      }
      // ignore: avoid_print
      print('[GoogleAuth] signInSilently: 계정 없음');
    } catch (e) {
      // ignore: avoid_print
      print('[GoogleAuth] signInSilently 예외: $e');
    }
    return null;
  }

  Future<String?> signIn() async {
    try {
      // ignore: avoid_print
      print('[GoogleAuth] Starting sign in...');
      final account = await _googleSignIn.signIn().timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          // ignore: avoid_print
          print('[GoogleAuth] Sign in timeout');
          throw TimeoutException('로그인 시간 초과', const Duration(seconds: 60));
        },
      );
      // ignore: avoid_print
      print(
        '[GoogleAuth] Sign in completed, account: ${account?.email ?? 'null'}',
      );
      if (account != null) {
        _currentEmail = account.email;
        await _storage.write(key: 'googleUserEmail', value: account.email);
        // ignore: avoid_print
        print('[GoogleAuth] Email saved: ${account.email}');
        return account.email;
      }
      // ignore: avoid_print
      print('[GoogleAuth] Sign in returned null account');
    } catch (e, stackTrace) {
      // ignore: avoid_print
      print('[GoogleAuth] Sign in error: $e');
      // ignore: avoid_print
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
    // 이미 생성자에서 필요한 스코프들을 모두 요청했으므로,
    // 여기서는 "로그인 상태인지" 정도만 확인한다.
    // ignore: avoid_print
    print('[GoogleAuth] hasDriveAccess 호출 (추가 스코프 요청 없이 계정 유무만 확인)');
    final account = await _googleSignIn.signInSilently();
    final hasAccess = account != null;
    // ignore: avoid_print
    print(
      '[GoogleAuth] hasDriveAccess: account=${account?.email ?? 'null'} → $hasAccess',
    );
    return hasAccess;
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

    final authHeaders = await account.authHeaders;
    return {
      'Authorization': authHeaders['Authorization'] ?? '',
      'X-Goog-AuthUser': '0',
    };
  }

  Future<http.Client> getAuthenticatedClient({
    bool promptIfNecessary = false,
  }) async {
    // ignore: avoid_print
    print(
      '[GoogleAuth] getAuthenticatedClient(promptIfNecessary=$promptIfNecessary)',
    );
    var account = await _googleSignIn.signInSilently();
    if (account == null && promptIfNecessary) {
      // ignore: avoid_print
      print('[GoogleAuth] getAuthenticatedClient: silent 실패 → 대화형 로그인 시도');
      account = await _googleSignIn.signIn();
    }
    if (account == null) {
      // ignore: avoid_print
      print('[GoogleAuth] getAuthenticatedClient: 계정 없음 → Not authenticated');
      throw Exception('Not authenticated');
    }

    final headers = await account.authHeaders;
    // ignore: avoid_print
    print('[GoogleAuth] getAuthenticatedClient: 성공');
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
