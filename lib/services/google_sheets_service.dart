import 'dart:collection';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_auth_service.dart';

class GoogleSheetsService {
  GoogleAuthService? _authService;
  SharedPreferences? _prefs;

  Future<void> bindAuth(GoogleAuthService authService) async {
    _authService = authService;
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// 재고 시트 내부 탭 이름 (재고 시트에는 더 이상 설정 탭 없음)
  static const _settingsSheetName = 'settings';

  /// 설정 전용 스프레드시트 파일 제목 (Drive에 "투석 설정" 파일로 저장)
  static const _settingsFileTitle = '투석 설정';
  static const _settingsFilePrefKey = 'settingsSheetId';

  Future<void> ensureCurrentMonthSheet() async {
    _prefs ??= await SharedPreferences.getInstance();
    final monthKey = _currentMonthKey();
    final existingId = _prefs?.getString(_sheetIdKey(monthKey));
    // 이미 저장된 월별 시트 ID가 있을 때, 위치와 상태를 검증한다.
    if (existingId != null && existingId.isNotEmpty) {
      // 1) 파일이 휴지통이거나 존재하지 않으면 무시하고 새로 생성
      final trashedOrMissing = await _isFileTrashedOrMissing(existingId);
      final appFolderId = await _ensureAppFolder();
      final inAppFolder = await _isFileInFolder(
        existingId,
        appFolderId,
      ); // '투석결과App' 여부

      if (!trashedOrMissing && inAppFolder) {
        // 정상적인 위치(투석결과App 폴더)에 있고, 삭제되지 않은 경우 그대로 사용
        return;
      }

      // 여기까지 왔다면: 삭제되었거나, 다른 폴더에 있거나, 정보 조회 실패 → 새로 생성
      await _prefs?.remove(_sheetIdKey(monthKey));
    }

    final folderId = await _ensureAppFolder();
    // 새 시트 생성 시 필요하면 재인증 유도(promptIfNecessary: true)해 데이터 반영 보장
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      return;
    }
    final spreadsheet = Spreadsheet(
      properties: SpreadsheetProperties(title: 'Dialysis $monthKey'),
      sheets: [
        Sheet(properties: SheetProperties(title: 'dialysis_machine')),
        Sheet(properties: SheetProperties(title: 'dialysis_manual')),
        Sheet(properties: SheetProperties(title: 'weight')),
        Sheet(properties: SheetProperties(title: 'blood_pressure')),
      ],
    );
    final created = await sheetsApi.spreadsheets.create(spreadsheet);
    final sheetId = created.spreadsheetId ?? '';
    await _prefs?.setString(_sheetIdKey(monthKey), sheetId);
    if (sheetId.isNotEmpty && folderId.isNotEmpty) {
      await _moveFileToFolder(sheetId, folderId);
    }
  }

  Future<String> ensureInventorySheet() async {
    _prefs ??= await SharedPreferences.getInstance();
    final existingId = _prefs?.getString('inventorySheetId');
    // 이미 저장된 시트 ID가 있을 때, 위치와 상태를 검증한다.
    if (existingId != null && existingId.isNotEmpty) {
      // ignore: avoid_print
      print('[Sheets] ensureInventorySheet: existingId=$existingId 검증 시작');
      // 1) 파일이 휴지통이거나 존재하지 않으면 무시하고 새로 생성
      final trashedOrMissing = await _isFileTrashedOrMissing(existingId);
      final appFolderId = await _ensureAppFolder();
      final inAppFolder = await _isFileInFolder(
        existingId,
        appFolderId,
      ); // '투석결과App' 여부

      if (!trashedOrMissing && inAppFolder) {
        // 정상적인 위치(투석결과App 폴더)에 있고, 삭제되지 않은 경우 그대로 사용
        // ignore: avoid_print
        print(
          '[Sheets] ensureInventorySheet: 기존 시트 유효 → 탭 확인 후 사용 existingId=$existingId',
        );
        await _ensureSheetTabsExist(existingId, [
          'owned',
          'pending',
          'defective',
        ]);
        return existingId;
      }

      // 여기까지 왔다면: 삭제되었거나, 다른 폴더에 있거나, 정보 조회 실패 → 새로 생성
      await _prefs?.remove('inventorySheetId');
      // ignore: avoid_print
      print('[Sheets] ensureInventorySheet: 기존 ID 무효 → 재생성 준비');
    }
    // ignore: avoid_print
    print('[Sheets] ensureInventorySheet: 앱 폴더 확인 중...');
    final folderId = await _ensureAppFolder();
    // ignore: avoid_print
    print(
      '[Sheets] ensureInventorySheet: folderId=${folderId.isEmpty ? "없음" : folderId}',
    );
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      // ignore: avoid_print
      print('[Sheets] ensureInventorySheet: sheetsApi=null → 종료');
      return '';
    }
    final spreadsheet = Spreadsheet(
      properties: SpreadsheetProperties(title: '투석물품 재고관리'),
      sheets: [
        Sheet(properties: SheetProperties(title: 'owned')),
        Sheet(properties: SheetProperties(title: 'pending')),
        Sheet(properties: SheetProperties(title: 'defective')),
      ],
    );
    // ignore: avoid_print
    print('[Sheets] ensureInventorySheet: 새 스프레드시트 생성 요청');
    final created = await sheetsApi.spreadsheets.create(spreadsheet);
    final sheetId = created.spreadsheetId ?? '';
    // ignore: avoid_print
    print('[Sheets] ensureInventorySheet: created.sheetId=$sheetId');
    await _prefs?.setString('inventorySheetId', sheetId);
    if (sheetId.isNotEmpty && folderId.isNotEmpty) {
      await _moveFileToFolder(sheetId, folderId);
    }
    await _appendRowsById(sheetId, 'owned', [_inventoryHeaderRow()]);
    await _appendRowsById(sheetId, 'pending', [_inventoryHeaderRow()]);
    await _appendRowsById(sheetId, 'defective', [_inventoryHeaderRow()]);
    // ignore: avoid_print
    print('[Sheets] ensureInventorySheet: 재고 시트/헤더까지 생성 완료');
    return sheetId;
  }

  /// 설정 전용 스프레드시트 파일(투석 설정)을 확인·생성한다.
  /// - 저장 위치: 투석결과App 폴더 안 "투석 설정" 파일
  Future<String> ensureSettingsSheet() async {
    _prefs ??= await SharedPreferences.getInstance();
    final existingId = _prefs?.getString(_settingsFilePrefKey);
    if (existingId != null && existingId.isNotEmpty) {
      // ignore: avoid_print
      print('[Sheets] ensureSettingsSheet: existingId=$existingId 검증 시작');
      final trashedOrMissing = await _isFileTrashedOrMissing(existingId);
      final appFolderId = await _ensureAppFolder();
      final inAppFolder = await _isFileInFolder(existingId, appFolderId);
      if (!trashedOrMissing && inAppFolder) {
        // ignore: avoid_print
        print('[Sheets] ensureSettingsSheet: 기존 설정 파일 유효 → 사용');
        return existingId;
      }
      await _prefs?.remove(_settingsFilePrefKey);
      // ignore: avoid_print
      print('[Sheets] ensureSettingsSheet: 기존 ID 무효 → 재생성 준비');
    }
    final folderId = await _ensureAppFolder();
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      // ignore: avoid_print
      print('[Sheets] ensureSettingsSheet: sheetsApi=null → 종료');
      return '';
    }
    final spreadsheet = Spreadsheet(
      properties: SpreadsheetProperties(title: _settingsFileTitle),
      sheets: [Sheet(properties: SheetProperties(title: _settingsSheetName))],
    );
    // ignore: avoid_print
    print('[Sheets] ensureSettingsSheet: 새 설정 파일 생성 요청');
    final created = await sheetsApi.spreadsheets.create(spreadsheet);
    final sheetId = created.spreadsheetId ?? '';
    await _prefs?.setString(_settingsFilePrefKey, sheetId);
    if (sheetId.isNotEmpty && folderId.isNotEmpty) {
      await _moveFileToFolder(sheetId, folderId);
    }
    await _appendRowsById(sheetId, _settingsSheetName, [
      ['key', 'value'],
    ]);
    // ignore: avoid_print
    print('[Sheets] ensureSettingsSheet: 설정 파일 생성 완료 sheetId=$sheetId');
    return sheetId;
  }

  /// Google Sheets 설정 파일(투석 설정)에서 설정값을 불러온다.
  Future<Map<String, String>> loadSettingsFromSheet() async {
    _prefs ??= await SharedPreferences.getInstance();
    final sheetId =
        _prefs?.getString(_settingsFilePrefKey) ?? await ensureSettingsSheet();
    if (sheetId.isEmpty) {
      // ignore: avoid_print
      print('[Sheets] loadSettingsFromSheet: sheetId 없음 → 빈 맵');
      return {};
    }

    final sheetsApi = await _sheetsApi(promptIfNecessary: false);
    if (sheetsApi == null) {
      // ignore: avoid_print
      print('[Sheets] loadSettingsFromSheet: sheetsApi null → 빈 맵');
      return {};
    }

    try {
      final resp = await sheetsApi.spreadsheets.values.get(
        sheetId,
        '$_settingsSheetName!A:B',
      );
      final values = resp.values;
      if (values != null && values.length > 1) {
        final Map<String, String> result = {};
        for (var i = 1; i < values.length; i++) {
          final row = values[i];
          if (row.isEmpty || row.length < 2) continue;
          final key = '${row[0]}'.trim();
          final value = '${row[1]}'.trim();
          if (key.isEmpty) continue;
          result[key] = value;
        }
        // ignore: avoid_print
        print(
          '[Sheets] loadSettingsFromSheet: 성공(설정 파일) sheetId=$sheetId 키 ${result.length}개',
        );
        return result;
      }

      // ignore: avoid_print
      print(
        '[Sheets] loadSettingsFromSheet: 데이터 없음(행 ${values?.length ?? 0}) → 빈 맵',
      );
      return {};
    } catch (e) {
      // ignore: avoid_print
      print('[Sheets] loadSettingsFromSheet 예외: $e → 빈 맵');
      return {};
    }
  }

  /// 현재 설정값을 설정 전용 파일(투석 설정)에 저장한다.
  Future<void> saveSettingsToSheet(Map<String, String> settings) async {
    if (settings.isEmpty) {
      // ignore: avoid_print
      print('[Sheets] saveSettingsToSheet: settings 비어 있음 → 스킵');
      return;
    }
    _prefs ??= await SharedPreferences.getInstance();
    final sheetId =
        _prefs?.getString(_settingsFilePrefKey) ?? await ensureSettingsSheet();
    if (sheetId.isEmpty) {
      // ignore: avoid_print
      print('[Sheets] saveSettingsToSheet: sheetId 없음 → 스킵');
      return;
    }

    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      // ignore: avoid_print
      print('[Sheets] saveSettingsToSheet: sheetsApi null → 스킵');
      return;
    }

    try {
      // ignore: avoid_print
      print('[Sheets] saveSettingsToSheet: clear 시작 sheetId=$sheetId');
      // NOTE: clear(request, spreadsheetId, range) 순서여야 한다.
      await sheetsApi.spreadsheets.values.clear(
        ClearValuesRequest(),
        sheetId,
        '$_settingsSheetName!A:Z',
      );
      // ignore: avoid_print
      print(
        '[Sheets] saveSettingsToSheet: clear 완료, append ${settings.length}개 행',
      );

      final rows = <List<Object>>[
        ['key', 'value'],
        for (final entry in settings.entries) [entry.key, entry.value],
      ];

      await _appendRowsById(sheetId, _settingsSheetName, rows);
      // ignore: avoid_print
      print('[Sheets] saveSettingsToSheet: 완료 sheetId=$sheetId');
    } catch (e, st) {
      // ignore: avoid_print
      print('[Sheets] saveSettingsToSheet 예외: $e');
      // ignore: avoid_print
      print(
        '[Sheets] saveSettingsToSheet 스택: ${st.toString().split('\n').take(2).join(' ')}',
      );
    }
  }

  Future<InventoryStorageInfo> getInventoryStorageInfo() async {
    _prefs ??= await SharedPreferences.getInstance();
    final sheetId = _prefs?.getString('inventorySheetId') ?? '';
    final folderId = _prefs?.getString('driveFolderId') ?? '';
    if (sheetId.isEmpty) {
      return InventoryStorageInfo(
        sheetId: '',
        fileName: '',
        folderId: folderId,
        parentIds: '',
        webViewLink: '',
        trashed: false,
        errorMessage: 'sheetId 없음',
      );
    }
    try {
      final driveApi = await _driveApi(promptIfNecessary: false);
      if (driveApi == null) {
        return InventoryStorageInfo(
          sheetId: sheetId,
          fileName: '',
          folderId: folderId,
          parentIds: '',
          webViewLink: '',
          trashed: false,
          errorMessage: 'auth_required',
        );
      }
      final file =
          await driveApi.files.get(
                sheetId,
                $fields: 'id, name, parents, webViewLink, trashed',
              )
              as drive.File;
      return InventoryStorageInfo(
        sheetId: sheetId,
        fileName: file.name ?? '',
        folderId: folderId,
        parentIds: (file.parents ?? []).join(','),
        webViewLink: file.webViewLink ?? '',
        trashed: file.trashed ?? false,
        errorMessage: '',
      );
    } catch (error) {
      return InventoryStorageInfo(
        sheetId: sheetId,
        fileName: '',
        folderId: folderId,
        parentIds: '',
        webViewLink: '',
        trashed: false,
        errorMessage: error.toString(),
      );
    }
  }

  Future<String> getDriveUserEmail() async {
    try {
      final driveApi = await _driveApi(promptIfNecessary: false);
      if (driveApi == null) {
        return '';
      }
      final about = await driveApi.about.get($fields: 'user(emailAddress)');
      return about.user?.emailAddress ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<String> _currentSheetId() async {
    final monthKey = _currentMonthKey();
    final sheetId = _prefs?.getString(_sheetIdKey(monthKey));
    if (sheetId == null || sheetId.isEmpty) {
      await ensureCurrentMonthSheet();
      return _prefs?.getString(_sheetIdKey(monthKey)) ?? '';
    }
    return sheetId;
  }

  Future<void> shareCurrentMonth(String email) async {
    final sheetId = await _currentSheetId();
    if (sheetId.isEmpty) {
      return;
    }
    final driveApi = await _driveApi(promptIfNecessary: true);
    if (driveApi == null) {
      return;
    }
    final permission = drive.Permission(
      type: 'user',
      role: 'writer',
      emailAddress: email,
    );
    await driveApi.permissions.create(
      permission,
      sheetId,
      sendNotificationEmail: false,
    );
  }

  Future<void> shareAppFolder(String email) async {
    await ensureInventorySheet();
    final folderId = await _ensureAppFolder();
    if (folderId.isEmpty) {
      return;
    }
    final driveApi = await _driveApi(promptIfNecessary: true);
    if (driveApi == null) {
      return;
    }
    final permission = drive.Permission(
      type: 'user',
      role: 'writer',
      emailAddress: email,
    );
    await driveApi.permissions.create(
      permission,
      folderId,
      sendNotificationEmail: false,
    );
  }

  Future<InventorySnapshot> fetchLatestInventory(String section) async {
    await ensureInventorySheet();
    final sheetId = _prefs?.getString('inventorySheetId') ?? '';
    if (sheetId.isEmpty) {
      return InventorySnapshot.empty();
    }
    final values = await _getValuesById(sheetId, '$section!A2:J');
    if (values == null || values.isEmpty) {
      return InventorySnapshot.empty();
    }
    final last = values.last;
    final numbers = <int>[];
    for (var i = 1; i < 9; i++) {
      if (last.length > i) {
        numbers.add(int.tryParse('${last[i]}') ?? 0);
      } else {
        numbers.add(0);
      }
    }
    return InventorySnapshot(values: numbers);
  }

  Future<void> appendInventory(
    String section,
    List<int> values, {
    required bool autoRequest,
  }) async {
    await ensureInventorySheet();
    final sheetId = _prefs?.getString('inventorySheetId') ?? '';
    if (sheetId.isEmpty) {
      return;
    }
    final row = [
      DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      ...values,
      autoRequest ? 'ON' : 'OFF',
    ];
    await _appendRowsById(sheetId, section, [row]);
  }

  Future<void> appendMachineDialysis(List<DialysisRow> rows) async {
    await _appendRows(
      'dialysis_machine',
      rows.map((row) => row.toRow()).toList(),
    );
  }

  Future<void> appendManualDialysis(List<DialysisRow> rows) async {
    await _appendRows(
      'dialysis_manual',
      rows.map((row) => row.toRow()).toList(),
    );
  }

  Future<void> appendWeight(WeightEntry entry) async {
    await _appendRows('weight', [entry.toRow()]);
  }

  Future<void> appendBloodPressure(BloodPressureEntry entry) async {
    await _appendRows('blood_pressure', [entry.toRow()]);
  }

  Future<int> getManualDialysisCountForDate(DateTime date) async {
    final values = await _getValues('dialysis_manual!A2:A');
    if (values == null) {
      return 0;
    }
    final dateText = DateFormat('yyyy-MM-dd').format(date);
    return values
        .where((row) => row.isNotEmpty && row.first == dateText)
        .length;
  }

  Future<MonthlyData> fetchMonthlyData() async {
    final weight = await _getValues('weight!A2:C');
    final pressure = await _getValues('blood_pressure!A2:D');
    final machine = await _getValues('dialysis_machine!A2:E');
    final manual = await _getValues('dialysis_manual!A2:E');
    return MonthlyData(
      weight: _mapWeight(weight),
      bloodPressure: _mapPressure(pressure),
      machineDialysis: _mapDialysis(machine),
      manualDialysis: _mapDialysis(manual),
    );
  }

  List<WeightEntry> _mapWeight(List<List<Object?>>? values) {
    if (values == null) return [];
    return values.map((row) {
      final date = row.isNotEmpty ? '${row[0]}' : '';
      final time = row.length > 1 ? '${row[1]}' : '';
      final value = row.length > 2 ? double.tryParse('${row[2]}') ?? 0.0 : 0.0;
      return WeightEntry(date: date, time: time, weight: value);
    }).toList();
  }

  List<BloodPressureEntry> _mapPressure(List<List<Object?>>? values) {
    if (values == null) return [];
    return values.map((row) {
      final date = row.isNotEmpty ? '${row[0]}' : '';
      final time = row.length > 1 ? '${row[1]}' : '';
      final systolic = row.length > 2 ? int.tryParse('${row[2]}') ?? 0 : 0;
      final diastolic = row.length > 3 ? int.tryParse('${row[3]}') ?? 0 : 0;
      return BloodPressureEntry(
        date: date,
        time: time,
        systolic: systolic,
        diastolic: diastolic,
      );
    }).toList();
  }

  List<DialysisRow> _mapDialysis(List<List<Object?>>? values) {
    if (values == null) return [];
    return values.map((row) {
      final date = row.isNotEmpty ? '${row[0]}' : '';
      final time = row.length > 1 ? '${row[1]}' : '';
      final session = row.length > 2 ? int.tryParse('${row[2]}') ?? 0 : 0;
      final inflow = row.length > 3 ? double.tryParse('${row[3]}') ?? 0.0 : 0.0;
      final outflow = row.length > 4
          ? double.tryParse('${row[4]}') ?? 0.0
          : 0.0;
      return DialysisRow(
        date: date,
        time: time,
        session: session,
        inflow: inflow,
        outflow: outflow,
      );
    }).toList();
  }

  Future<void> _appendRows(String sheetName, List<List<Object?>> rows) async {
    if (rows.isEmpty) return;
    final sheetId = await _currentSheetId();
    if (sheetId.isEmpty) {
      throw StateError('월별 데이터 시트가 없습니다. 앱을 다시 실행하거나 로그인 후 다시 시도해주세요.');
    }
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      throw StateError('Google 시트 연결에 실패했습니다. 로그인 상태를 확인해주세요.');
    }
    final valueRange = ValueRange(values: rows);
    await sheetsApi.spreadsheets.values.append(
      valueRange,
      sheetId,
      '$sheetName!A:E',
      valueInputOption: 'USER_ENTERED',
      insertDataOption: 'INSERT_ROWS',
    );
  }

  Future<void> _appendRowsById(
    String sheetId,
    String sheetName,
    List<List<Object?>> rows,
  ) async {
    if (rows.isEmpty) return;
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      return;
    }
    final valueRange = ValueRange(values: rows);
    await sheetsApi.spreadsheets.values.append(
      valueRange,
      sheetId,
      '$sheetName!A:J',
      valueInputOption: 'USER_ENTERED',
      insertDataOption: 'INSERT_ROWS',
    );
  }

  Future<List<List<Object?>>?> _getValues(String range) async {
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      return null;
    }
    final sheetId = await _currentSheetId();
    final response = await sheetsApi.spreadsheets.values.get(sheetId, range);
    return response.values;
  }

  Future<List<List<Object?>>?> _getValuesById(
    String sheetId,
    String range,
  ) async {
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      return null;
    }
    final response = await sheetsApi.spreadsheets.values.get(sheetId, range);
    return response.values;
  }

  Future<void> _ensureSheetTabsExist(
    String sheetId,
    List<String> titles,
  ) async {
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      return;
    }
    final spreadsheet = await sheetsApi.spreadsheets.get(
      sheetId,
      includeGridData: false,
    );
    final existing =
        spreadsheet.sheets
            ?.map((sheet) => sheet.properties?.title)
            .whereType<String>()
            .toSet() ??
        {};
    final requests = <Request>[];
    for (final title in titles) {
      if (!existing.contains(title)) {
        requests.add(
          Request(
            addSheet: AddSheetRequest(
              properties: SheetProperties(title: title),
            ),
          ),
        );
      }
    }
    if (requests.isEmpty) return;
    await sheetsApi.spreadsheets.batchUpdate(
      BatchUpdateSpreadsheetRequest(requests: requests),
      sheetId,
    );
  }

  Future<SheetsApi?> _sheetsApi({required bool promptIfNecessary}) async {
    try {
      final client = await _authService?.getAuthenticatedClient(
        promptIfNecessary: promptIfNecessary,
      );
      if (client == null) {
        // ignore: avoid_print
        print(
          '[Sheets] _sheetsApi: getAuthenticatedClient 반환 null (promptIfNecessary=$promptIfNecessary)',
        );
        return null;
      }
      return SheetsApi(client);
    } catch (e, st) {
      // ignore: avoid_print
      print('[Sheets] _sheetsApi 예외: $e');
      // ignore: avoid_print
      print(
        '[Sheets] _sheetsApi 스택: ${st.toString().split('\n').take(2).join(' ')}',
      );
      return null;
    }
  }

  Future<drive.DriveApi?> _driveApi({required bool promptIfNecessary}) async {
    try {
      final client = await _authService?.getAuthenticatedClient(
        promptIfNecessary: promptIfNecessary,
      );
      if (client == null) {
        // ignore: avoid_print
        print(
          '[Sheets] _driveApi: getAuthenticatedClient 반환 null (promptIfNecessary=$promptIfNecessary)',
        );
        return null;
      }
      return drive.DriveApi(client);
    } catch (e, st) {
      // ignore: avoid_print
      print('[Sheets] _driveApi 예외: $e');
      // ignore: avoid_print
      print(
        '[Sheets] _driveApi 스택: ${st.toString().split('\n').take(2).join(' ')}',
      );
      return null;
    }
  }

  Future<String> _ensureAppFolder() async {
    _prefs ??= await SharedPreferences.getInstance();
    try {
      final cached = _prefs?.getString('driveFolderId');
      if (cached != null && cached.isNotEmpty) {
        // ignore: avoid_print
        print('[Sheets] _ensureAppFolder: 캐시 폴더 ID 확인 중...');
        final trashedOrMissing = await _isFileTrashedOrMissing(cached);
        if (!trashedOrMissing) {
          // ignore: avoid_print
          print('[Sheets] _ensureAppFolder: 캐시 폴더 사용 folderId=$cached');
          return cached;
        }
        await _prefs?.remove('driveFolderId');
        // ignore: avoid_print
        print('[Sheets] _ensureAppFolder: 캐시 폴더 무효(삭제/휴지통) → 재조회');
      }
      final driveApi = await _driveApi(promptIfNecessary: true);
      if (driveApi == null) {
        // ignore: avoid_print
        print('[Sheets] _ensureAppFolder: Drive API null → 폴더 없음 반환');
        return '';
      }
      // ignore: avoid_print
      print('[Sheets] _ensureAppFolder: "투석결과App" 폴더 검색 중...');
      final response = await driveApi.files.list(
        q:
            "mimeType='application/vnd.google-apps.folder' "
            "and name='투석결과App' and trashed=false",
        spaces: 'drive',
        $fields: 'files(id, name)',
      );
      if (response.files != null && response.files!.isNotEmpty) {
        final folderId = response.files!.first.id ?? '';
        if (folderId.isNotEmpty) {
          await _prefs?.setString('driveFolderId', folderId);
          // ignore: avoid_print
          print('[Sheets] _ensureAppFolder: 기존 폴더 발견 folderId=$folderId');
          return folderId;
        }
      }
      // ignore: avoid_print
      print('[Sheets] _ensureAppFolder: 폴더 없음 → 새로 생성');
      final created = await driveApi.files.create(
        drive.File(
          name: '투석결과App',
          mimeType: 'application/vnd.google-apps.folder',
        ),
      );
      final folderId = created.id ?? '';
      if (folderId.isNotEmpty) {
        await _prefs?.setString('driveFolderId', folderId);
        // ignore: avoid_print
        print('[Sheets] _ensureAppFolder: 폴더 생성 완료 folderId=$folderId');
      }
      return folderId;
    } catch (e, st) {
      // ignore: avoid_print
      print('[Sheets] _ensureAppFolder 예외: $e');
      // ignore: avoid_print
      print(
        '[Sheets] _ensureAppFolder 스택: ${st.toString().split('\n').take(2).join(' ')}',
      );
      return '';
    }
  }

  Future<void> _moveFileToFolder(String fileId, String folderId) async {
    final driveApi = await _driveApi(promptIfNecessary: true);
    if (driveApi == null) {
      // ignore: avoid_print
      print('[Sheets] _moveFileToFolder: Drive API null → 스킵');
      return;
    }
    try {
      final file =
          await driveApi.files.get(fileId, $fields: 'parents') as drive.File;
      final previousParents = file.parents?.join(',') ?? '';
      await driveApi.files.update(
        drive.File(),
        fileId,
        addParents: folderId,
        removeParents: previousParents.isEmpty ? null : previousParents,
        $fields: 'id, parents',
      );
      // ignore: avoid_print
      print(
        '[Sheets] _moveFileToFolder: 완료 fileId=$fileId → folderId=$folderId',
      );
    } catch (e) {
      // ignore: avoid_print
      print('[Sheets] _moveFileToFolder 예외: $e');
    }
  }

  Future<bool> _isFileTrashedOrMissing(String fileId) async {
    try {
      final driveApi = await _driveApi(promptIfNecessary: false);
      if (driveApi == null) {
        // ignore: avoid_print
        print('[Sheets] _isFileTrashedOrMissing: Drive API null → true(무효 처리)');
        return true;
      }
      final file =
          await driveApi.files.get(fileId, $fields: 'trashed') as drive.File;
      final trashed = file.trashed == true;
      // ignore: avoid_print
      print(
        '[Sheets] _isFileTrashedOrMissing: fileId=$fileId trashed=$trashed',
      );
      return trashed;
    } catch (e) {
      // ignore: avoid_print
      print('[Sheets] _isFileTrashedOrMissing 예외: $e → true');
      return true;
    }
  }

  /// 파일이 지정한 폴더(투석결과App)에 포함되어 있는지 확인한다.
  /// - 폴더가 비어 있거나, 조회에 실패하면 false 를 반환한다.
  Future<bool> _isFileInFolder(String fileId, String folderId) async {
    if (fileId.isEmpty || folderId.isEmpty) {
      // ignore: avoid_print
      print('[Sheets] _isFileInFolder: fileId 또는 folderId 비어 있음 → false');
      return false;
    }
    try {
      final driveApi = await _driveApi(promptIfNecessary: false);
      if (driveApi == null) {
        // ignore: avoid_print
        print('[Sheets] _isFileInFolder: Drive API null → false');
        return false;
      }
      final file =
          await driveApi.files.get(fileId, $fields: 'parents, trashed')
              as drive.File;
      if (file.trashed == true) {
        // ignore: avoid_print
        print('[Sheets] _isFileInFolder: fileId=$fileId 휴지통 → false');
        return false;
      }
      final parents = file.parents ?? const <String>[];
      final inFolder = parents.contains(folderId);
      // ignore: avoid_print
      print(
        '[Sheets] _isFileInFolder: fileId=$fileId folderId=$folderId inFolder=$inFolder parents=${parents.join(",")}',
      );
      return inFolder;
    } catch (e) {
      // ignore: avoid_print
      print('[Sheets] _isFileInFolder 예외: $e → false');
      return false;
    }
  }

  String _currentMonthKey() {
    return DateFormat('yyyy-MM').format(DateTime.now());
  }

  String _previousMonthKey(String monthKey) {
    try {
      final d = DateFormat('yyyy-MM').parse(monthKey);
      final prev = DateTime(d.year, d.month - 1, 1);
      return DateFormat('yyyy-MM').format(prev);
    } catch (_) {
      return monthKey;
    }
  }

  String _sheetIdKey(String monthKey) => 'sheetId_$monthKey';

  /// 오늘 포함 최근 30일 데이터 (추이 화면용). 현재월·전월 시트에서 병합 후 기간 필터.
  Future<MonthlyData> fetchLast30DaysData() async {
    _prefs ??= await SharedPreferences.getInstance();
    final now = DateTime.now();
    final endDate = DateTime(now.year, now.month, now.day);
    final startDate = endDate.subtract(const Duration(days: 29));
    final startStr = DateFormat('yyyy-MM-dd').format(startDate);
    final endStr = DateFormat('yyyy-MM-dd').format(endDate);

    final monthKey = _currentMonthKey();
    final currentSheetId = await _currentSheetId();
    List<WeightEntry> weight = [];
    List<BloodPressureEntry> bloodPressure = [];
    List<DialysisRow> machineDialysis = [];
    List<DialysisRow> manualDialysis = [];

    if (currentSheetId.isNotEmpty) {
      weight = _mapWeight(await _getValuesById(currentSheetId, 'weight!A2:C'));
      bloodPressure = _mapPressure(
        await _getValuesById(currentSheetId, 'blood_pressure!A2:D'),
      );
      machineDialysis = _mapDialysis(
        await _getValuesById(currentSheetId, 'dialysis_machine!A2:E'),
      );
      manualDialysis = _mapDialysis(
        await _getValuesById(currentSheetId, 'dialysis_manual!A2:E'),
      );
    }

    final prevMonthKey = _previousMonthKey(monthKey);
    final prevSheetId = _prefs?.getString(_sheetIdKey(prevMonthKey)) ?? '';
    if (prevSheetId.isNotEmpty) {
      final sheetsApi = await _sheetsApi(promptIfNecessary: false);
      if (sheetsApi != null) {
        try {
          final pm = await _getValuesById(prevSheetId, 'dialysis_machine!A2:E');
          final pma = await _getValuesById(prevSheetId, 'dialysis_manual!A2:E');
          final pw = await _getValuesById(prevSheetId, 'weight!A2:C');
          final pp = await _getValuesById(prevSheetId, 'blood_pressure!A2:D');
          machineDialysis = [..._mapDialysis(pm), ...machineDialysis];
          manualDialysis = [..._mapDialysis(pma), ...manualDialysis];
          weight = [..._mapWeight(pw), ...weight];
          bloodPressure = [..._mapPressure(pp), ...bloodPressure];
        } catch (_) {}
      }
    }

    bool inRange(String dateStr) {
      return dateStr.compareTo(startStr) >= 0 && dateStr.compareTo(endStr) <= 0;
    }

    return MonthlyData(
      weight: weight.where((e) => inRange(e.date)).toList(),
      bloodPressure: bloodPressure.where((e) => inRange(e.date)).toList(),
      machineDialysis: machineDialysis.where((e) => inRange(e.date)).toList(),
      manualDialysis: manualDialysis.where((e) => inRange(e.date)).toList(),
    );
  }

  List<Object?> _inventoryHeaderRow() {
    return [
      'timestamp',
      '1.5 2리터',
      '2.3 2리터',
      '4.3 2리터',
      '1.5 3리터',
      '2.3 3리터',
      '4.3 3리터',
      '세트',
      '배액백',
      'auto_request',
    ];
  }
}

class DialysisRow {
  DialysisRow({
    required this.date,
    required this.time,
    required this.session,
    required this.inflow,
    required this.outflow,
  });

  final String date;
  final String time;
  final int session;
  final double inflow;
  final double outflow;

  List<Object?> toRow() => [date, time, session, inflow, outflow];
}

class WeightEntry {
  WeightEntry({required this.date, required this.time, required this.weight});

  final String date;
  final String time;
  final double weight;

  List<Object?> toRow() => [date, time, weight];
}

class BloodPressureEntry {
  BloodPressureEntry({
    required this.date,
    required this.time,
    required this.systolic,
    required this.diastolic,
  });

  final String date;
  final String time;
  final int systolic;
  final int diastolic;

  List<Object?> toRow() => [date, time, systolic, diastolic];
}

class MonthlyData {
  MonthlyData({
    required this.weight,
    required this.bloodPressure,
    required this.machineDialysis,
    required this.manualDialysis,
  });

  final List<WeightEntry> weight;
  final List<BloodPressureEntry> bloodPressure;
  final List<DialysisRow> machineDialysis;
  final List<DialysisRow> manualDialysis;

  Map<String, double> sumDialysisByDate(List<DialysisRow> rows) {
    final map = HashMap<String, double>();
    for (final row in rows) {
      map[row.date] = (map[row.date] ?? 0) + row.outflow;
    }
    return map;
  }
}

class InventorySnapshot {
  InventorySnapshot({required this.values});

  final List<int> values;

  factory InventorySnapshot.empty() =>
      InventorySnapshot(values: List.filled(8, 0));
}

class InventoryStorageInfo {
  InventoryStorageInfo({
    required this.sheetId,
    required this.fileName,
    required this.folderId,
    required this.parentIds,
    required this.webViewLink,
    required this.trashed,
    required this.errorMessage,
  });

  final String sheetId;
  final String fileName;
  final String folderId;
  final String parentIds;
  final String webViewLink;
  final bool trashed;
  final String errorMessage;
}
