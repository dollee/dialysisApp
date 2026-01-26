import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/google_auth_service.dart';
import '../services/google_sheets_service.dart';
import '../services/health_service.dart';
import '../widgets/contact_picker.dart';

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
  final List<DebugLogEntry> _debugLogs = [];

  bool get isInitializing => _isInitializing;
  bool get isSignedIn => _isSignedIn;
  bool get writeWeightToHealth => _writeWeightToHealth;
  bool get writeBloodPressureToHealth => _writeBloodPressureToHealth;
  String? get shareEmail => _shareEmail;
  GoogleSheetsService get sheetsService => _sheetsService;
  HealthService get healthService => _healthService;
  List<DebugLogEntry> get debugLogs => List.unmodifiable(_debugLogs);

  Future<void> initialize() async {
    _prefs = await SharedPreferences.getInstance();
    _writeWeightToHealth = _prefs?.getBool('writeWeightToHealth') ?? false;
    _writeBloodPressureToHealth =
        _prefs?.getBool('writeBloodPressureToHealth') ?? false;
    _shareEmail = _prefs?.getString('shareEmail');

    final signedInEmail = await _authService.signInSilently();
    _isSignedIn = signedInEmail != null;
    if (_isSignedIn) {
      await _sheetsService.bindAuth(_authService);
      if (signedInEmail != null && signedInEmail.isNotEmpty) {
        addLog('구글 계정: $signedInEmail');
      }
      if (await _authService.hasDriveAccess()) {
        await _sheetsService.ensureCurrentMonthSheet();
        try {
          final sheetId = await _sheetsService.ensureInventorySheet();
          final driveEmail = await _sheetsService.getDriveUserEmail();
          if (driveEmail.isNotEmpty) {
            addLog('드라이브 API 계정: $driveEmail');
          }
          if (sheetId.isNotEmpty) {
            addLog('재고 시트 확인: $sheetId');
          }
          final info = await _sheetsService.getInventoryStorageInfo();
          addLog(
            '재고 저장 위치: '
            'file=${info.fileName.isEmpty ? 'unknown' : info.fileName} '
            'sheetId=${info.sheetId.isEmpty ? 'none' : info.sheetId} '
            'folderId=${info.folderId.isEmpty ? 'none' : info.folderId} '
            'parents=${info.parentIds.isEmpty ? 'none' : info.parentIds} '
            'link=${info.webViewLink.isEmpty ? 'none' : info.webViewLink} '
            'trashed=${info.trashed} '
            'error=${info.errorMessage.isEmpty ? 'none' : info.errorMessage}',
          );
        } catch (error) {
          addLog('재고 시트 생성 실패: $error');
        }
      } else {
        addLog('드라이브 권한 없음: 동기화 대기');
      }
      if (_shareEmail != null && _shareEmail!.isNotEmpty) {
        if (await _authService.hasDriveAccess()) {
          await _sheetsService.shareAppFolder(_shareEmail!);
        } else {
          addLog('공유 요청 보류: 드라이브 권한 필요');
        }
      }
    }

    _isInitializing = false;
    notifyListeners();
  }

  Future<void> signIn() async {
    try {
      addLog('로그인 시작...');
      final signedInEmail = await _authService.signIn();
      if (signedInEmail == null) {
        addLog('구글 로그인 실패 또는 취소됨');
      } else {
        addLog('로그인 성공: $signedInEmail');
      }
      _isSignedIn = signedInEmail != null;
      if (_isSignedIn) {
        await _secureStorage.write(
          key: 'googleUserEmail',
          value: signedInEmail ?? '',
        );
        await _sheetsService.bindAuth(_authService);
        if (signedInEmail != null && signedInEmail.isNotEmpty) {
          addLog('구글 계정: $signedInEmail');
        }
        if (await _authService.hasDriveAccess()) {
          await _sheetsService.ensureCurrentMonthSheet();
          try {
            final sheetId = await _sheetsService.ensureInventorySheet();
            final driveEmail = await _sheetsService.getDriveUserEmail();
            if (driveEmail.isNotEmpty) {
              addLog('드라이브 API 계정: $driveEmail');
            }
            final info = await _sheetsService.getInventoryStorageInfo();
            addLog(
              '재고 저장 위치: '
              'file=${info.fileName.isEmpty ? 'unknown' : info.fileName} '
              'sheetId=${info.sheetId.isEmpty ? 'none' : info.sheetId} '
              'folderId=${info.folderId.isEmpty ? 'none' : info.folderId} '
              'parents=${info.parentIds.isEmpty ? 'none' : info.parentIds} '
              'link=${info.webViewLink.isEmpty ? 'none' : info.webViewLink} '
              'trashed=${info.trashed} '
              'error=${info.errorMessage.isEmpty ? 'none' : info.errorMessage}',
            );
          } catch (error) {
            addLog('재고 시트 생성 실패: $error');
          }
        } else {
          addLog('드라이브 권한 없음: 동기화 대기');
        }
        if (_shareEmail != null && _shareEmail!.isNotEmpty) {
          if (await _authService.hasDriveAccess()) {
            await _sheetsService.shareAppFolder(_shareEmail!);
          } else {
            addLog('공유 요청 보류: 드라이브 권한 필요');
          }
        }
      }
    } catch (error) {
      addLog('로그인 중 에러: $error');
      rethrow;
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

  void addLog(String message) {
    _debugLogs.insert(0, DebugLogEntry(DateTime.now(), message));
    notifyListeners();
  }

  void clearLogs() {
    _debugLogs.clear();
    notifyListeners();
  }

  Future<bool> hasRequiredProfile() async {
    _prefs ??= await SharedPreferences.getInstance();
    final patient = _prefs?.getString('patientName') ?? '';
    final hospital = _prefs?.getString('hospitalName') ?? '';
    return patient.trim().isNotEmpty && hospital.trim().isNotEmpty;
  }

  Future<void> maybeRequestDelivery(BuildContext context) async {
    _prefs ??= await SharedPreferences.getInstance();
    final gateOn = _prefs?.getBool('deliveryRequestGate') ?? true;
    if (gateOn) {
      addLog('배송요청 판단: 게이트 ON → 스킵');
      return;
    }

    final owned = await _sheetsService.fetchLatestInventory('owned');
    final pending = await _sheetsService.fetchLatestInventory('pending');

    final thresholds = <int?>[
      _prefs?.getInt('manual_1_5_2l'),
      _prefs?.getInt('manual_2_3_2l'),
      _prefs?.getInt('manual_4_3_2l'),
      _prefs?.getInt('machine_1_5_3l'),
      _prefs?.getInt('machine_2_3_3l'),
      _prefs?.getInt('machine_4_3_3l'),
      _prefs?.getInt('manual_set'),
      null,
    ];

    var needsRequest = false;
    for (var i = 0; i < owned.values.length; i++) {
      final threshold = thresholds[i];
      if (threshold == null) {
        continue;
      }
      final pendingValue = pending.values[i];
      if (pendingValue <= 0) {
        continue;
      }
      final ownedValue = owned.values[i];
      if (ownedValue < threshold * 10) {
        needsRequest = true;
        break;
      }
    }

    addLog('배송요청 판단 값: owned=${owned.values.join(",")} '
        'pending=${pending.values.join(",")} '
        'thresholds=${thresholds.map((v) => v ?? 0).join(",")} '
        'needsRequest=$needsRequest');

    if (!needsRequest) {
      return;
    }

    final shouldSend = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('미배송분 배송 요청'),
        content: const Text('보유수량이 10일분보다 적습니다. 배송 메세지를 보낼까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('확인'),
          ),
        ],
      ),
    );

    if (shouldSend != true) {
      addLog('배송요청 취소됨');
      return;
    }

    var phone = _prefs?.getString('deliveryPhone') ?? '';
    if (phone.isEmpty) {
      phone = await _promptPhoneNumber(context);
      if (phone.isEmpty) {
        addLog('배송요청 전화번호 미입력');
        return;
      }
      await _prefs?.setString('deliveryPhone', phone);
    }

    final deliveryDate = await _selectDeliveryDate(context);
    if (deliveryDate == null) {
      return;
    }

    final patient = _prefs?.getString('patientName') ?? '';
    final hospital = _prefs?.getString('hospitalName') ?? '';
    final dateText = DateFormat('yyyy-MM-dd').format(deliveryDate);
    final message =
        '환자명 : $patient\n병원명 : $hospital\n미배송분 배송 요청합니다.\n배송일 : $dateText';
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': message},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      await _prefs?.setBool('deliveryRequestGate', true);
      addLog('배송요청 문자 발송');
    }
  }

  Future<void> applyMachineConsumption() async {
    _prefs ??= await SharedPreferences.getInstance();
    final deltas = List<int>.filled(8, 0);
    deltas[3] = _prefs?.getInt('machine_1_5_3l') ?? 0;
    deltas[4] = _prefs?.getInt('machine_2_3_3l') ?? 0;
    deltas[5] = _prefs?.getInt('machine_4_3_3l') ?? 0;
    deltas[6] = _prefs?.getInt('machine_set') ?? 0;
    addLog('기계투석 소모량 차감 요청: ${deltas.join(",")}');
    await _updateOwnedInventory(deltas);
  }

  Future<void> applyManualConsumption(String bagValue) async {
    final deltas = List<int>.filled(8, 0);
    switch (bagValue) {
      case '1.5':
        deltas[0] = 1;
        break;
      case '2.3':
        deltas[1] = 1;
        break;
      case '4.3':
        deltas[2] = 1;
        break;
      case '배액백':
        deltas[7] = 1;
        break;
      default:
        break;
    }
    addLog('손투석 소모량 차감 요청: $bagValue -> ${deltas.join(",")}');
    await _updateOwnedInventory(deltas);
  }

  Future<void> _updateOwnedInventory(List<int> deltas) async {
    _prefs ??= await SharedPreferences.getInstance();
    final autoRequest = _prefs?.getBool('autoDeliveryRequest') ?? false;
    final owned = await _sheetsService.fetchLatestInventory('owned');
    final updated = List<int>.generate(
      owned.values.length,
      (index) {
        final next = owned.values[index] - (deltas[index]);
        return next < 0 ? 0 : next;
      },
    );
    addLog('보유수량 변경: ${owned.values.join(",")} -> ${updated.join(",")}');
    await _sheetsService.appendInventory(
      'owned',
      updated,
      autoRequest: autoRequest,
    );
  }

  Future<DateTime?> _selectDeliveryDate(BuildContext context) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    return showDatePicker(
      context: context,
      initialDate: start.add(const Duration(days: 1)),
      firstDate: start,
      lastDate: start.add(const Duration(days: 365)),
      selectableDayPredicate: (date) {
        final normalized = DateTime(date.year, date.month, date.day);
        if (normalized.isBefore(start)) return false;
        return !_isHoliday(normalized);
      },
    );
  }

  bool _isHoliday(DateTime date) {
    final fixed = <String>{
      '${date.year}-01-01', // 신정
      '${date.year}-03-01', // 삼일절
      '${date.year}-05-05', // 어린이날
      '${date.year}-06-06', // 현충일
      '${date.year}-08-15', // 광복절
      '${date.year}-10-03', // 개천절
      '${date.year}-10-09', // 한글날
      '${date.year}-12-25', // 성탄절
    };
    final key = DateFormat('yyyy-MM-dd').format(date);
    if (fixed.contains(key)) return true;
    final weekday = date.weekday;
    return weekday == DateTime.saturday || weekday == DateTime.sunday;
  }

  Future<String> _promptPhoneNumber(BuildContext context) async {
    final controller = TextEditingController();
    String? value = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('배송 요청 전화번호'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: '전화번호 입력',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                final phone = await pickContactPhone(dialogContext);
                if (phone == null || phone.trim().isEmpty) return;
                controller.text = phone;
              },
              child: const Text('주소록'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('확인'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return value ?? '';
  }
}

class DebugLogEntry {
  DebugLogEntry(this.timestamp, this.message);

  final DateTime timestamp;
  final String message;
}
