import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/google_auth_service.dart';
import '../services/google_sheets_service.dart';
import '../services/health_service.dart';

class AppState extends ChangeNotifier {
  AppState()
      : _authService = GoogleAuthService(),
        _sheetsService = GoogleSheetsService(),
        _healthService = HealthService();

  final GoogleAuthService _authService;
  final GoogleSheetsService _sheetsService;
  final HealthService _healthService;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  SharedPreferences? _prefs;
  bool _isInitializing = true;
  bool _isSignedIn = false;
  bool _writeWeightToHealth = false;
  bool _writeBloodPressureToHealth = false;
  String? _shareEmail;

  bool get isInitializing => _isInitializing;
  bool get isSignedIn => _isSignedIn;
  bool get writeWeightToHealth => _writeWeightToHealth;
  bool get writeBloodPressureToHealth => _writeBloodPressureToHealth;
  String? get shareEmail => _shareEmail;
  GoogleSheetsService get sheetsService => _sheetsService;
  HealthService get healthService => _healthService;

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _writeWeightToHealth = _prefs?.getBool('writeWeightToHealth') ?? false;
    _writeBloodPressureToHealth =
        _prefs?.getBool('writeBloodPressureToHealth') ?? false;
    _shareEmail = _prefs?.getString('shareEmail');

    final signedInUser = await _authService.signInSilently();
    _isSignedIn = signedInUser != null;
    if (_isSignedIn) {
      await _sheetsService.bindAuth(_authService);
      await _sheetsService.ensureCurrentMonthSheet();
      if (_shareEmail != null && _shareEmail!.isNotEmpty) {
        await _sheetsService.shareAppFolder(_shareEmail!);
      }
    }

    _isInitializing = false;
    notifyListeners();
  }

  Future<void> signIn() async {
    final user = await _authService.signIn();
    _isSignedIn = user != null;
    if (_isSignedIn) {
      await _secureStorage.write(
        key: 'googleUserEmail',
        value: user?.email ?? '',
      );
      await _sheetsService.bindAuth(_authService);
      await _sheetsService.ensureCurrentMonthSheet();
      if (_shareEmail != null && _shareEmail!.isNotEmpty) {
        await _sheetsService.shareAppFolder(_shareEmail!);
      }
    }
    notifyListeners();
  }

  Future<void> signOut() async {
    await _authService.signOut();
    await _secureStorage.delete(key: 'googleUserEmail');
    _isSignedIn = false;
    notifyListeners();
  }

  Future<void> setWriteWeightToHealth(bool value) async {
    _writeWeightToHealth = value;
    await _prefs?.setBool('writeWeightToHealth', value);
    notifyListeners();
  }

  Future<void> setWriteBloodPressureToHealth(bool value) async {
    _writeBloodPressureToHealth = value;
    await _prefs?.setBool('writeBloodPressureToHealth', value);
    notifyListeners();
  }

  Future<void> setShareEmail(String email) async {
    _shareEmail = email;
    await _prefs?.setString('shareEmail', email);
    notifyListeners();
  }
}
