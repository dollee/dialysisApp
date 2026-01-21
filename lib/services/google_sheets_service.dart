import 'dart:collection';

import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis/sheets/v4.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'google_api_client.dart';
import 'google_auth_service.dart';

class GoogleSheetsService {
  GoogleAuthService? _authService;
  SharedPreferences? _prefs;

  Future<void> bindAuth(GoogleAuthService authService) async {
    _authService = authService;
    _prefs ??= await SharedPreferences.getInstance();
  }

  Future<void> ensureCurrentMonthSheet() async {
    final monthKey = _currentMonthKey();
    final existingId = _prefs?.getString(_sheetIdKey(monthKey));
    if (existingId != null && existingId.isNotEmpty) {
      final trashedOrMissing = await _isFileTrashedOrMissing(existingId);
      if (!trashedOrMissing) {
        return;
      }
      await _prefs?.remove(_sheetIdKey(monthKey));
    }

    final folderId = await _ensureAppFolder();
    final sheetsApi = await _sheetsApi(promptIfNecessary: false);
    if (sheetsApi == null) {
      return;
    }
    final spreadsheet = Spreadsheet(
      properties: SpreadsheetProperties(
        title: 'Dialysis $monthKey',
      ),
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
    if (existingId != null && existingId.isNotEmpty) {
      final trashedOrMissing = await _isFileTrashedOrMissing(existingId);
      if (trashedOrMissing) {
        await _prefs?.remove('inventorySheetId');
      } else {
        final folderId = await _ensureAppFolder();
        await _ensureSheetTabsExist(
          existingId,
          ['owned', 'pending', 'defective'],
        );
        if (folderId.isNotEmpty) {
          await _moveFileToFolder(existingId, folderId);
        }
        return existingId;
      }
    }
    final folderId = await _ensureAppFolder();
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      return '';
    }
    final spreadsheet = Spreadsheet(
      properties: SpreadsheetProperties(
        title: '투석물품 재고관리',
      ),
      sheets: [
        Sheet(properties: SheetProperties(title: 'owned')),
        Sheet(properties: SheetProperties(title: 'pending')),
        Sheet(properties: SheetProperties(title: 'defective')),
      ],
    );
    final created = await sheetsApi.spreadsheets.create(spreadsheet);
    final sheetId = created.spreadsheetId ?? '';
    await _prefs?.setString('inventorySheetId', sheetId);
    if (sheetId.isNotEmpty && folderId.isNotEmpty) {
      await _moveFileToFolder(sheetId, folderId);
    }
    await _appendRowsById(
      sheetId,
      'owned',
      [
        _inventoryHeaderRow(),
      ],
    );
    await _appendRowsById(
      sheetId,
      'pending',
      [
        _inventoryHeaderRow(),
      ],
    );
    await _appendRowsById(
      sheetId,
      'defective',
      [
        _inventoryHeaderRow(),
      ],
    );
    return sheetId;
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
      final file = await driveApi.files.get(
        sheetId,
        $fields: 'id, name, parents, webViewLink, trashed',
      ) as drive.File;
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
    await driveApi.permissions
        .create(permission, sheetId, sendNotificationEmail: false);
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
    await driveApi.permissions
        .create(permission, folderId, sendNotificationEmail: false);
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
    return values.where((row) => row.isNotEmpty && row.first == dateText).length;
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
      final date = row.length > 0 ? '${row[0]}' : '';
      final time = row.length > 1 ? '${row[1]}' : '';
      final value = row.length > 2 ? double.tryParse('${row[2]}') ?? 0.0 : 0.0;
      return WeightEntry(date: date, time: time, weight: value);
    }).toList();
  }

  List<BloodPressureEntry> _mapPressure(List<List<Object?>>? values) {
    if (values == null) return [];
    return values.map((row) {
      final date = row.length > 0 ? '${row[0]}' : '';
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
      final date = row.length > 0 ? '${row[0]}' : '';
      final time = row.length > 1 ? '${row[1]}' : '';
      final session = row.length > 2 ? int.tryParse('${row[2]}') ?? 0 : 0;
      final inflow = row.length > 3 ? double.tryParse('${row[3]}') ?? 0.0 : 0.0;
      final outflow = row.length > 4 ? double.tryParse('${row[4]}') ?? 0.0 : 0.0;
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
    final sheetsApi = await _sheetsApi(promptIfNecessary: true);
    if (sheetsApi == null) {
      return;
    }
    final sheetId = await _currentSheetId();
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
    final existing = spreadsheet.sheets
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
        return null;
      }
      return SheetsApi(client);
    } catch (_) {
      return null;
    }
  }

  Future<drive.DriveApi?> _driveApi({required bool promptIfNecessary}) async {
    try {
      final client = await _authService?.getAuthenticatedClient(
        promptIfNecessary: promptIfNecessary,
      );
      if (client == null) {
        return null;
      }
      return drive.DriveApi(client);
    } catch (_) {
      return null;
    }
  }

  Future<String> _ensureAppFolder() async {
    _prefs ??= await SharedPreferences.getInstance();
    final cached = _prefs?.getString('driveFolderId');
    if (cached != null && cached.isNotEmpty) {
      final trashedOrMissing = await _isFileTrashedOrMissing(cached);
      if (!trashedOrMissing) {
        return cached;
      }
      await _prefs?.remove('driveFolderId');
    }
    final driveApi = await _driveApi(promptIfNecessary: true);
    if (driveApi == null) {
      return '';
    }
    final response = await driveApi.files.list(
      q: "mimeType='application/vnd.google-apps.folder' "
          "and name='투석결과App' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id, name)',
    );
    if (response.files != null && response.files!.isNotEmpty) {
      final folderId = response.files!.first.id ?? '';
      if (folderId.isNotEmpty) {
        await _prefs?.setString('driveFolderId', folderId);
        return folderId;
      }
    }
    final created = await driveApi.files.create(
      drive.File(
        name: '투석결과App',
        mimeType: 'application/vnd.google-apps.folder',
      ),
    );
    final folderId = created.id ?? '';
    if (folderId.isNotEmpty) {
      await _prefs?.setString('driveFolderId', folderId);
    }
    return folderId;
  }

  Future<void> _moveFileToFolder(String fileId, String folderId) async {
    final driveApi = await _driveApi(promptIfNecessary: true);
    if (driveApi == null) {
      return;
    }
    final file = await driveApi.files.get(
      fileId,
      $fields: 'parents',
    ) as drive.File;
    final previousParents = file.parents?.join(',') ?? '';
    await driveApi.files.update(
      drive.File(),
      fileId,
      addParents: folderId,
      removeParents: previousParents.isEmpty ? null : previousParents,
      $fields: 'id, parents',
    );
  }

  Future<bool> _isFileTrashedOrMissing(String fileId) async {
    try {
      final driveApi = await _driveApi(promptIfNecessary: false);
      if (driveApi == null) {
        return true;
      }
      final file = await driveApi.files.get(
        fileId,
        $fields: 'trashed',
      ) as drive.File;
      return file.trashed == true;
    } catch (_) {
      return true;
    }
  }

  String _currentMonthKey() {
    return DateFormat('yyyy-MM').format(DateTime.now());
  }

  String _sheetIdKey(String monthKey) => 'sheetId_$monthKey';

  List<Object?> _inventoryHeaderRow() {
    return [
      'timestamp',
      '1.5 2리터',
      '2.3 2리터',
      '4.3 2리터',
      '1.5 3리터',
      '2.3 3리터',
      '4.3 f리터',
      '겟트',
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
  WeightEntry({
    required this.date,
    required this.time,
    required this.weight,
  });

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
