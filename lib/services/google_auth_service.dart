import 'package:google_sign_in/google_sign_in.dart';

class GoogleAuthService {
  GoogleAuthService()
      : _googleSignIn = GoogleSignIn(
          scopes: <String>[
            'https://www.googleapis.com/auth/spreadsheets',
            'https://www.googleapis.com/auth/drive',
          ],
        );

  final GoogleSignIn _googleSignIn;

  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;

  Future<GoogleSignInAccount?> signInSilently() async {
    try {
      return await _googleSignIn.signInSilently();
    } catch (_) {
      return null;
    }
  }

  Future<GoogleSignInAccount?> signIn() async {
    try {
      return await _googleSignIn.signIn();
    } catch (_) {
      return null;
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
  }

  Future<Map<String, String>> authHeaders() async {
    var account = _googleSignIn.currentUser;
    account ??= await _googleSignIn.signInSilently();
    if (account == null) {
      return {};
    }
    return await account.authHeaders;
  }
}
