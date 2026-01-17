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
      return;
    }

    final folderId = await _ensureAppFolder();
    final sheetsApi = await _sheetsApi();
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
    final driveApi = await _driveApi();
    final permission = drive.Permission(
      type: 'user',
      role: 'writer',
      emailAddress: email,
    );
    await driveApi.permissions.create(permission, sheetId, sendNotificationEmail: false);
  }

  Future<void> shareAppFolder(String email) async {
    final folderId = await _ensureAppFolder();
    if (folderId.isEmpty) {
      return;
    }
    final driveApi = await _driveApi();
    final permission = drive.Permission(
      type: 'user',
      role: 'writer',
      emailAddress: email,
    );
    await driveApi.permissions.create(permission, folderId, sendNotificationEmail: false);
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
      final value =
          row.length > 2 ? double.tryParse('${row[2]}') ?? 0.0 : 0.0;
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
      final inflow =
          row.length > 3 ? double.tryParse('${row[3]}') ?? 0.0 : 0.0;
      final outflow =
          row.length > 4 ? double.tryParse('${row[4]}') ?? 0.0 : 0.0;
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
    final sheetsApi = await _sheetsApi();
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

  Future<List<List<Object?>>?> _getValues(String range) async {
    final sheetsApi = await _sheetsApi();
    final sheetId = await _currentSheetId();
    final response = await sheetsApi.spreadsheets.values.get(sheetId, range);
    return response.values;
  }

  Future<SheetsApi> _sheetsApi() async {
    final headers = await _authService?.authHeaders() ?? {};
    final client = GoogleAuthClient(headers);
    return SheetsApi(client);
  }

  Future<drive.DriveApi> _driveApi() async {
    final headers = await _authService?.authHeaders() ?? {};
    final client = GoogleAuthClient(headers);
    return drive.DriveApi(client);
  }

  Future<String> _ensureAppFolder() async {
    _prefs ??= await SharedPreferences.getInstance();
    final cached = _prefs?.getString('driveFolderId');
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final driveApi = await _driveApi();
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
    final driveApi = await _driveApi();
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

  String _currentMonthKey() {
    return DateFormat('yyyy-MM').format(DateTime.now());
  }

  String _sheetIdKey(String monthKey) => 'sheetId_$monthKey';
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
